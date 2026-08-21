// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../hid/keyboard_service.dart';
import '../../l10n/app_localizations.dart';
import 'components.dart';

/// 87 键横屏全屏虚拟键盘独立页面
class FullKeyboardScreen extends StatefulWidget {
  const FullKeyboardScreen({
    super.key,
    required this.isEnabled,
    this.onUpdatePressedKeys,
    this.service,
  });

  final bool isEnabled;
  final void Function(int modifier, List<int> usages)? onUpdatePressedKeys;
  final KeyboardService? service;

  @override
  State<FullKeyboardScreen> createState() => _FullKeyboardScreenState();
}

class _FullKeyboardScreenState extends State<FullKeyboardScreen> {
  KeyboardService get _service => widget.service ?? KeyboardService.instance;

  @override
  void initState() {
    super.initState();
    // 强制横屏并进入沉浸式全屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // 恢复竖屏与系统栏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _handleKeyTap(KeySpec key, List<String> modifiers) {
    final keyName = keySpecToCoreKeyName(key);
    if (keyName != null) {
      _service.sendKey(keyName, modifiers: modifiers).catchError((_) {});
    } else if (modifiers.isNotEmpty) {
      _service.sendModifiers(modifiers).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: Column(
            children: [
              // 顶部状态栏
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Icon(
                      Icons.keyboard_outlined,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.text('keyboardLandscapeTitle'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isEnabled
                            ? colorScheme.primary.withValues(alpha: 0.15)
                            : colorScheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.isEnabled
                            ? l10n.text('commonReady')
                            : l10n.text('commonNotEnabled'),
                        style: TextStyle(
                          color: widget.isEnabled
                              ? colorScheme.primary
                              : colorScheme.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.text('keyboardLandscapeSub'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // 87 键全键盘矩阵（自动充满剩余视口高度）
              Expanded(
                child: Full87KeyboardView(
                  enabled: widget.isEnabled,
                  onUpdateState: widget.onUpdatePressedKeys,
                  onKeyTap: _handleKeyTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
