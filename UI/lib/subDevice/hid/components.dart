// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// 虚拟按键数据结构规格
class KeySpec {
  const KeySpec({
    this.label = '',
    this.usage = 0,
    this.modifier = 0,
    this.units = 1.0,
    this.spacer = false,
    this.shiftLabel,
  });

  final String label;
  final int usage;
  final int modifier;
  final double units;
  final bool spacer;
  final String? shiftLabel;

  bool get special =>
      modifier != 0 || (usage < 0x04 || usage > 0x27) && (usage < 0x2d || usage > 0x38);

  String displayedLabel(bool shiftHeld) =>
      shiftHeld ? (shiftLabel ?? label) : label;
}

const KeySpec _gap03 = KeySpec(units: 0.3, spacer: true);
const KeySpec _gap04 = KeySpec(units: 0.4, spacer: true);
const KeySpec _gap05 = KeySpec(units: 0.5, spacer: true);
const KeySpec _gap11 = KeySpec(units: 1.1, spacer: true);
const KeySpec _gap13 = KeySpec(units: 1.3, spacer: true);
const KeySpec _gap34 = KeySpec(units: 3.4, spacer: true);

/// 87 键标准键盘矩阵排布定义
const List<List<KeySpec>> standard87KeyRows = [
  // Row 1: Esc, F1-F12, PrtSc, ScrLk, Pause
  [
    KeySpec(label: 'Esc', usage: 0x29), _gap05,
    KeySpec(label: 'F1', usage: 0x3a), KeySpec(label: 'F2', usage: 0x3b), KeySpec(label: 'F3', usage: 0x3c), KeySpec(label: 'F4', usage: 0x3d), _gap03,
    KeySpec(label: 'F5', usage: 0x3e), KeySpec(label: 'F6', usage: 0x3f), KeySpec(label: 'F7', usage: 0x40), KeySpec(label: 'F8', usage: 0x41), _gap03,
    KeySpec(label: 'F9', usage: 0x42), KeySpec(label: 'F10', usage: 0x43), KeySpec(label: 'F11', usage: 0x44), KeySpec(label: 'F12', usage: 0x45), _gap05,
    KeySpec(label: 'PrtSc', usage: 0x46), KeySpec(label: 'ScrLk', usage: 0x47), KeySpec(label: 'Pause', usage: 0x48),
  ],
  // Row 2: `~, 1-0, -, =, Backspace, Ins, Home, PgUp
  [
    KeySpec(label: '`', usage: 0x35, shiftLabel: '~'),
    KeySpec(label: '1', usage: 0x1e, shiftLabel: '!'),
    KeySpec(label: '2', usage: 0x1f, shiftLabel: '@'),
    KeySpec(label: '3', usage: 0x20, shiftLabel: '#'),
    KeySpec(label: '4', usage: 0x21, shiftLabel: r'$'),
    KeySpec(label: '5', usage: 0x22, shiftLabel: '%'),
    KeySpec(label: '6', usage: 0x23, shiftLabel: '^'),
    KeySpec(label: '7', usage: 0x24, shiftLabel: '&'),
    KeySpec(label: '8', usage: 0x25, shiftLabel: '*'),
    KeySpec(label: '9', usage: 0x26, shiftLabel: '('),
    KeySpec(label: '0', usage: 0x27, shiftLabel: ')'),
    KeySpec(label: '-', usage: 0x2d, shiftLabel: '_'),
    KeySpec(label: '=', usage: 0x2e, shiftLabel: '+'),
    KeySpec(label: '⌫', usage: 0x2a, units: 2.0), _gap04,
    KeySpec(label: 'Ins', usage: 0x49), KeySpec(label: 'Home', usage: 0x4a), KeySpec(label: 'PgUp', usage: 0x4b),
  ],
  // Row 3: Tab, Q-P, [, ], \, Del, End, PgDn
  [
    KeySpec(label: 'Tab', usage: 0x2b, units: 1.5),
    KeySpec(label: 'Q', usage: 0x14), KeySpec(label: 'W', usage: 0x1a), KeySpec(label: 'E', usage: 0x08),
    KeySpec(label: 'R', usage: 0x15), KeySpec(label: 'T', usage: 0x17), KeySpec(label: 'Y', usage: 0x1c),
    KeySpec(label: 'U', usage: 0x18), KeySpec(label: 'I', usage: 0x0c), KeySpec(label: 'O', usage: 0x12),
    KeySpec(label: 'P', usage: 0x13),
    KeySpec(label: '[', usage: 0x2f, shiftLabel: '{'),
    KeySpec(label: ']', usage: 0x30, shiftLabel: '}'),
    KeySpec(label: r'\', usage: 0x31, units: 1.5, shiftLabel: '|'), _gap04,
    KeySpec(label: 'Del', usage: 0x4c), KeySpec(label: 'End', usage: 0x4d), KeySpec(label: 'PgDn', usage: 0x4e),
  ],
  // Row 4: Caps, A-L, ;, ', Enter
  [
    KeySpec(label: 'Caps', usage: 0x39, units: 1.8),
    KeySpec(label: 'A', usage: 0x04), KeySpec(label: 'S', usage: 0x16), KeySpec(label: 'D', usage: 0x07),
    KeySpec(label: 'F', usage: 0x09), KeySpec(label: 'G', usage: 0x0a), KeySpec(label: 'H', usage: 0x0b),
    KeySpec(label: 'J', usage: 0x0d), KeySpec(label: 'K', usage: 0x0e), KeySpec(label: 'L', usage: 0x0f),
    KeySpec(label: ';', usage: 0x33, shiftLabel: ':'),
    KeySpec(label: "'", usage: 0x34, shiftLabel: '"'),
    KeySpec(label: '↵', usage: 0x28, units: 2.2), _gap34,
  ],
  // Row 5: Shift, Z-M, ,, ., /, Shift, ↑
  [
    KeySpec(label: '⇧', modifier: 0x02, units: 2.2),
    KeySpec(label: 'Z', usage: 0x1d), KeySpec(label: 'X', usage: 0x1b), KeySpec(label: 'C', usage: 0x06),
    KeySpec(label: 'V', usage: 0x19), KeySpec(label: 'B', usage: 0x05), KeySpec(label: 'N', usage: 0x11),
    KeySpec(label: 'M', usage: 0x10),
    KeySpec(label: ',', usage: 0x36, shiftLabel: '<'),
    KeySpec(label: '.', usage: 0x37, shiftLabel: '>'),
    KeySpec(label: '/', usage: 0x38, shiftLabel: '?'),
    KeySpec(label: '⇧', modifier: 0x20, units: 2.6), _gap13,
    KeySpec(label: '↑', usage: 0x52), _gap11,
  ],
  // Row 6: Ctrl, Win, Alt, Space, Alt, Win, Menu, Ctrl, ←, ↓, →
  [
    KeySpec(label: 'Ctrl', modifier: 0x01, units: 1.3),
    KeySpec(label: 'Win', modifier: 0x08, units: 1.3),
    KeySpec(label: 'Alt', modifier: 0x04, units: 1.3),
    KeySpec(label: 'Space', usage: 0x2c, units: 5.6),
    KeySpec(label: 'Alt', modifier: 0x40, units: 1.3),
    KeySpec(label: 'Win', modifier: 0x80, units: 1.3),
    KeySpec(label: 'Menu', usage: 0x65, units: 1.3),
    KeySpec(label: 'Ctrl', modifier: 0x10, units: 1.3), _gap04,
    KeySpec(label: '←', usage: 0x50),
    KeySpec(label: '↓', usage: 0x51),
    KeySpec(label: '→', usage: 0x4f),
  ],
];

/// 键盘服务运行状态（stopped: 停止 / operating: 操作中 / running: 运行中）
enum KeyboardDeviceState {
  stopped,
  operating,
  running,
}

/// 键盘可变操作按钮（支持 启动/操作中/终止 三态流畅过渡）
class KeyboardActionButton extends StatelessWidget {
  const KeyboardActionButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.size = 36.0,
    this.borderRadius = 10.0,
  });

  /// 状态：stopped (启动) / operating (操作中) / running (终止)
  final KeyboardDeviceState state;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 按钮尺寸（正方形宽高）
  final double size;

  /// 圆角大小
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color bgColor;
    final Border? border;
    final Widget iconWidget;

    switch (state) {
      case KeyboardDeviceState.stopped:
        // 启动）克制 Tonal Green，无游戏感发光
        final greenColor = isDark
            ? const Color(0xff4ade80)
            : const Color(0xff16a34a);
        bgColor = isDark ? const Color(0xff143527) : const Color(0xffdcfce7);
        border = Border.all(
          color: greenColor.withValues(alpha: 0.35),
          width: 1.2,
        );
        iconWidget = Icon(
          Icons.play_arrow_rounded,
          key: const ValueKey('icon_stopped'),
          color: greenColor,
          size: size * 0.62,
        );
        break;

      case KeyboardDeviceState.operating:
        // 操作中）Tonal Amber / Tertiary
        bgColor = colorScheme.tertiaryContainer;
        border = Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.35),
          width: 1.2,
        );
        iconWidget = SizedBox(
          key: const ValueKey('icon_operating'),
          width: size * 0.46,
          height: size * 0.46,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            valueColor: AlwaysStoppedAnimation<Color>(
              colorScheme.onTertiaryContainer,
            ),
          ),
        );
        break;

      case KeyboardDeviceState.running:
        // 终止）系统级 errorContainer 背景 + onErrorContainer 图标，收敛饱和度
        bgColor = colorScheme.errorContainer;
        border = Border.all(
          color: colorScheme.error.withValues(alpha: 0.35),
          width: 1.2,
        );
        iconWidget = Container(
          key: const ValueKey('icon_running'),
          width: size * 0.34,
          height: size * 0.34,
          decoration: BoxDecoration(
            color: colorScheme.onErrorContainer,
            borderRadius: BorderRadius.circular(2.0),
          ),
        );
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: state == KeyboardDeviceState.operating ? null : onPressed,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: iconWidget,
            ),
          ),
        ),
      ),
    );
  }
}

/// 1. 键盘服务状态开关卡片
class KeyboardStatusCard extends StatelessWidget {
  const KeyboardStatusCard({
    super.key,
    required this.isEnabled,
    required this.isReady,
    required this.isSending,
    this.isOperating = false,
    required this.onToggle,
  });

  final bool isEnabled;
  final bool isReady;
  final bool isSending;
  final bool isOperating;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color greenContainer =
        isDark ? const Color(0xff133624) : const Color(0xffe8f8ee);
    final Color greenIconContainer =
        isDark ? const Color(0xff1b4832) : const Color(0xffd4f4df);
    final Color greenContent =
        isDark ? const Color(0xff4ade80) : const Color(0xff16a34a);

    final String titleText = isEnabled
        ? (isSending
            ? l10n.text('keyboardStatusSending')
            : l10n.text('keyboardStatusReady'))
        : l10n.text('keyboardStatusStopped');

    final String subText = isEnabled
        ? l10n.text('keyboardStatusReadySub')
        : l10n.text('keyboardStatusStoppedSub');

    return Card(
      elevation: 0,
      color: isEnabled ? greenContainer : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isEnabled
              ? greenContent.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 图标徽标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isEnabled
                    ? greenIconContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.keyboard_outlined,
                color: isEnabled ? greenContent : colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),

            // 状态标题与副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isEnabled
                          ? (isDark
                              ? const Color(0xff86efac)
                              : const Color(0xff166534))
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subText,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isEnabled
                          ? greenContent
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // 原生 Android Switch 开关（操作中时置灰不可点击）
            Switch(
              value: isEnabled,
              onChanged: isOperating ? null : onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

/// 2. 文本输入与发送控制卡片
class KeyboardInputSection extends StatelessWidget {
  const KeyboardInputSection({
    super.key,
    required this.isEnabled,
    required this.isSending,
    required this.sendingProgress,
    required this.textController,
    required this.onSendText,
    required this.onCancelSend,
  });

  final bool isEnabled;
  final bool isSending;
  final double sendingProgress;
  final TextEditingController textController;
  final ValueChanged<String> onSendText;
  final VoidCallback onCancelSend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏：标签 + 清空按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.text('keyboardInputLabel'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: textController,
                  builder: (context, value, child) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => textController.clear(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.clear_rounded,
                              size: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              l10n.text('keyboardClear'),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 多行文本输入框
            TextField(
              controller: textController,
              maxLines: 4,
              minLines: 3,
              enabled: !isSending,
              decoration: InputDecoration(
                hintText: l10n.text('keyboardInputPlaceholder'),
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 14),

            // 进度条（发送中展示）
            if (isSending) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.text('keyboardSendingProgress'),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${(sendingProgress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: sendingProgress,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 14),
            ],

            // 发送 / 取消发送 主操作按钮
            SizedBox(
              height: 46,
              child: isSending
                  ? FilledButton.icon(
                      onPressed: onCancelSend,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: Text(l10n.text('keyboardBtnCancelSend')),
                      style: FilledButton.styleFrom(
                        foregroundColor: colorScheme.onError,
                        backgroundColor: colorScheme.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: isEnabled
                          ? () {
                              final text = textController.text.trim();
                              if (text.isNotEmpty) {
                                onSendText(text);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(l10n.text('keyboardBtnSend')),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3. 打字速度与按键发送间隔设置卡片
class TypingIntervalSettingCard extends StatelessWidget {
  const TypingIntervalSettingCard({
    super.key,
    required this.intervalMs,
    required this.onIntervalChanged,
  });

  final int intervalMs;
  final ValueChanged<int> onIntervalChanged;

  static const List<int> _presetIntervals = [5, 10, 20, 50, 100];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶行：图标 + 标题 + 当前数值
            Row(
              children: [
                Icon(
                  Icons.speed_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('keyboardIntervalLabel'),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l10n.text('keyboardIntervalSub'),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$intervalMs ms',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 滑块 (1ms .. 100ms)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4.0,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 16.0),
              ),
              child: Slider(
                value: intervalMs.toDouble().clamp(1.0, 100.0),
                min: 1.0,
                max: 100.0,
                divisions: 99,
                onChanged: (val) => onIntervalChanged(val.round()),
              ),
            ),

            // 常用间隔快速预设胶囊
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _presetIntervals.map((ms) {
                final isSelected = intervalMs == ms;
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onIntervalChanged(ms),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${ms}ms',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 将 87 键按键规格映射为 Core 标准按键名称
String? keySpecToCoreKeyName(KeySpec spec) {
  switch (spec.usage) {
    case 0x04: return 'A';
    case 0x05: return 'B';
    case 0x06: return 'C';
    case 0x07: return 'D';
    case 0x08: return 'E';
    case 0x09: return 'F';
    case 0x0a: return 'G';
    case 0x0b: return 'H';
    case 0x0c: return 'I';
    case 0x0d: return 'J';
    case 0x0e: return 'K';
    case 0x0f: return 'L';
    case 0x10: return 'M';
    case 0x11: return 'N';
    case 0x12: return 'O';
    case 0x13: return 'P';
    case 0x14: return 'Q';
    case 0x15: return 'R';
    case 0x16: return 'S';
    case 0x17: return 'T';
    case 0x18: return 'U';
    case 0x19: return 'V';
    case 0x1a: return 'W';
    case 0x1b: return 'X';
    case 0x1c: return 'Y';
    case 0x1d: return 'Z';
    case 0x1e: return '1';
    case 0x1f: return '2';
    case 0x20: return '3';
    case 0x21: return '4';
    case 0x22: return '5';
    case 0x23: return '6';
    case 0x24: return '7';
    case 0x25: return '8';
    case 0x26: return '9';
    case 0x27: return '0';
    case 0x28: return 'ENTER';
    case 0x29: return 'ESC';
    case 0x2a: return 'BACKSPACE';
    case 0x2b: return 'TAB';
    case 0x2c: return 'SPACE';
    case 0x2d: return 'MINUS';
    case 0x2e: return 'EQUAL';
    case 0x2f: return 'LEFTBRACKET';
    case 0x30: return 'RIGHTBRACKET';
    case 0x31: return 'BACKSLASH';
    case 0x33: return 'SEMICOLON';
    case 0x34: return 'QUOTE';
    case 0x35: return 'GRAVE';
    case 0x36: return 'COMMA';
    case 0x37: return 'DOT';
    case 0x38: return 'SLASH';
    case 0x39: return 'CAPSLOCK';
    case 0x3a: return 'F1';
    case 0x3b: return 'F2';
    case 0x3c: return 'F3';
    case 0x3d: return 'F4';
    case 0x3e: return 'F5';
    case 0x3f: return 'F6';
    case 0x40: return 'F7';
    case 0x41: return 'F8';
    case 0x42: return 'F9';
    case 0x43: return 'F10';
    case 0x44: return 'F11';
    case 0x45: return 'F12';
    case 0x46: return 'PRINTSCREEN';
    case 0x47: return 'SCROLLLOCK';
    case 0x48: return 'PAUSE';
    case 0x49: return 'INSERT';
    case 0x4a: return 'HOME';
    case 0x4b: return 'PAGEUP';
    case 0x4c: return 'DELETE';
    case 0x4d: return 'END';
    case 0x4e: return 'PAGEDOWN';
    case 0x4f: return 'RIGHT';
    case 0x50: return 'LEFT';
    case 0x51: return 'DOWN';
    case 0x52: return 'UP';
    case 0x65: return 'MENU';
    default: return null;
  }
}

/// 解析修饰键掩码为 Core 协议名称列表
List<String> modifierMaskToNames(int mask) {
  final list = <String>[];
  if (mask & 0x01 != 0) list.add('CTRL');
  if (mask & 0x02 != 0) list.add('SHIFT');
  if (mask & 0x04 != 0) list.add('ALT');
  if (mask & 0x08 != 0) list.add('GUI');
  if (mask & 0x10 != 0) list.add('RCTRL');
  if (mask & 0x20 != 0) list.add('RSHIFT');
  if (mask & 0x40 != 0) list.add('RALT');
  if (mask & 0x80 != 0) list.add('RGUI');
  return list;
}

/// 4. 87 键标准虚拟键盘视图组件
class Full87KeyboardView extends StatefulWidget {
  const Full87KeyboardView({
    super.key,
    required this.enabled,
    this.onUpdateState,
    this.onKeyTap,
  });

  final bool enabled;
  final void Function(int modifier, List<int> usages)? onUpdateState;
  final void Function(KeySpec key, List<String> modifiers)? onKeyTap;

  @override
  State<Full87KeyboardView> createState() => _Full87KeyboardViewState();
}

class _Full87KeyboardViewState extends State<Full87KeyboardView> {
  final Set<KeySpec> _pressedKeys = {};

  void _updateKey(KeySpec key, bool pressed) {
    if (!widget.enabled) return;

    setState(() {
      if (pressed) {
        _pressedKeys.add(key);
      } else {
        _pressedKeys.remove(key);
      }
    });

    if (pressed) {
      if (key.modifier != 0) {
        widget.onKeyTap?.call(key, modifierMaskToNames(key.modifier));
      } else if (key.usage != 0) {
        final modifierMask =
            _pressedKeys.fold<int>(0, (mask, item) => mask | item.modifier);
        final modifiers = modifierMaskToNames(modifierMask);
        widget.onKeyTap?.call(key, modifiers);
      }
    }

    final modifierMask =
        _pressedKeys.fold<int>(0, (mask, item) => mask | item.modifier);
    final usages =
        _pressedKeys.map((k) => k.usage).where((u) => u != 0).toList();
    widget.onUpdateState?.call(modifierMask, usages);
  }

  @override
  void dispose() {
    _pressedKeys.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftHeld = _pressedKeys.any((k) => k.modifier == 0x02 || k.modifier == 0x20);

    return Column(
      children: standard87KeyRows.map((row) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              children: row.map((key) {
                if (key.spacer) {
                  return Spacer(flex: (key.units * 100).toInt());
                }
                return Expanded(
                  flex: (key.units * 100).toInt(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: _VirtualKeyButton(
                      keySpec: key,
                      displayLabel: key.displayedLabel(shiftHeld),
                      active: _pressedKeys.contains(key),
                      enabled: widget.enabled,
                      onPressedChange: (pressed) => _updateKey(key, pressed),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _VirtualKeyButton extends StatefulWidget {
  const _VirtualKeyButton({
    required this.keySpec,
    required this.displayLabel,
    required this.active,
    required this.enabled,
    required this.onPressedChange,
  });

  final KeySpec keySpec;
  final String displayLabel;
  final bool active;
  final bool enabled;
  final ValueChanged<bool> onPressedChange;

  @override
  State<_VirtualKeyButton> createState() => _VirtualKeyButtonState();
}

class _VirtualKeyButtonState extends State<_VirtualKeyButton> {
  bool _physicalDown = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDown = _physicalDown || widget.active;

    final Color containerBg;
    final Color textColor;

    if (widget.active) {
      containerBg = colorScheme.primary;
      textColor = colorScheme.onPrimary;
    } else if (widget.keySpec.special) {
      containerBg = colorScheme.surfaceContainerHigh;
      textColor = colorScheme.primary;
    } else {
      containerBg = colorScheme.surfaceContainerHighest;
      textColor = colorScheme.onSurface;
    }

    return Listener(
      onPointerDown: (_) {
        if (!widget.enabled) return;
        setState(() => _physicalDown = true);
        widget.onPressedChange(true);
      },
      onPointerUp: (_) {
        if (!widget.enabled) return;
        setState(() => _physicalDown = false);
        widget.onPressedChange(false);
      },
      onPointerCancel: (_) {
        if (!widget.enabled) return;
        setState(() => _physicalDown = false);
        widget.onPressedChange(false);
      },
      child: AnimatedScale(
        scale: isDown ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            color: containerBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.active
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.displayLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.enabled
                  ? textColor
                  : textColor.withValues(alpha: 0.35),
              fontWeight: (widget.keySpec.special || widget.active)
                  ? FontWeight.bold
                  : FontWeight.w500,
              fontSize: widget.displayLabel.length > 4
                  ? 9.0
                  : (widget.displayLabel.length > 2 ? 10.5 : 12.5),
            ),
          ),
        ),
      ),
    );
  }
}
