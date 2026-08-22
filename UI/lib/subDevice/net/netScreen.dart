// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../devicePage.dart';
import 'components.dart';

/// 虚拟网卡配置与状态控制页面 (NCM 网络通道)
class NetScreen extends StatefulWidget {
  const NetScreen({super.key});

  @override
  State<NetScreen> createState() => _NetScreenState();
}

class _NetScreenState extends State<NetScreen> {
  /// NCM 虚拟网卡总开关状态
  bool _ncmEnabled = false;

  /// Android 侧 MAC 地址
  String _androidMac = '02:42:AC:11:00:02';

  /// USB 侧 MAC 地址
  String _usbMac = '02:42:AC:11:00:03';

  /// DHCP 服务开关状态（默认开启）
  bool _dhcpEnabled = true;

  /// 要从 Android 访问设备所用的 IP 地址
  String _deviceIp = '192.168.42.2';

  /// 要从设备访问 Android 所用的 IP 地址
  String _androidIp = '192.168.42.129';

  /// 流量代理开关状态
  bool _proxyEnabled = false;

  /// 重新生成 Android 侧 MAC 地址
  void _refreshAndroidMac() {
    setState(() {
      _androidMac = generateRandomMac();
    });
  }

  /// 重新生成 USB 侧 MAC 地址
  void _refreshUsbMac() {
    setState(() {
      _usbMac = generateRandomMac();
    });
  }

  /// 打开 MAC 地址手动编辑弹窗
  void _openEditMacDialog({required bool isAndroid}) {
    final l10n = context.l10n;
    final title = isAndroid
        ? '${l10n.text('editMacTitle')} (${l10n.text('androidMacAddress')})'
        : '${l10n.text('editMacTitle')} (${l10n.text('usbMacAddress')})';
    final initialValue = isAndroid ? _androidMac : _usbMac;

    MacEditDialog.show(
      context,
      title: title,
      initialValue: initialValue,
      onSave: (newMac) {
        setState(() {
          if (isAndroid) {
            _androidMac = newMac;
          } else {
            _usbMac = newMac;
          }
        });
      },
    );
  }

  /// 打开 IP 地址编辑弹窗
  void _openEditIpDialog({required bool isDevice}) {
    final l10n = context.l10n;
    final targetDescription = isDevice
        ? l10n.text('accessDeviceFromAndroid')
        : l10n.text('accessAndroidFromDevice');
    final initialValue = isDevice ? _deviceIp : _androidIp;

    IpEditDialog.show(
      context,
      targetDescription: targetDescription,
      initialValue: initialValue,
      onSave: (newIp) {
        setState(() {
          if (isDevice) {
            _deviceIp = newIp;
          } else {
            _androidIp = newIp;
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DeviceScaffold(
      title: l10n.text('virtualNetwork'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. NCM 虚拟网卡总开关卡片
          NetMasterCard(
            enabled: _ncmEnabled,
            onChanged: (val) => setState(() => _ncmEnabled = val),
          ),

          // 2. 网卡设置小节 (Android 侧与 USB 侧 MAC 地址，支持点击编辑与刷新)
          DeviceSection(l10n.text('networkSettings')),
          NetMacSettingsCard(
            androidMac: _androidMac,
            usbMac: _usbMac,
            onEditAndroidMac: () => _openEditMacDialog(isAndroid: true),
            onEditUsbMac: () => _openEditMacDialog(isAndroid: false),
            onRefreshAndroidMac: _refreshAndroidMac,
            onRefreshUsbMac: _refreshUsbMac,
          ),
          const SizedBox(height: 14),

          // 3. DHCP 设置卡片 (DHCP 开关与双向 IP 地址)
          NetDhcpCard(
            dhcpEnabled: _dhcpEnabled,
            deviceIp: _deviceIp,
            androidIp: _androidIp,
            onToggleDhcp: (val) => setState(() => _dhcpEnabled = val),
            onEditDeviceIp: () => _openEditIpDialog(isDevice: true),
            onEditAndroidIp: () => _openEditIpDialog(isDevice: false),
          ),
          const SizedBox(height: 14),

          // 4. 流量代理卡片 (是否一并使用安卓代理)
          NetTrafficProxyCard(
            enabled: _proxyEnabled,
            onChanged: (val) => setState(() => _proxyEnabled = val),
          ),
        ],
      ),
    );
  }
}
