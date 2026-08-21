// ignore_for_file: file_names

import 'dart:async';
import 'package:flutter/material.dart';
import '../../hid/keyboard_service.dart';
import '../../l10n/app_localizations.dart';
import '../devicePage.dart';
import 'components.dart';
import 'fullKeyboardScreen.dart';

/// USB HID 虚拟键盘主页面
class HidScreen extends StatefulWidget {
  const HidScreen({
    super.key,
    this.service,
  });

  final KeyboardService? service;

  @override
  State<HidScreen> createState() => _HidScreenState();
}

class _HidScreenState extends State<HidScreen> {
  late final KeyboardService _service;
  late final TextEditingController _textController;
  StreamSubscription<KeyboardServiceStatus>? _subscription;

  KeyboardServiceStatus _status = const KeyboardServiceStatus.initial();
  int _typingIntervalMs = 20;
  bool _isOperating = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? KeyboardService.instance;
    _status = _service.currentStatus;
    _textController = TextEditingController();

    _subscription = _service.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    });

    _service.refreshStatus();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _openFullKeyboard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullKeyboardScreen(
          isEnabled: _status.ready && !_status.isSending,
          service: _service,
        ),
      ),
    );
  }

  Future<void> _handleToggle(bool enable) async {
    if (_isOperating) return;
    setState(() => _isOperating = true);

    try {
      if (enable) {
        await _service.enable();
      } else {
        await _service.disable();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isOperating = false);
      }
    }
  }

  Future<void> _handleSendText(String text) async {
    try {
      await _service.typeText(
        text,
        intervalMs: _typingIntervalMs,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _handleCancelSend() {
    _service.cancelTyping();
  }

  void _handleKeyTap(KeySpec key, List<String> modifiers) {
    final keyName = keySpecToCoreKeyName(key);
    if (keyName != null) {
      _service.sendKey(keyName, modifiers: modifiers).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      });
    } else if (modifiers.isNotEmpty) {
      _service.sendModifiers(modifiers).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DeviceScaffold(
      title: l10n.text('virtualHid'),
      action: IconButton(
        tooltip: l10n.text('keyboardFullscreenAction'),
        icon: const Icon(Icons.fullscreen_rounded),
        onPressed: _openFullKeyboard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 键盘服务状态开关卡片
          KeyboardStatusCard(
            isEnabled: _status.enabled,
            isReady: _status.ready,
            isSending: _status.isSending,
            isOperating: _isOperating,
            onToggle: _isOperating ? (_) {} : _handleToggle,
          ),
          const SizedBox(height: 16),

          // 2. 文本输入与发送控制
          _buildSectionHeader(context, l10n.text('keyboardSectionSendTitle')),
          const SizedBox(height: 8),
          KeyboardInputSection(
            isEnabled: _status.ready && !_isOperating,
            isSending: _status.isSending,
            sendingProgress: _status.sendingProgress,
            textController: _textController,
            onSendText: _handleSendText,
            onCancelSend: _handleCancelSend,
          ),
          const SizedBox(height: 16),

          // 3. 设置发送按键间隔的控件
          _buildSectionHeader(
            context,
            l10n.text('keyboardSectionIntervalTitle'),
          ),
          const SizedBox(height: 8),
          TypingIntervalSettingCard(
            intervalMs: _typingIntervalMs,
            onIntervalChanged: (val) {
              setState(() {
                _typingIntervalMs = val;
              });
            },
          ),
          const SizedBox(height: 16),

          // 4. 87 键标准虚拟键盘面板
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader(
                context,
                l10n.text('keyboardSection87Title'),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _openFullKeyboard,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fullscreen_rounded,
                        size: 15,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        l10n.text('keyboardFullscreenAction'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.text('keyboard87Desc'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 87 键水平滚动预览容器
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 820,
                      height: 230,
                      child: Full87KeyboardView(
                        enabled: _status.ready && !_status.isSending,
                        onKeyTap: _handleKeyTap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 2.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
