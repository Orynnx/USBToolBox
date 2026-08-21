import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Lightweight application translations. Chinese is the fallback language.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('zh'), Locale('en')];
  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  static const delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  String text(String key) =>
      _values[locale.languageCode]?[key] ?? _values['zh']![key] ?? key;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['zh', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

const _values = <String, Map<String, String>>{
  'zh': {
    'controllerTitle': 'USB 设备控制器',
    'running': '运行中',
    'stopped': '已停止',
    'usbControlled': 'HyperUSB 正在控制此 USB 设备',
    'usbManaged': 'USB 由 Android 系统管理',
    'virtualDisks': '虚拟磁盘',
    'virtualHid': '虚拟 HID',
    'virtualNetwork': '虚拟网卡',
    'virtualWebcam': '虚拟摄像头',
    'virtualSerial': '虚拟串口',
    'enabled': '已启用',
    'disabled': '已禁用',
    'environment': '设备与环境',
    'environmentInfo': '设备与环境信息',
    'managerVersion': '管理器版本',
    'controllerState': '控制器状态',
    'platform': '平台',
    'systemVersion': '系统版本',
    'coreIntegration': 'Core 集成',
    'notConnected': '未连接',
    'diskMode': '磁盘模式',
    'virtualFlash': '虚拟 U 盘',
    'bootDrive': '启动盘',
    'activeDevices': '活动设备',
    'virtualBootDrive': '虚拟启动盘',
    'mounted': '0 / 0 已挂载',
    'noIso': '未挂载 ISO',
    'storageOptions': '存储选项',
    'addImage': '添加现有镜像',
    'imageFormats': 'IMG、RAW、ISO',
    'createImage': '创建新镜像',
    'formatSize': '格式与容量配置',
    'hidService': 'HID 键盘服务',
    'hostReady': '已就绪，可向主机输入',
    'keyboardInput': '键盘输入',
    'inputHint': '输入要发送到 USB 主机的文本或按键序列',
    'sendHost': '发送到主机',
    'serialService': '串口服务',
    'serialConnected': '/dev/ttyGS0 · 已连接',
    'parameters': '通信参数',
    'baudRate': '波特率',
    'serialFormat': '8 数据位 · 无校验 · 1 停止位',
    'monitor': '监视器',
    'noSerialData': '未收到串口数据',
    'networkAdapter': 'USB 网卡',
    'networkActive': 'RNDIS / CDC-ECM 已启用',
    'networkMode': '网络模式',
    'dhcp': 'DHCP',
    'dhcpSummary': '自动为主机分配 IP 地址',
    'hostAddress': '主机地址',
    'dnsForwarding': 'DNS 转发',
    'dnsSummary': '使用 Android 上游网络',
    'hostConnection': '主机连接',
    'noHost': '未连接 USB 主机',
    'refresh': '刷新',
    'cameraService': 'UVC 摄像头服务',
    'videoReady': '视频流已就绪',
    'viewfinder': '实时取景',
    'videoSource': '视频源',
    'back': '后置',
    'front': '前置',
    'screen': '屏幕',
    'outputSpec': '输出规格',
    'resolution': '分辨率',
    'codec': '编码',
    'codecValue': 'MJPEG · 主机兼容',
  },
  'en': {
    'controllerTitle': 'USB Device Controller',
    'running': 'Running',
    'stopped': 'Stopped',
    'usbControlled': 'HyperUSB controls this USB device',
    'usbManaged': 'USB managed by Android OS',
    'virtualDisks': 'Virtual Disks',
    'virtualHid': 'Virtual HID',
    'virtualNetwork': 'Virtual Network',
    'virtualWebcam': 'Virtual Webcam',
    'virtualSerial': 'Virtual Serial Port',
    'enabled': 'Enabled',
    'disabled': 'Disabled',
    'environment': 'DEVICE & ENVIRONMENT',
    'environmentInfo': 'Device & Environment Info',
    'managerVersion': 'Manager Version',
    'controllerState': 'Controller State',
    'platform': 'Platform',
    'systemVersion': 'System Version',
    'coreIntegration': 'Core Integration',
    'notConnected': 'Not connected',
    'diskMode': 'Disk Mode',
    'virtualFlash': 'Virtual Flash',
    'bootDrive': 'Boot Drive',
    'activeDevices': 'ACTIVE DEVICES',
    'virtualBootDrive': 'Virtual Boot Drive',
    'mounted': '0 / 0 mounted',
    'noIso': 'No ISO mounted',
    'storageOptions': 'STORAGE OPTIONS',
    'addImage': 'Add existing image',
    'imageFormats': 'IMG, RAW, ISO',
    'createImage': 'Create new image',
    'formatSize': 'Format and size configuration',
    'hidService': 'HID Keyboard Service',
    'hostReady': 'Ready for host input',
    'keyboardInput': 'KEYBOARD INPUT',
    'inputHint': 'Type text or a key sequence to send to the USB host',
    'sendHost': 'Send to host',
    'serialService': 'Serial Service',
    'serialConnected': '/dev/ttyGS0 · Connected',
    'parameters': 'COMMUNICATION PARAMETERS',
    'baudRate': 'Baud rate',
    'serialFormat': '8 data bits · No parity · 1 stop bit',
    'monitor': 'MONITOR',
    'noSerialData': 'No serial data received',
    'networkAdapter': 'USB Network Adapter',
    'networkActive': 'RNDIS / CDC-ECM active',
    'networkMode': 'NETWORK MODE',
    'dhcp': 'DHCP',
    'dhcpSummary': 'Automatically assign host IP address',
    'hostAddress': 'Host address',
    'dnsForwarding': 'DNS forwarding',
    'dnsSummary': 'Use Android upstream network',
    'hostConnection': 'HOST CONNECTION',
    'noHost': 'No USB host connected',
    'refresh': 'Refresh',
    'cameraService': 'UVC Camera Service',
    'videoReady': 'Video stream ready',
    'viewfinder': 'LIVE VIEWFINDER',
    'videoSource': 'VIDEO SOURCE',
    'back': 'Back',
    'front': 'Front',
    'screen': 'Screen',
    'outputSpec': 'OUTPUT SPECIFICATION',
    'resolution': 'Resolution',
    'codec': 'Codec',
    'codecValue': 'MJPEG · Host compatible',
  },
};
