// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'aboutSettingsScreen.dart';
import 'coreSettingsScreen.dart';
import 'themeSettingsScreen.dart';

/// 设置主页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部大标题（与从设备主页面保持完全一致的字体排版与边距）
              Text(
                l10n.text('settings'),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  height: 1.12,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 24),

              // Material 3 卡片式设置分组
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // 1. 主题设置
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.palette_outlined,
                          color: colorScheme.primary,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        l10n.text('themeSettings'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        l10n.text('themeSettingsDesc'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoute(
                            builder: (_) => const ThemeSettingsScreen(),
                          ),
                        );
                      },
                    ),
                    Divider(
                      height: 1,
                      indent: 68,
                      endIndent: 16,
                      color: colorScheme.outlineVariant.withValues(alpha: .5),
                    ),

                    // 2. USB Core 管理
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.memory_outlined,
                          color: colorScheme.secondary,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        l10n.text('usbCoreSettings'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        l10n.text('usbCoreSettingsDesc'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoute(
                            builder: (_) => const CoreSettingsScreen(),
                          ),
                        );
                      },
                    ),
                    Divider(
                      height: 1,
                      indent: 68,
                      endIndent: 16,
                      color: colorScheme.outlineVariant.withValues(alpha: .5),
                    ),

                    // 3. 关于
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.info_outline_rounded,
                          color: colorScheme.tertiary,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        l10n.text('about'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        l10n.text('aboutSettingsDesc'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoute(
                            builder: (_) => const AboutSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
