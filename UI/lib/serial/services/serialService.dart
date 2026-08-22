// ignore_for_file: file_names
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/core_client.dart';
import '../../core/core_deployment_service.dart';
import '../../core/root_shell_service.dart';
import '../../storage/services/disk_storage_service.dart';
import '../../usb/usb_session_service.dart';
import '../models/serialMessage.dart';
import '../models/serialMode.dart';
import 'serialEndpointService.dart';

class SerialServiceStatus {
  const SerialServiceStatus({
    required this.mode,
    required this.ready,
    this.endpoint,
    this.lastError,
  });
  final SerialMode mode;
  final bool ready;
  final String? endpoint, lastError;
  const SerialServiceStatus.off()
    : mode = SerialMode.off,
      ready = false,
      endpoint = null,
      lastError = null;
}

/// Routes the one endpoint in Dart. Core only creates the CDC ACM Function.
class SerialService {
  SerialService._() {
    _endpoint.received.listen(_onHostData);
  }
  static final instance = SerialService._();
  final _root = RootShellService();
  late final _client = CoreClient(_root);
  late final _session = UsbSessionService(
    _root,
    CoreDeploymentService(_root, _client),
    _client,
  );
  late final _endpoint = SerialEndpointService(_root);
  final _disks = DiskStorageService();
  final _statusChanges = StreamController<SerialServiceStatus>.broadcast();
  final _messageChanges = StreamController<List<SerialMessage>>.broadcast();
  final List<SerialMessage> _messages = [];
  SerialServiceStatus _status = const SerialServiceStatus.off();
  Process? _shell;
  bool _switching = false;
  static const _maxMessages = 3000;
  Stream<SerialServiceStatus> get status => _statusChanges.stream;
  Stream<List<SerialMessage>> get messages => _messageChanges.stream;
  SerialServiceStatus get currentStatus => _status;
  List<SerialMessage> get currentMessages => List.unmodifiable(_messages);

  /// Restores an already-active CDC function without issuing SET again. Route
  /// is Manager-local, so an externally active serial function resumes as User.
  Future<void> initialize() async {
    if (_status.mode != SerialMode.off) return;
    await CoreDeploymentService(_root, _client).ensureReady();
    final core = await _client.getStatus();
    if (!core.serial) return;
    await _endpoint.open();
    _setStatus(
      SerialServiceStatus(
        mode: SerialMode.user,
        ready: _endpoint.isOpen,
        endpoint: _endpoint.endpoint,
      ),
    );
  }

  Future<void> setMode(SerialMode target) async {
    if (_switching || target == _status.mode) return;
    final previous = _status;
    _switching = true;
    try {
      if (target == SerialMode.off) {
        await _stopShell();
        await _endpoint.close();
        await _session.apply(await _disks.load(), serialEnabled: false);
        _setStatus(const SerialServiceStatus.off());
        return;
      }
      if (previous.mode == SerialMode.off) {
        await _session.apply(await _disks.load(), serialEnabled: true);
        await _endpoint.open();
      }
      if (target == SerialMode.shell) {
        await _startShell();
      } else {
        await _stopShell();
      }
      _setStatus(
        SerialServiceStatus(
          mode: target,
          ready: _endpoint.isOpen,
          endpoint: _endpoint.endpoint,
        ),
      );
    } catch (error) {
      _setStatus(
        SerialServiceStatus(
          mode: previous.mode,
          ready: previous.ready,
          endpoint: previous.endpoint,
          lastError: '$error',
        ),
      );
      rethrow;
    } finally {
      _switching = false;
    }
  }

  Future<void> send(String text) async {
    if (!_status.ready || text.isEmpty) {
      throw StateError('serial endpoint is not ready');
    }
    final content = _status.mode == SerialMode.shell && !text.endsWith('\n')
        ? '$text\n'
        : text;
    final bytes = Uint8List.fromList(utf8.encode(content));
    if (_status.mode == SerialMode.shell) {
      final shell = _shell;
      if (shell == null) throw StateError('shell is unavailable');
      shell.stdin.add(bytes);
      await shell.stdin.flush();
    } else {
      await _endpoint.write(bytes);
      _add(SerialDirection.tx, utf8.decode(bytes, allowMalformed: true));
    }
  }

  Future<void> _startShell() async {
    if (_shell != null) return;
    // `sh -i` connected to Process pipes has no controlling terminal, which
    // breaks job control. KernelSU's BusyBox `script` allocates a PTY and
    // forwards its input/output through this process instead.
    final busybox = (await _root.runRootCommand(
      'command -v busybox || true',
    )).trim();
    if (busybox.isEmpty) {
      throw StateError('A BusyBox script PTY helper is unavailable');
    }
    final shell = await _root.startRootProcess(
      'exec ${RootShellService.shellQuote(busybox)} script -q -c ${RootShellService.shellQuote('exec /system/bin/sh -i')} /dev/null',
    );
    _shell = shell;
    shell.stdout.listen((bytes) async {
      try {
        await _endpoint.write(bytes);
        _add(SerialDirection.tx, utf8.decode(bytes, allowMalformed: true));
      } catch (_) {}
    });
    shell.stderr.drain();
    shell.exitCode.then((_) {
      if (identical(_shell, shell)) {
        _shell = null;
        _setStatus(
          SerialServiceStatus(
            mode: SerialMode.shell,
            ready: _endpoint.isOpen,
            endpoint: _endpoint.endpoint,
            lastError: 'shell exited',
          ),
        );
      }
    });
  }

  Future<void> _stopShell() async {
    final shell = _shell;
    _shell = null;
    if (shell != null) {
      await shell.stdin.close();
      shell.kill();
    }
  }

  void _onHostData(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    _add(SerialDirection.rx, text);
    if (_status.mode == SerialMode.shell) {
      final shell = _shell;
      if (shell != null) {
        shell.stdin.add(bytes);
        shell.stdin.flush();
      }
    }
  }

  void _add(SerialDirection direction, String message) {
    _messages.add(
      SerialMessage(
        timestamp: DateTime.now(),
        direction: direction,
        message: message,
      ),
    );
    if (_messages.length > _maxMessages) {
      _messages.removeRange(0, _messages.length - _maxMessages);
    }
    _messageChanges.add(List.unmodifiable(_messages));
  }

  void _setStatus(SerialServiceStatus value) {
    _status = value;
    _statusChanges.add(value);
  }
}
