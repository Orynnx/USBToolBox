import 'package:shared_preferences/shared_preferences.dart';

import '../../core/root_shell_service.dart';

/// Owns a reversible lease for Android's built-in DeviceAsWebcam receiver.
///
/// That receiver attaches to every UVC V4L2 output node after USB state
/// changes. HyperUSB owns that node while UVC is enabled, so allowing both
/// producers to run corrupts control events and output buffers.
class SystemWebcamGuard {
  SystemWebcamGuard(this._root);

  static const _package = 'com.android.DeviceAsWebcam';
  static const _component =
      'com.android.DeviceAsWebcam/com.android.deviceaswebcam.DeviceAsWebcamReceiverImpl';
  static const _receiverName =
      'name=com.android.deviceaswebcam.DeviceAsWebcamReceiverImpl';
  static const _leaseKey = 'hyperusb.system_webcam_guard.restore_receiver';

  final RootShellService _root;

  Future<void> acquire() async {
    final prefs = await SharedPreferences.getInstance();
    // Recover a lease left behind by a crashed Manager before using a new one.
    if (prefs.getBool(_leaseKey) ?? false) await release();

    final receivers = await _root.runRootCommand(
      'cmd package query-receivers --user 0 -a android.hardware.usb.action.USB_STATE 2>/dev/null || true',
    );
    final restoreReceiver = receivers.contains(_receiverName);
    await prefs.setBool(_leaseKey, restoreReceiver);
    if (restoreReceiver) {
      await _root.runRootCommand(
        // MIUI accepts component-level `disable`, but silently keeps this
        // privileged receiver enabled when `disable-user` is used.
        'pm disable --user 0 ${RootShellService.shellQuote(_component)}; '
        'am force-stop ${RootShellService.shellQuote(_package)}',
      );
    } else {
      await _root.runRootCommand(
        'am force-stop ${RootShellService.shellQuote(_package)}',
      );
    }
  }

  Future<void> release() async {
    final prefs = await SharedPreferences.getInstance();
    final restoreReceiver = prefs.getBool(_leaseKey) ?? false;
    try {
      if (restoreReceiver) {
        await _root.runRootCommand(
          'pm enable --user 0 ${RootShellService.shellQuote(_component)}',
        );
      }
    } finally {
      await prefs.remove(_leaseKey);
    }
  }
}
