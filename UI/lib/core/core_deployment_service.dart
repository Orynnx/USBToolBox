import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'core_client.dart';
import 'root_shell_service.dart';

class CoreInstallationStatus {
  const CoreInstallationStatus({
    required this.installed,
    required this.running,
    this.version,
  });
  final bool installed, running;
  final String? version;
}

/// Installs only the APK-bundled, current-source ARM64 Core. Replacement is
/// atomic and the old daemon is stopped with SIGTERM after PID verification.
class CoreDeploymentService {
  CoreDeploymentService(this._root, this._client);
  final RootShellService _root;
  final CoreClient _client;
  static const directory = '/data/adb/usb_sub';
  static const binary = '$directory/hyperusbd';
  static const pidFile = '$directory/hyperusbd.pid';

  Future<CoreInstallationStatus> getInstallationStatus() async {
    final installed =
        (await _root.runRootCommand(
          '[ -x ${RootShellService.shellQuote(binary)} ] && echo yes || true',
        )).trim() ==
        'yes';
    var running = false;
    try {
      await _client.ping();
      running = true;
    } catch (_) {}
    return CoreInstallationStatus(
      installed: installed,
      running: running,
      version: installed ? await getInstalledVersion() : null,
    );
  }

  Future<String?> getInstalledVersion() async {
    final result = await _root.runRootCommand(
      '${RootShellService.shellQuote(binary)} --version 2>/dev/null || true',
    );
    final version = result.trim();
    return version.isEmpty ? null : version;
  }

  /// Atomically replaces the daemon only when the APK-bundled binary differs.
  /// This prevents a stale installed Core from silently lacking newer protocol
  /// capabilities while avoiding an unnecessary daemon restart on every SET.
  Future<bool> deploy() async {
    final bytes = (await rootBundle.load(
      'assets/core/arm64-v8a/hyperusbd',
    )).buffer.asUint8List();
    if (bytes.isEmpty) {
      throw RootShellException(
        'core_asset_missing',
        'The ARM64 Core asset is empty.',
      );
    }
    final support = await getApplicationSupportDirectory();
    final staged = File('${support.path}/hyperusbd-stage');
    await staged.writeAsBytes(bytes, flush: true);
    final qDir = RootShellService.shellQuote(directory);
    final qBin = RootShellService.shellQuote(binary);
    final qStage = RootShellService.shellQuote(staged.path);
    final changed = await _root.runRootCommand(
      'mkdir -p $qDir && chmod 700 $qDir; if [ -x $qBin ] && cmp -s $qStage $qBin; then echo unchanged; else cp $qStage $qBin.new && chown 0:0 $qBin.new && chmod 755 $qBin.new && mv -f $qBin.new $qBin && echo changed; fi',
    );
    return changed.trim() == 'changed';
  }

  Future<void> start() async {
    try {
      await _client.ping();
      return;
    } catch (_) {}
    final qBin = RootShellService.shellQuote(binary);
    final qPid = RootShellService.shellQuote(pidFile);
    await _root.runRootCommand(
      'mkdir -p ${RootShellService.shellQuote(directory)}; '
      '(umask 077; setsid $qBin </dev/null >> ${RootShellService.shellQuote('$directory/hyperusbd.log')} 2>&1 & echo \$! > $qPid)',
    );
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        await _client.ping();
        return;
      } catch (_) {}
    }
    throw RootShellException('core_start_failed', 'Core did not become ready.');
  }

  Future<void> stop() async {
    final qPid = RootShellService.shellQuote(pidFile);
    final qBin = RootShellService.shellQuote(binary);
    final qDeletedBin = RootShellService.shellQuote('$binary (deleted)');
    await _root.runRootCommand(
      // argv[0] is not a stable identity on Android: the daemon is commonly
      // shown as just "hyperusbd", and toybox tr does not reliably translate
      // the NUL separators in /proc/<pid>/cmdline.  Verify the actual
      // executable instead.  After an atomic replacement, Linux appends
      // " (deleted)" to the old process's executable link, which is still the
      // exact daemon we must stop before starting its replacement.
      'if [ -r $qPid ]; then p=\$(cat $qPid); case \$p in *[!0-9]*|\'\') ;; *) target=\$(readlink /proc/\$p/exe 2>/dev/null || true); if [ "\$target" = $qBin ] || [ "\$target" = $qDeletedBin ]; then kill -TERM \$p || true; for i in \$(seq 1 20); do [ -e /proc/\$p ] || break; sleep 0.1; done; fi ;; esac; fi',
    );
  }

  Future<void> ensureReady() async {
    final abi = (await _root.runRootCommand(
      'getprop ro.product.cpu.abi',
    )).trim();
    if (abi != 'arm64-v8a') {
      throw RootShellException(
        'unsupported_abi',
        'This APK currently bundles only arm64-v8a Core.',
      );
    }
    final changed = await deploy();
    if (changed) await stop();
    await start();
  }

  Future<void> remove() async {
    await stop();
    await _root.runRootCommand(
      'rm -f ${RootShellService.shellQuote(binary)} ${RootShellService.shellQuote(pidFile)}',
    );
  }
}
