import 'dart:async';
import 'dart:io';

enum RootState {
  unknown,
  unavailable,
  awaitingAuthorization,
  available,
  denied,
  failed,
}

class RootShellException implements Exception {
  RootShellException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

/// The only place the Manager invokes `su`. Callers supply a complete shell
/// command; dynamic path fragments must pass through [shellQuote].
class RootShellService {
  RootState state = RootState.unknown;

  static String shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  Future<bool> probeRoot({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!Platform.isAndroid) {
      state = RootState.unavailable;
      return false;
    }
    state = RootState.awaitingAuthorization;
    try {
      final result = await Process.run('su', const [
        '-c',
        'id',
      ]).timeout(timeout);
      if (result.exitCode == 0 && result.stdout.toString().contains('uid=0')) {
        state = RootState.available;
        return true;
      }
      state = RootState.denied;
      return false;
    } on ProcessException {
      state = RootState.unavailable;
      return false;
    } on TimeoutException {
      state = RootState.denied;
      return false;
    } catch (_) {
      state = RootState.failed;
      return false;
    }
  }

  Future<String> runRootCommand(
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!await probeRoot(timeout: timeout)) {
      throw RootShellException(
        'root_unavailable',
        'Root authorization was not granted.',
      );
    }
    try {
      final result = await Process.run('su', ['-c', command]).timeout(timeout);
      if (result.exitCode != 0) {
        throw RootShellException(
          'root_command_failed',
          result.stderr.toString().trim(),
        );
      }
      return result.stdout.toString();
    } on TimeoutException {
      throw RootShellException('root_timeout', 'Root command timed out.');
    }
  }

  /// Starts one long-lived root command. Data-plane clients use this instead
  /// of spawning a new `su` process for every packet.
  Future<Process> startRootProcess(String command) async {
    if (!await probeRoot()) {
      throw RootShellException(
        'root_unavailable',
        'Root authorization was not granted.',
      );
    }
    try {
      return await Process.start('su', ['-c', command]);
    } on ProcessException catch (error) {
      throw RootShellException('root_process_failed', error.message);
    }
  }
}
