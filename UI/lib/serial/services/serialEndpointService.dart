import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/root_shell_service.dart';

/// The sole Manager-side owner of `/dev/ttyGS<n>`. It keeps one long-lived
/// root reader and writer; individual terminal sends never reopen the endpoint.
class SerialEndpointService {
  static const _readerPid = '/data/local/tmp/hyperusb-serial-reader.pid';
  static const _writerPid = '/data/local/tmp/hyperusb-serial-writer.pid';
  SerialEndpointService(this._root);
  final RootShellService _root;
  final _received = StreamController<Uint8List>.broadcast();
  Process? _reader;
  Process? _writer;
  String? endpoint;
  Stream<Uint8List> get received => _received.stream;
  bool get isOpen => _reader != null && _writer != null;

  Future<void> open() async {
    if (isOpen) return;
    await _stopRemoteWorker(_readerPid);
    await _stopRemoteWorker(_writerPid);
    endpoint = await _discoverEndpoint();
    // The endpoint is derived only from a digits-only ConfigFS port number,
    // never from user input; nesting another shell quote here would turn its
    // quote characters into part of the filename in the worker shell.
    final path = endpoint!;
    // ttyGS is a terminal device, not a line-oriented file. Raw mode is
    // required for immediate byte delivery from the host (including data
    // that does not end in a newline) and prevents the device side from
    // echoing or transforming it.
    await _root.runRootCommand(
      'stty -F ${RootShellService.shellQuote(path)} raw -echo -opost',
    );
    // ttyGS can return EIO before the Windows COM handle is opened. Keep the
    // same root process and retry the endpoint instead of reporting it closed.
    final reader = await _startWorker(
      _readerPid,
      'while :; do cat $path 2>/dev/null; sleep 1; done',
    );
    final writer = await _startWorker(
      _writerPid,
      'while :; do cat > $path 2>/dev/null; sleep 1; done',
    );
    _reader = reader;
    _writer = writer;
    reader.stdout.listen(
      (bytes) => _received.add(Uint8List.fromList(bytes)),
      onDone: _clearReader,
    );
    reader.stderr.drain();
    writer.stderr.drain();
    reader.exitCode.then((_) => _clearReader());
    writer.exitCode.then((_) => _clearWriter());
  }

  Future<void> write(List<int> bytes) async {
    final writer = _writer;
    if (writer == null) throw StateError('serial endpoint is not open');
    writer.stdin.add(bytes);
    await writer.stdin.flush();
  }

  Future<void> close() async {
    final reader = _reader;
    final writer = _writer;
    _reader = null;
    _writer = null;
    endpoint = null;
    await _stopRemoteWorker(_readerPid);
    await _stopRemoteWorker(_writerPid);
    if (reader != null) {
      await reader.stdin.close();
      reader.kill();
    }
    if (writer != null) {
      await writer.stdin.close();
      writer.kill();
    }
  }

  Future<Process> _startWorker(
    String pidFile,
    String loop,
  ) => _root.startRootProcess(
    // A dedicated session makes the worker PID a process-group leader, so a
    // close can terminate its currently-blocked `cat` child as well.
    'exec setsid sh -c ${RootShellService.shellQuote('echo \$\$ > $pidFile; exec sh -c ${RootShellService.shellQuote(loop)}')}',
  );

  Future<void> _stopRemoteWorker(String pidFile) async {
    final quoted = RootShellService.shellQuote(pidFile);
    await _root.runRootCommand(
      'if [ -r $quoted ]; then p=\$(cat $quoted); case \$p in *[!0-9]*|\'\') ;; *) kill -TERM -- -\$p 2>/dev/null || kill -TERM \$p 2>/dev/null || true ;; esac; fi; rm -f $quoted',
    );
  }

  Future<String> _discoverEndpoint() async {
    const function = '/config/usb_gadget/hyperusb/functions/acm.hyperusb';
    final port = (await _root.runRootCommand(
      'test -r $function/port_num && cat $function/port_num',
    )).trim();
    if (!RegExp(r'^\d+$').hasMatch(port)) {
      throw StateError('CDC ACM port_num is unavailable');
    }
    final path = '/dev/ttyGS$port';
    final exists = (await _root.runRootCommand(
      'test -c ${RootShellService.shellQuote(path)} && echo ok || true',
    )).trim();
    if (exists != 'ok') {
      throw StateError('CDC ACM endpoint is unavailable: $path');
    }
    return path;
  }

  void _clearReader() => _reader = null;
  void _clearWriter() => _writer = null;
}
