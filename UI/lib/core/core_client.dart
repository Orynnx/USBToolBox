import 'dart:convert';
import 'root_shell_service.dart';

enum CoreErrorCode {
  invalidCommand,
  invalidConfigPath,
  configNotFound,
  invalidConfig,
  invalidVid,
  invalidPid,
  invalidDeviceVersion,
  imageNotFound,
  imageNotFile,
  duplicateBackingFile,
  notStarted,
  bootDisabled,
  applyFailed,
  restoreFailed,
  internalError,
  unavailable,
  timeout,
  unknown,
}

class CoreException implements Exception {
  CoreException(this.code, this.message);
  final CoreErrorCode code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class CoreStatus {
  CoreStatus({
    required this.active,
    required this.storageLuns,
    required this.keyboard,
    required this.serial,
    required this.uvc,
  });
  final bool active;
  final List<String> storageLuns;
  final bool keyboard;
  final bool serial;
  final bool uvc;
  factory CoreStatus.fromJson(Map<String, dynamic> json) => CoreStatus(
    active: json['state'] == 'active',
    storageLuns: ((json['storageLuns'] as List?) ?? const [])
        .map((v) {
          if (v is Map) return v['imagePath']?.toString() ?? '';
          return v?.toString() ?? '';
        })
        .where((v) => v.isNotEmpty)
        .toList(),
    keyboard: json['keyboard'] == true,
    serial: json['serial'] == true,
    uvc: json['uvc'] == true,
  );
}

class CoreImageProbe {
  const CoreImageProbe({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;

  factory CoreImageProbe.fromJson(Map<String, dynamic> json) => CoreImageProbe(
    path: json['path'] as String,
    sizeBytes: (json['sizeBytes'] as num).toInt(),
  );
}

class CoreClient {
  CoreClient(this._root);
  final RootShellService _root;
  static const socketPath = '/data/adb/usb_sub/usb.sock';

  Future<void> ping() async => _send('PING');
  Future<void> setConfig(String path) async => _send('SET $path');

  Future<CoreImageProbe> probeImage(String path) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'must be absolute');
    }
    final response = await _send('PROBE_IMAGE $path');
    try {
      return CoreImageProbe.fromJson(
        jsonDecode(response) as Map<String, dynamic>,
      );
    } catch (_) {
      throw CoreException(
        CoreErrorCode.unknown,
        'Core returned an invalid PROBE_IMAGE payload.',
      );
    }
  }

  Future<void> sendBootKey({
    List<String> modifiers = const [],
    String? key,
  }) async {
    final String command;
    if (key != null && key.isNotEmpty) {
      command = modifiers.isEmpty
          ? 'BOOT_KEY $key'
          : 'BOOT_KEY ${modifiers.join(' ')} $key';
    } else if (modifiers.isNotEmpty) {
      command = 'BOOT_KEY ${modifiers.join(' ')}';
    } else {
      throw ArgumentError('sendBootKey requires at least one modifier or key');
    }
    await _send(command);
  }

  Future<CoreStatus> getStatus() async {
    final response = await _send('STATUS');
    try {
      return CoreStatus.fromJson(jsonDecode(response) as Map<String, dynamic>);
    } catch (_) {
      throw CoreException(
        CoreErrorCode.unknown,
        'Core returned an invalid STATUS payload.',
      );
    }
  }

  Future<String> _send(String request) async {
    final payload = RootShellService.shellQuote('$request\n');
    final socket = RootShellService.shellQuote(socketPath);
    try {
      final output = await _root.runRootCommand(
        'printf %s $payload | toybox nc -w 10 -U $socket',
        timeout: const Duration(seconds: 15),
      );
      final line = output.trim();
      if (line == 'OK') return '';
      if (line.startsWith('OK ')) return line.substring(3);
      if (line.startsWith('ERR ')) throw _mapError(line.substring(4).trim());
      throw CoreException(
        CoreErrorCode.unavailable,
        'No valid response from HyperUSB Core.',
      );
    } on RootShellException catch (error) {
      throw CoreException(CoreErrorCode.unavailable, error.message);
    }
  }

  CoreException _mapError(String value) {
    const map = {
      'invalid_command': CoreErrorCode.invalidCommand,
      'invalid_config_path': CoreErrorCode.invalidConfigPath,
      'config_not_found': CoreErrorCode.configNotFound,
      'invalid_config': CoreErrorCode.invalidConfig,
      'invalid_vid': CoreErrorCode.invalidVid,
      'invalid_pid': CoreErrorCode.invalidPid,
      'invalid_device_version': CoreErrorCode.invalidDeviceVersion,
      'image_not_found': CoreErrorCode.imageNotFound,
      'image_not_file': CoreErrorCode.imageNotFile,
      'duplicate_backing_file': CoreErrorCode.duplicateBackingFile,
      'not_started': CoreErrorCode.notStarted,
      'boot_disabled': CoreErrorCode.bootDisabled,
      'apply_failed': CoreErrorCode.applyFailed,
      'restore_failed': CoreErrorCode.restoreFailed,
      'internal_error': CoreErrorCode.internalError,
    };
    return CoreException(map[value] ?? CoreErrorCode.unknown, value);
  }
}
