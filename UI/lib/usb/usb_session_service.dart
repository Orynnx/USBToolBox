import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/core_client.dart';
import '../core/core_deployment_service.dart';
import '../core/root_shell_service.dart';
import '../storage/models/virtual_disk.dart';
import '../uvc/models/uvc_configuration.dart';

class UsbSessionService {
  UsbSessionService(this._root, this._deployment, this._client);
  final RootShellService _root;
  final CoreDeploymentService _deployment;
  final CoreClient _client;
  static Future<void> _globalTail = Future.value();

  static final instance = UsbSessionService(
    RootShellService(),
    CoreDeploymentService(RootShellService(), CoreClient(RootShellService())),
    CoreClient(RootShellService()),
  );

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _globalTail.then((_) => work());
    _globalTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<CoreStatus> stopAll() => _serial(() async {
    await _deployment.ensureReady();
    const path = '/data/adb/usb_sub/manager_config.json';
    final temp = '$path.new';
    final json = jsonEncode(<String, dynamic>{});
    await _root.runRootCommand(
      'umask 077; printf %s ${RootShellService.shellQuote(json)} > ${RootShellService.shellQuote(temp)} && mv -f ${RootShellService.shellQuote(temp)} ${RootShellService.shellQuote(path)}',
    );
    await _client.setConfig(path);
    return _client.getStatus();
  });

  Future<CoreStatus> apply(
    List<VirtualDisk> allDisks, {
    bool? serialEnabled,
    bool? keyboardEnabled,
    bool? uvcEnabled,
    UvcConfiguration? uvc,
  }) => _serial(() async {
    final active = allDisks.where((disk) => disk.desiredEnabled).toList();
    final paths = <String>{};
    for (final disk in active) {
      if (!paths.add(disk.imagePath)) {
        throw CoreException(
          CoreErrorCode.duplicateBackingFile,
          'The same backing file is active more than once.',
        );
      }
    }
    await _deployment.ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final serial =
        prefs.getString('hyperusb.serial') ??
        'HU-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    await prefs.setString('hyperusb.serial', serial);
    final serialEnabledValue =
        serialEnabled ?? (prefs.getBool('hyperusb.serial.enabled') ?? false);
    if (serialEnabled != null) {
      await prefs.setBool('hyperusb.serial.enabled', serialEnabled);
    }
    final keyboardEnabledValue =
        keyboardEnabled ??
        (prefs.getBool('hyperusb.keyboard.enabled') ?? false);
    if (keyboardEnabled != null) {
      await prefs.setBool('hyperusb.keyboard.enabled', keyboardEnabled);
    }
    if (uvc != null) {
      await prefs.setString('hyperusb.uvc.config', jsonEncode(uvc.toJson()));
    } else if (uvcEnabled == false) {
      await prefs.remove('hyperusb.uvc.config');
    }
    final uvcJson = uvcEnabled == false
        ? null
        : uvc?.toJson() ??
              _readUvcConfig(prefs.getString('hyperusb.uvc.config'));
    final config = await _readManagerConfig();
    final device = _section(config, 'device');
    device.putIfAbsent('manufacturer', () => 'HyperUSB');
    device.putIfAbsent('product', () => 'HyperUSB Composite');
    device.putIfAbsent('serialNumber', () => serial);
    config['device'] = device;

    final storage = _section(config, 'storage');
    storage['luns'] = active
        .map(
          (disk) => {
            'imagePath': disk.imagePath,
            'readOnly': disk.type == VirtualDiskType.cdrom || disk.readOnly,
            'removable': disk.removable,
            'cdrom': disk.type == VirtualDiskType.cdrom,
            'noFua': !disk.enableFua,
          },
        )
        .toList();
    config['storage'] = storage;

    final serialSection = _section(config, 'serial');
    if (serialEnabled != null || !serialSection.containsKey('enabled')) {
      serialSection['enabled'] = serialEnabledValue;
    }
    config['serial'] = serialSection;

    final keyboardSection = _section(config, 'keyboard');
    if (keyboardEnabled != null || !keyboardSection.containsKey('boot')) {
      keyboardSection['boot'] = keyboardEnabledValue;
    }
    config['keyboard'] = keyboardSection;

    if (uvcEnabled == false) {
      final uvcSection = _section(config, 'uvc');
      uvcSection['enabled'] = false;
      config['uvc'] = uvcSection;
    } else if (uvc != null) {
      config['uvc'] = uvc.toJson();
    } else if (!config.containsKey('uvc')) {
      config['uvc'] = uvcJson ?? {'enabled': false};
    }
    final json = jsonEncode(config);
    const path = '/data/adb/usb_sub/manager_config.json';
    final temp = '$path.new';
    await _root.runRootCommand(
      'umask 077; printf %s ${RootShellService.shellQuote(json)} > ${RootShellService.shellQuote(temp)} && mv -f ${RootShellService.shellQuote(temp)} ${RootShellService.shellQuote(path)}',
    );
    await _client.setConfig(path);
    return _client.getStatus();
  });

  Future<Map<String, dynamic>> _readManagerConfig() async {
    const path = '/data/adb/usb_sub/manager_config.json';
    final quoted = RootShellService.shellQuote(path);
    final raw = await _root.runRootCommand(
      'if [ -f $quoted ]; then cat $quoted; else printf %s ${RootShellService.shellQuote('{}')}; fi',
    );
    if (raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    throw CoreException(
      CoreErrorCode.invalidConfig,
      'The current Manager configuration is not valid JSON.',
    );
  }

  Map<String, dynamic> _section(Map<String, dynamic> config, String key) {
    final value = config[key];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  Map<String, dynamic>? _readUvcConfig(String? value) {
    if (value == null) return null;
    try {
      return jsonDecode(value) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
