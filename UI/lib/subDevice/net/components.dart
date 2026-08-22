// ignore_for_file: file_names

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../devicePage.dart';

/// 生成合法的本地管理单播 MAC 地址 (格式: XX:XX:XX:XX:XX:XX)
String generateRandomMac() {
  final random = math.Random();
  // 首字节确保为本地管理单播地址 (第二低位为1，最低位为0)
  const prefixes = [0x02, 0x06, 0x0A, 0x0E];
  final firstByte = prefixes[random.nextInt(prefixes.length)];
  final bytes = [
    firstByte,
    random.nextInt(256),
    random.nextInt(256),
    random.nextInt(256),
    random.nextInt(256),
    random.nextInt(256),
  ];
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}

/// 校验 MAC 地址格式合法性 (支持冒号或短横线分隔的 6 组十六进制)
bool isValidMac(String mac) {
  final cleaned = mac.trim().replaceAll('-', ':');
  final regex = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
  return regex.hasMatch(cleaned);
}

/// 标准化 MAC 地址格式为大写冒号分隔 (XX:XX:XX:XX:XX:XX)
String normalizeMac(String mac) {
  return mac.trim().replaceAll('-', ':').toUpperCase();
}

/// 校验 IPv4 地址格式合法性
bool isValidIpv4(String ip) {
  final parts = ip.trim().split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    if (part.length > 1 && part.startsWith('0')) return false; // 避免前导零
  }
  return true;
}

/// 1. NCM 虚拟网卡总开关状态卡片
class NetMasterCard extends StatelessWidget {
  const NetMasterCard({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /// 网卡是否启用
  final bool enabled;

  /// 启停开关切换回调
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return DeviceCard(
      child: Row(
        children: [
          // 左侧网络图标徽标
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: enabled
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lan_rounded,
              color: enabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          // 中间标题与描述
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.text('ncmNetworkAdapter'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.text('ncmNetworkDesc'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧开关
          Switch(
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 2. 网卡 MAC 地址配置卡片（支持点击整行编辑与右侧刷新）
class NetMacSettingsCard extends StatelessWidget {
  const NetMacSettingsCard({
    super.key,
    required this.androidMac,
    required this.usbMac,
    required this.onEditAndroidMac,
    required this.onEditUsbMac,
    required this.onRefreshAndroidMac,
    required this.onRefreshUsbMac,
  });

  /// Android 侧 MAC 地址
  final String androidMac;

  /// USB 侧 MAC 地址
  final String usbMac;

  /// 点击编辑 Android 侧 MAC 回调
  final VoidCallback onEditAndroidMac;

  /// 点击编辑 USB 侧 MAC 回调
  final VoidCallback onEditUsbMac;

  /// 刷新 Android 侧 MAC 回调
  final VoidCallback onRefreshAndroidMac;

  /// 刷新 USB 侧 MAC 回调
  final VoidCallback onRefreshUsbMac;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return DeviceCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // Android 侧 MAC 地址行（可点击编辑）
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            onTap: onEditAndroidMac,
            title: Text(
              l10n.text('androidMacAddress'),
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                androidMac,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  letterSpacing: 0.5,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.text('refreshMac'),
              onPressed: onRefreshAndroidMac,
            ),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
          // USB 侧 MAC 地址行（可点击编辑）
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            onTap: onEditUsbMac,
            title: Text(
              l10n.text('usbMacAddress'),
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                usbMac,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  letterSpacing: 0.5,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.text('refreshMac'),
              onPressed: onRefreshUsbMac,
            ),
          ),
        ],
      ),
    );
  }
}

/// 3. DHCP 服务及双向 IP 地址配置卡片
class NetDhcpCard extends StatelessWidget {
  const NetDhcpCard({
    super.key,
    required this.dhcpEnabled,
    required this.deviceIp,
    required this.androidIp,
    required this.onToggleDhcp,
    required this.onEditDeviceIp,
    required this.onEditAndroidIp,
  });

  /// DHCP 是否启用
  final bool dhcpEnabled;

  /// 从 Android 访问设备所用的 IP
  final String deviceIp;

  /// 从设备访问 Android 所用的 IP
  final String androidIp;

  /// 切换 DHCP 开关回调
  final ValueChanged<bool> onToggleDhcp;

  /// 编辑设备 IP 回调
  final VoidCallback onEditDeviceIp;

  /// 编辑 Android IP 回调
  final VoidCallback onEditAndroidIp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return DeviceCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // DHCP 启停开关行
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            title: Text(
              l10n.text('dhcp'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              l10n.text('dhcpSummary'),
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Switch(
              value: dhcpEnabled,
              onChanged: onToggleDhcp,
            ),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
          // 1. 从 Android 访问设备 IP 行
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            onTap: !dhcpEnabled ? onEditDeviceIp : null,
            title: Text(
              l10n.text('accessDeviceFromAndroid'),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                deviceIp,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            trailing: AnimatedSwitcher(
              duration: appThemeManager.disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              child: !dhcpEnabled
                  ? IconButton(
                      key: const ValueKey('editDeviceIp'),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: l10n.text('editIp'),
                      onPressed: onEditDeviceIp,
                    )
                  : const SizedBox.shrink(key: ValueKey('noEditDeviceIp')),
            ),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
          // 2. 从设备访问 Android IP 行
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            onTap: !dhcpEnabled ? onEditAndroidIp : null,
            title: Text(
              l10n.text('accessAndroidFromDevice'),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                androidIp,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            trailing: AnimatedSwitcher(
              duration: appThemeManager.disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              child: !dhcpEnabled
                  ? IconButton(
                      key: const ValueKey('editAndroidIp'),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: l10n.text('editIp'),
                      onPressed: onEditAndroidIp,
                    )
                  : const SizedBox.shrink(key: ValueKey('noEditAndroidIp')),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4. 流量代理开关卡片
class NetTrafficProxyCard extends StatelessWidget {
  const NetTrafficProxyCard({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /// 流量代理是否启用
  final bool enabled;

  /// 启停开关切换回调
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return DeviceCard(
      child: Row(
        children: [
          // 左侧代理图标
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: enabled
                  ? colorScheme.secondaryContainer
                  : colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.vpn_lock_rounded,
              color: enabled
                  ? colorScheme.secondary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          // 中间标题与描述
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.text('trafficProxy'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.text('trafficProxyDesc'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧开关
          Switch(
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// IP 地址编辑弹窗（标题固定为“编辑 IP”）
class IpEditDialog extends StatefulWidget {
  const IpEditDialog({
    super.key,
    required this.targetDescription,
    required this.initialValue,
    required this.onSave,
  });

  /// 编辑目标描述（例如“从 Android 访问设备”或“从设备访问 Android”）
  final String targetDescription;

  /// 初始 IP 地址值
  final String initialValue;

  /// 保存 IP 回调
  final ValueChanged<String> onSave;

  static Future<void> show(
    BuildContext context, {
    required String targetDescription,
    required String initialValue,
    required ValueChanged<String> onSave,
  }) {
    return showDialog(
      context: context,
      builder: (_) => IpEditDialog(
        targetDescription: targetDescription,
        initialValue: initialValue,
        onSave: onSave,
      ),
    );
  }

  @override
  State<IpEditDialog> createState() => _IpEditDialogState();
}

class _IpEditDialogState extends State<IpEditDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (!isValidIpv4(text)) {
      setState(() {
        _errorText = context.l10n.text('invalidIpAddress');
      });
      return;
    }
    widget.onSave(text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.text('editIp')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.targetDescription,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: l10n.text('ipAddress'),
              hintText: l10n.text('ipAddressHint'),
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _handleSubmit(),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: _handleSubmit,
          child: Text(l10n.text('save')),
        ),
      ],
    );
  }
}

/// MAC 地址编辑弹窗
class MacEditDialog extends StatefulWidget {
  const MacEditDialog({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onSave,
  });

  /// 弹窗标题
  final String title;

  /// 初始 MAC 地址
  final String initialValue;

  /// 保存回调
  final ValueChanged<String> onSave;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String initialValue,
    required ValueChanged<String> onSave,
  }) {
    return showDialog(
      context: context,
      builder: (_) => MacEditDialog(
        title: title,
        initialValue: initialValue,
        onSave: onSave,
      ),
    );
  }

  @override
  State<MacEditDialog> createState() => _MacEditDialogState();
}

class _MacEditDialogState extends State<MacEditDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (!isValidMac(text)) {
      setState(() {
        _errorText = context.l10n.text('invalidMacAddress');
      });
      return;
    }
    widget.onSave(normalizeMac(text));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: l10n.text('macAddress'),
              hintText: l10n.text('macAddressHint'),
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _handleSubmit(),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: _handleSubmit,
          child: Text(l10n.text('save')),
        ),
      ],
    );
  }
}
