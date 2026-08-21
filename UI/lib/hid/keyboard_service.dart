import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/core_client.dart';
import '../../core/core_deployment_service.dart';
import '../../core/root_shell_service.dart';
import '../../storage/services/disk_storage_service.dart';
import '../../usb/usb_session_service.dart';
import 'keyboard_text_encoder.dart';

class KeyboardServiceStatus {
  const KeyboardServiceStatus({
    required this.enabled,
    required this.ready,
    this.isSending = false,
    this.sendingProgress = 0.0,
    this.lastError,
  });

  final bool enabled;
  final bool ready;
  final bool isSending;
  final double sendingProgress;
  final String? lastError;

  const KeyboardServiceStatus.initial()
      : enabled = false,
        ready = false,
        isSending = false,
        sendingProgress = 0.0,
        lastError = null;

  KeyboardServiceStatus copyWith({
    bool? enabled,
    bool? ready,
    bool? isSending,
    double? sendingProgress,
    String? lastError,
    bool clearError = false,
  }) =>
      KeyboardServiceStatus(
        enabled: enabled ?? this.enabled,
        ready: ready ?? this.ready,
        isSending: isSending ?? this.isSending,
        sendingProgress: sendingProgress ?? this.sendingProgress,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

class KeyboardService {
  KeyboardService({
    RootShellService? root,
    CoreClient? client,
    CoreDeploymentService? deployment,
    UsbSessionService? session,
    DiskStorageService? disks,
  })  : _client = client ?? CoreClient(root ?? RootShellService()),
        _deployment = deployment ??
            CoreDeploymentService(
              root ?? RootShellService(),
              client ?? CoreClient(root ?? RootShellService()),
            ),
        _session = session ??
            UsbSessionService(
              root ?? RootShellService(),
              deployment ??
                  CoreDeploymentService(
                    root ?? RootShellService(),
                    client ?? CoreClient(root ?? RootShellService()),
                  ),
              client ?? CoreClient(root ?? RootShellService()),
            ),
        _disks = disks ?? DiskStorageService();

  static final instance = KeyboardService();

  final CoreClient _client;
  final CoreDeploymentService _deployment;
  final UsbSessionService _session;
  final DiskStorageService _disks;

  final _statusController =
      StreamController<KeyboardServiceStatus>.broadcast();
  KeyboardServiceStatus _status = const KeyboardServiceStatus.initial();

  bool _isCancelled = false;

  Stream<KeyboardServiceStatus> get statusStream => _statusController.stream;
  KeyboardServiceStatus get currentStatus => _status;

  void _updateStatus(KeyboardServiceStatus newStatus) {
    _status = newStatus;
    _statusController.add(_status);
  }

  /// 开启 USB Boot Keyboard 功能
  Future<void> enable() async {
    try {
      _updateStatus(_status.copyWith(clearError: true));
      await _deployment.ensureReady();
      final disks = await _disks.load();
      final coreStatus = await _session.apply(disks, keyboardEnabled: true);
      _updateStatus(
        _status.copyWith(
          enabled: coreStatus.keyboard,
          ready: coreStatus.active && coreStatus.keyboard,
          clearError: true,
        ),
      );
    } catch (e) {
      _updateStatus(
        _status.copyWith(
          enabled: false,
          ready: false,
          lastError: e.toString(),
        ),
      );
      rethrow;
    }
  }

  /// 关闭 USB Boot Keyboard 功能
  Future<void> disable() async {
    try {
      _updateStatus(_status.copyWith(clearError: true));
      final disks = await _disks.load();
      final coreStatus = await _session.apply(disks, keyboardEnabled: false);
      _updateStatus(
        _status.copyWith(
          enabled: coreStatus.keyboard,
          ready: coreStatus.active && coreStatus.keyboard,
          clearError: true,
        ),
      );
    } catch (e) {
      _updateStatus(
        _status.copyWith(
          lastError: e.toString(),
        ),
      );
      rethrow;
    }
  }

  /// 刷新当前 Core 键盘状态
  Future<void> refreshStatus() async {
    try {
      final coreStatus = await _client.getStatus();
      _updateStatus(
        _status.copyWith(
          enabled: coreStatus.keyboard,
          ready: coreStatus.active && coreStatus.keyboard,
          clearError: true,
        ),
      );
    } catch (_) {
      // 忽略刷新阶段的网络或未启动异常
    }
  }

  /// 发送单个按键
  Future<void> sendKey(
    String key, {
    List<String> modifiers = const [],
  }) async {
    try {
      await _client.sendBootKey(modifiers: modifiers, key: key);
    } catch (e) {
      _updateStatus(_status.copyWith(lastError: e.toString()));
      rethrow;
    }
  }

  /// 发送独立修饰键 (例如单独按 Shift 切换中英文)
  Future<void> sendModifiers(List<String> modifiers) async {
    try {
      await _client.sendBootKey(modifiers: modifiers);
    } catch (e) {
      _updateStatus(_status.copyWith(lastError: e.toString()));
      rethrow;
    }
  }

  /// 发送快捷组合键
  Future<void> sendShortcut(List<String> modifiers, String key) async {
    try {
      await _client.sendBootKey(modifiers: modifiers, key: key);
    } catch (e) {
      _updateStatus(_status.copyWith(lastError: e.toString()));
      rethrow;
    }
  }

  /// 逐字发送文本
  Future<void> typeText(
    String text, {
    int intervalMs = 20,
    ValueChanged<double>? onProgress,
  }) async {
    if (text.isEmpty || _status.isSending) return;

    _isCancelled = false;
    final strokes = KeyboardTextEncoder.encodeText(text);
    if (strokes.isEmpty) return;

    _updateStatus(
      _status.copyWith(
        isSending: true,
        sendingProgress: 0.0,
        clearError: true,
      ),
    );

    final total = strokes.length;
    try {
      for (int i = 0; i < total; i++) {
        if (_isCancelled) break;

        final stroke = strokes[i];
        await _client.sendBootKey(
          modifiers: stroke.modifiers,
          key: stroke.key,
        );

        final progress = (i + 1) / total;
        onProgress?.call(progress);
        _updateStatus(_status.copyWith(sendingProgress: progress));

        if (i < total - 1 && intervalMs > 0) {
          await Future.delayed(Duration(milliseconds: intervalMs));
        }
      }
    } catch (e) {
      _updateStatus(
        _status.copyWith(
          isSending: false,
          sendingProgress: 0.0,
          lastError: e.toString(),
        ),
      );
      rethrow;
    } finally {
      _updateStatus(
        _status.copyWith(
          isSending: false,
          sendingProgress: 0.0,
        ),
      );
    }
  }

  /// 取消当前正在发送的文本序列
  void cancelTyping() {
    _isCancelled = true;
    _updateStatus(
      _status.copyWith(
        isSending: false,
        sendingProgress: 0.0,
      ),
    );
  }
}
