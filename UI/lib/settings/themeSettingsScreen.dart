// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// 具备淡入淡出与尺寸平滑过渡的折叠动效组件
class _CollapsibleSection extends StatelessWidget {
  final bool visible;
  final Duration duration;
  final Widget child;

  const _CollapsibleSection({
    required this.visible,
    required this.duration,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: child,
      secondChild: const SizedBox(width: double.infinity, height: 0),
      crossFadeState:
          visible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      duration: duration,
      sizeCurve: Curves.easeInOutCubicEmphasized,
      firstCurve: Curves.easeOutCubic,
      secondCurve: Curves.easeInCubic,
    );
  }
}

/// 主题设置页面
class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key});

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('themeSettings')),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: appThemeManager,
          builder: (context, _) {
            final animDuration = appThemeManager.disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 320);

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              // 1. 主题模式（跟随系统、浅色、深色）
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('displayMode'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text(l10n.text('systemMode')),
                            icon: const Icon(Icons.brightness_auto_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text(l10n.text('lightMode')),
                            icon: const Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text(l10n.text('darkMode')),
                            icon: const Icon(Icons.dark_mode_outlined),
                          ),
                        ],
                        selected: {appThemeManager.themeMode},
                        onSelectionChanged: (modes) {
                          appThemeManager.setThemeMode(modes.first);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // 2. 配色方案与动态取色
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('colorSchemeTitle'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 动态取色开关
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.auto_awesome_outlined),
                        title: Text(
                          l10n.text('dynamicColor'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          l10n.text('dynamicColorDesc'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: appThemeManager.useDynamicColor,
                        onChanged: (val) {
                          appThemeManager.setUseDynamicColor(val);
                        },
                      ),
                      // 动态取色开启时折叠取色面板（带有流畅出现/消失淡入与高度展开动画）
                      _CollapsibleSection(
                        visible: !appThemeManager.useDynamicColor,
                        duration: animDuration,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 16),
                            Text(
                              l10n.text('colorSchemeDesc'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: appThemePresets.map((preset) {
                                final isSelected =
                                    !appThemeManager.useDynamicColor &&
                                    (appThemeManager.currentPresetId ==
                                            preset.id ||
                                        appThemeManager.seedColor ==
                                            preset.color);

                                return ChoiceChip(
                                  avatar: CircleAvatar(
                                    backgroundColor: preset.color,
                                    radius: 8,
                                  ),
                                  label: Text(l10n.text(preset.nameKey)),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) {
                                      appThemeManager.setSeedColor(
                                        preset.color,
                                        preset.id,
                                      );
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. 动画特性（移除所有动画在上方，预测性返回在下方并根据动画状态折叠）
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('features'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 1. 移除所有动画开关（放在预测性返回手势上面）
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.motion_photos_off_outlined),
                        title: Text(
                          l10n.text('disableAnimations'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          l10n.text('disableAnimationsDesc'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: appThemeManager.disableAnimations,
                        onChanged: (val) {
                          appThemeManager.setDisableAnimations(val);
                        },
                      ),
                      // 2. 预测性返回手势（关闭动画时自动关闭并折叠，带有流畅出现/消失动画）
                      _CollapsibleSection(
                        visible: !appThemeManager.disableAnimations,
                        duration: animDuration,
                        child: Column(
                          children: [
                            const Divider(height: 16),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(
                                Icons.swipe_left_rounded,
                              ),
                              title: Text(
                                l10n.text('predictiveBack'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                l10n.text('predictiveBackDesc'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              value: appThemeManager.enablePredictiveBack,
                              onChanged: (val) {
                                appThemeManager.setEnablePredictiveBack(val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  }
}
