// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../core/core_client.dart';
import '../core/core_deployment_service.dart';
import '../core/root_shell_service.dart';

/// USB Core 管理页面
class CoreSettingsScreen extends StatefulWidget {
  const CoreSettingsScreen({super.key});

  @override
  State<CoreSettingsScreen> createState() => _CoreSettingsScreenState();
}

class _CoreSettingsScreenState extends State<CoreSettingsScreen> {
  final _root = RootShellService();
  late final _client = CoreClient(_root);
  late final _deployment = CoreDeploymentService(_root, _client);
  bool _isInstalled = false;
  bool _isProcessing = false;
  String? _version;
  bool _daemonRunning = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await _deployment.getInstallationStatus();
      if (mounted) {
        setState(() {
          _isInstalled = status.installed;
          _daemonRunning = status.running;
          _version = status.version;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isInstalled = false;
          _daemonRunning = false;
          _version = null;
        });
      }
    }
  }

  void _toggleInstallation() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      if (_isInstalled) {
        await _deployment.remove();
      } else {
        await _deployment.ensureReady();
      }
      await _refresh();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('usbCoreSettings'))),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. 顶部状态与操作卡片（整体着色）
          Card(
            elevation: 0,
            color: _isInstalled
                ? (isDark ? const Color(0xff133624) : const Color(0xffe8f8ee))
                : (isDark ? const Color(0xff2e2318) : const Color(0xfffff7ed)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: _isInstalled
                    ? (isDark
                          ? const Color(0xff4ade80).withValues(alpha: 0.4)
                          : const Color(0xff16a34a).withValues(alpha: 0.35))
                    : (isDark
                          ? const Color(0xfff59e0b).withValues(alpha: 0.4)
                          : const Color(0xffd97706).withValues(alpha: 0.35)),
                width: 1.2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 状态展示行
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _isInstalled
                              ? (isDark
                                    ? const Color(0xff1b4832)
                                    : const Color(0xffd4f4df))
                              : (isDark
                                    ? const Color(0xff453420)
                                    : const Color(0xfffed7aa)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isInstalled
                              ? Icons.verified_rounded
                              : Icons.cloud_download_outlined,
                          color: _isInstalled
                              ? (isDark
                                    ? const Color(0xff4ade80)
                                    : const Color(0xff16a34a))
                              : (isDark
                                    ? const Color(0xfffbbf24)
                                    : const Color(0xffd97706)),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _isInstalled
                              ? l10n.text('usbCoreInstalled')
                              : l10n.text('usbCoreNotInstalled'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: _isInstalled
                                ? (isDark
                                      ? const Color(0xff86efac)
                                      : const Color(0xff166534))
                                : (isDark
                                      ? const Color(0xfffde68a)
                                      : const Color(0xff9a3412)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 释放 / 移除 USB Core 操作按钮（与卡片基色自然融洽，避免高冲突撞色）
                  SizedBox(
                    height: 44,
                    child: _isInstalled
                        ? OutlinedButton.icon(
                            onPressed: _isProcessing
                                ? null
                                : _toggleInstallation,
                            icon: _isProcessing
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        isDark
                                            ? const Color(0xfffca5a5)
                                            : const Color(0xffb91c1c),
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                            label: Text(l10n.text('removeUsbCore')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? const Color(0xfffca5a5)
                                  : const Color(0xffb91c1c),
                              side: BorderSide(
                                color:
                                    (isDark
                                            ? const Color(0xfffca5a5)
                                            : const Color(0xffb91c1c))
                                        .withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: _isProcessing
                                ? null
                                : _toggleInstallation,
                            icon: _isProcessing
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        isDark
                                            ? const Color(0xff1c1308)
                                            : Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.download_rounded, size: 18),
                            label: Text(l10n.text('deployUsbCore')),
                            style: FilledButton.styleFrom(
                              foregroundColor: isDark
                                  ? const Color(0xff1c1308)
                                  : Colors.white,
                              backgroundColor: isDark
                                  ? const Color(0xfff59e0b)
                                  : const Color(0xffd97706),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. 下部描述卡片（版本、构建时间、挂载路径、套接字管道）
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 版本
                _buildInfoItem(
                  context,
                  title: l10n.text('coreVersion'),
                  value: _version ?? 'unavailable',
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                ),

                // 构建时间
                _buildInfoItem(
                  context,
                  title: l10n.text('buildTime'),
                  value: 'unavailable',
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                ),

                // 挂载路径
                _buildInfoItem(
                  context,
                  title: l10n.text('mountPath'),
                  value: _isInstalled ? '/data/adb/usb_sub/hyperusbd' : '—',
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                ),

                // 套接字管道
                _buildInfoItem(
                  context,
                  title: l10n.text('socketPipe'),
                  value: _daemonRunning
                      ? '/data/adb/usb_sub/usb.sock (ready)'
                      : '/data/adb/usb_sub/usb.sock (not ready)',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context, {
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 13.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
