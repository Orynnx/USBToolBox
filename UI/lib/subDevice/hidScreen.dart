// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'devicePage.dart';

/// 虚拟人机接口设备（USB HID - 键盘与快捷指令输入）配置页面
///
/// 允许用户将 Android 设备模拟为 USB 键盘设备，向目标主机发送文本字符、击键序列或快捷键组合。
class HidScreen extends StatefulWidget {
  const HidScreen({super.key});

  @override
  State<HidScreen> createState() => _HidScreenState();
}

class _HidScreenState extends State<HidScreen> {
  /// 虚拟 HID 服务总启停开关
  bool _enabled = false;

  /// 待发送到主机的文本输入框控制器
  final _input = TextEditingController();

  @override
  void dispose() {
    // 页面销毁时及时释放控制器资源
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取多语言本地化资源
    final l = context.l10n;

    return DeviceScaffold(
      title: l.text('virtualHid'), // 页面标题：“虚拟 HID 设备”
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HID 服务开关与状态卡片
          DeviceStatusCard(
            icon: Icons.keyboard_rounded,
            title: l.text('hidService'), // “HID 服务”
            detail: _enabled ? l.text('hostReady') : l.text('disabled'),
            enabled: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),

          // 2. 键盘文本与快捷按键输入区域
          DeviceSection(l.text('keyboardInput')), // “键盘输入”
          DeviceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 多行文本输入框
                TextField(
                  controller: _input,
                  minLines: 4,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: l.text('inputHint'), // 输入提示（例如“输入要向主机发送的文本或脚本...”）
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // 快捷键快速点选胶囊标签组
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Ctrl+C', 'Ctrl+V', 'Alt+Tab', 'Enter']
                      .map(
                        (label) => ChoicePill(
                          label: label,
                          selected: false,
                          // 点击后直接将快捷键宏指令追加到输入框中
                          onTap: () => _input.text = '${_input.text}$label ',
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),

                // 发送至主机按钮（仅在 HID 服务开启时允许点击）
                FilledButton(
                  onPressed: _enabled
                      ? () {
                          // TODO: 调用底层 HyperUSB Core 发送 HID 键盘数据包至主机
                        }
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.send_rounded),
                      const SizedBox(width: 8),
                      Text(l.text('sendHost')), // “发送至主机”
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
