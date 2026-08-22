// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/core_client.dart';
import '../core/core_deployment_service.dart';
import '../core/root_shell_service.dart';
import '../l10n/app_localizations.dart';

/// 关于 HyperUSB 详情页面
class AboutSettingsScreen extends StatefulWidget {
  const AboutSettingsScreen({super.key});

  @override
  State<AboutSettingsScreen> createState() => _AboutSettingsScreenState();
}

class _AboutSettingsScreenState extends State<AboutSettingsScreen> {
  final _root = RootShellService();
  late final _client = CoreClient(_root);
  late final _deployment = CoreDeploymentService(_root, _client);

  /// 核心守护进程版本号
  String? _coreVersion;

  /// 彩蛋连击计数器
  int _easterEggTapCount = 0;
  DateTime? _lastTapTime;

  /// 作者头像在线地址
  static const String _avatarUrl =
      'https://avatars.githubusercontent.com/u/98645428?v=4&size=64';

  /// 社交与反馈渠道常量
  static const String _githubUrl = 'https://github.com/Orynnx/USBToolBox';
  static const String _emailAddress = 'orynnx@gmail.com';
  static const String _qqNumber = '323602123';

  @override
  void initState() {
    super.initState();
    _fetchCoreVersion();
  }

  Future<void> _fetchCoreVersion() async {
    try {
      final status = await _deployment.getInstallationStatus();
      if (mounted) {
        setState(() {
          _coreVersion = status.version;
        });
      }
    } catch (_) {
      // 获取失败或未安装时保持 null
    }
  }

  /// 触发开发者信息点击彩蛋
  void _handleDeveloperTap() {
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
      _easterEggTapCount = 1;
    } else {
      _easterEggTapCount++;
    }
    _lastTapTime = now;

    if (_easterEggTapCount >= 5) {
      _easterEggTapCount = 0;
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.text('easterEggNotice'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 复制文本到剪贴板并提示
  void _copyToClipboard(String content, String message) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('about')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // 1. 居中大字 HyperUSB（其中 USB 是主题色）
              Center(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: colorScheme.onSurface,
                    ),
                    children: [
                      const TextSpan(text: 'Hyper'),
                      TextSpan(
                        text: 'USB',
                        style: TextStyle(
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 2. 开发者卡片（头像、Orynnx、Slogan 凛野想要，凛野得到！支持 5 击彩蛋）
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _handleDeveloperTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        // 作者头像
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            _avatarUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                color: colorScheme.primary,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 开发者与 Slogan
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.text('developerName'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                l10n.text('developerSlogan'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. 版本信息卡片
              Text(
                l10n.text('versionInfo'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        title: Text(
                          l10n.text('currentVersion'),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Text(
                          '1.0.0+1',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        title: Text(
                          l10n.text('usbCoreVersion'),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Text(
                          _coreVersion ?? l10n.text('usbCoreInstalled'),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _coreVersion != null
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 4. 致谢与联系渠道卡片
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('thankYouMsg1'),
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.text('thankYouMsg2'),
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.text('thankYouMsg3'),
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 渠道按钮组 (GitHub Logo, Email Logo, QQ Logo)
                      Row(
                        children: [
                          // GitHub 按钮
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _copyToClipboard(
                                _githubUrl,
                                '${l10n.text('copiedToClipboard')}: $_githubUrl',
                              ),
                              icon: const Icon(Icons.code_rounded, size: 18),
                              label: const Text('GitHub'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Email 按钮
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _copyToClipboard(
                                _emailAddress,
                                '${l10n.text('copiedToClipboard')}: $_emailAddress',
                              ),
                              icon: const Icon(Icons.email_outlined, size: 18),
                              label: const Text('Email'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // QQ 按钮
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _copyToClipboard(
                                _qqNumber,
                                '${l10n.text('copiedToClipboard')}: $_qqNumber',
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('QQ'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
