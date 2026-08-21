// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter/material.dart';
import '../core/core_client.dart';
import '../core/root_shell_service.dart';
import '../l10n/app_localizations.dart';
import '../storage/services/disk_storage_service.dart';
import '../usb/usb_session_service.dart';
import 'cam/camScreen.dart';
import 'disk/diskScreen.dart';
import 'hid/hidScreen.dart';
import 'net/netScreen.dart';
import 'serial/serialScreen.dart';
import 'devicePage.dart';
import '../theme/app_theme.dart';

/// HyperUSB 主控制中心页面
///
/// 汇总展示 HyperUSB 总控制器运行状态、5 种虚拟子设备（磁盘、HID 键盘、虚拟网卡、UVC 摄像头、虚拟串口）的快速入口及运行环境信息。
class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.client,
    this.session,
    this.disks,
  });

  final CoreClient? client;
  final UsbSessionService? session;
  final DiskStorageService? disks;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late final CoreClient _client;
  late final UsbSessionService _session;
  late final DiskStorageService _disks;

  /// HyperUSB 核心服务总运行状态（true: 运行中, false: 已停止）
  bool _running = false;
  bool _coreConnected = false;
  bool _isOperating = false;

  /// 各子设备的启用激活状态映射表
  final _enabled = <String, bool>{
    'disk': false, // 虚拟磁盘
    'hid': false, // 虚拟 HID (键盘)
    'net': false, // 虚拟网络适配器
    'cam': false, // 虚拟 UVC 摄像头
    'serial': false, // 虚拟串口
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = widget.client ?? CoreClient(RootShellService());
    _session = widget.session ?? UsbSessionService.instance;
    _disks = widget.disks ?? DiskStorageService();
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _client.getStatus();
      if (!mounted) return;
      setState(() {
        _coreConnected = true;
        _running = status.active;
        _enabled['disk'] = status.active && status.storageLuns.isNotEmpty;
        _enabled['hid'] = status.active && status.keyboard;
        _enabled['serial'] = status.active && status.serial;
        _enabled['cam'] = status.active && status.uvc;
        _enabled['net'] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _coreConnected = false;
        _running = false;
        _enabled['disk'] = false;
        _enabled['hid'] = false;
        _enabled['serial'] = false;
        _enabled['cam'] = false;
        _enabled['net'] = false;
      });
    }
  }

  Future<void> _toggleMaster() async {
    if (_isOperating) return;
    setState(() => _isOperating = true);
    try {
      if (_running) {
        final status = await _session.stopAll();
        if (!mounted) return;
        setState(() {
          _coreConnected = true;
          _running = status.active;
          _enabled['disk'] = false;
          _enabled['hid'] = false;
          _enabled['serial'] = false;
          _enabled['cam'] = false;
          _enabled['net'] = false;
        });
      } else {
        final disks = await _disks.load();
        final status = await _session.apply(disks);
        if (!mounted) return;
        setState(() {
          _coreConnected = true;
          _running = status.active;
          _enabled['disk'] = status.active && status.storageLuns.isNotEmpty;
          _enabled['hid'] = status.active && status.keyboard;
          _enabled['serial'] = status.active && status.serial;
          _enabled['cam'] = status.active && status.uvc;
          _enabled['net'] = false;
        });
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

  /// 页面导航辅助方法，推入指定的子设备详情配置页面并在返回时刷新真实状态
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(AppPageRoute(builder: (_) => page));
    if (mounted) {
      await _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取多语言本地化资源对象
    final l = context.l10n;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部大标题：控制器标题（如“HyperUSB 控制中心”）
              Text(
                l.text('controllerTitle'),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  height: 1.12,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 24),

              // 2. 第一组功能区：左侧总控大卡片 + 右侧 3 个子设备快捷入口卡片
              IntrinsicHeight(
                child: Row(
                  children: [
                    // 左侧：总控制器启停切换卡片
                    Expanded(
                      child: _ControllerCard(
                        running: _running,
                        onTap: _toggleMaster,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 右侧：垂直排列的 3 个子设备小卡片
                    Expanded(
                      child: Column(
                        children: [
                          // 虚拟磁盘入口
                          Expanded(
                            child: _DeviceMini(
                              icon: Icons.storage_rounded,
                              title: l.text('virtualDisks'),
                              active: _enabled['disk']!,
                              onTap: () => _open(const DiskScreen()),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 虚拟 HID 键盘入口
                          Expanded(
                            child: _DeviceMini(
                              icon: Icons.keyboard_rounded,
                              title: l.text('virtualHid'),
                              active: _enabled['hid']!,
                              onTap: () => _open(const HidScreen()),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 虚拟网络适配器入口
                          Expanded(
                            child: _DeviceMini(
                              icon: Icons.lan_rounded,
                              title: l.text('virtualNetwork'),
                              active: _enabled['net']!,
                              onTap: () => _open(const NetScreen()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 3. 第二组功能区：水平并排的另外 2 个子设备快捷卡片（摄像头与串口）
              Row(
                children: [
                  // 虚拟摄像头入口
                  Expanded(
                    child: _DeviceMini(
                      icon: Icons.videocam_rounded,
                      title: l.text('virtualWebcam'),
                      active: _enabled['cam']!,
                      onTap: () => _open(const CamScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 虚拟串口入口
                  Expanded(
                    child: _DeviceMini(
                      icon: Icons.terminal_rounded,
                      title: l.text('virtualSerial'),
                      active: _enabled['serial']!,
                      onTap: () => _open(const SerialScreen()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              DeviceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.text('environmentInfo'), // “运行环境详情”
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 管理器版本号
                    _InfoLine(l.text('managerVersion'), '1.0.0'),
                    // 控制器状态（运行中 / 已停止）
                    _InfoLine(
                      l.text('controllerState'),
                      _running ? l.text('running') : l.text('stopped'),
                    ),
                    // 运行操作系统平台（如 android, windows 等）
                    _InfoLine(l.text('platform'), Platform.operatingSystem),
                    // 操作系统完整版本号
                    _InfoLine(
                      l.text('systemVersion'),
                      Platform.operatingSystemVersion.split('\n').first,
                    ),
                    // 底层 Core 原生库集成状态
                    _InfoLine(
                      l.text('coreIntegration'),
                      _coreConnected ? l.text('connected') : l.text('notConnected'),
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

/// 主控制器启停状态大卡片
///
/// 具备醒目的背景色变换（运行中为浅绿，停止为浅红）以及右下角装饰性巨型状态图标。
class _ControllerCard extends StatefulWidget {
  const _ControllerCard({required this.running, required this.onTap});

  final bool running;
  final VoidCallback onTap;

  @override
  State<_ControllerCard> createState() => _ControllerCardState();
}

class _ControllerCardState extends State<_ControllerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _colorController;

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(
      value: widget.running ? 1 : 0,
      duration: const Duration(milliseconds: 620),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant _ControllerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) {
      widget.running ? _colorController.forward() : _colorController.reverse();
    }
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stoppedColor = colorScheme.errorContainer;
    final runningColor = colorScheme.primaryContainer;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _colorController,
        builder: (context, child) {
          final progress = Curves.easeInOutCubic.transform(
            _colorController.value,
          );
          final trailingProgress = ((progress - .18) / .82).clamp(0.0, 1.0);
          final leading = Color.lerp(stoppedColor, runningColor, progress)!;
          final trailing = Color.lerp(
            stoppedColor,
            runningColor,
            trailingProgress,
          )!;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [leading, trailing],
              ),
            ),
            child: child,
          );
        },
        child: InkWell(
          onTap: widget.onTap,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                // KernelSU StatusCard: BottomEnd plus offset(27dp, 31dp).
                right: -27,
                bottom: -31,
                child: _StatusGlyph(running: widget.running),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.running
                          ? context.l10n.text('running')
                          : context.l10n.text('stopped'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.running
                          ? context.l10n.text('usbControlled')
                          : context.l10n.text('usbManaged'),
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: .68),
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
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

class _StatusGlyph extends StatefulWidget {
  const _StatusGlyph({required this.running});

  final bool running;

  @override
  State<_StatusGlyph> createState() => _StatusGlyphState();
}

class _StatusGlyphState extends State<_StatusGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      value: widget.running ? 1 : 0,
      duration: const Duration(milliseconds: 620),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant _StatusGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) {
      // animateTo starts from the live value. Repeated taps therefore reverse
      // or continue the single AB/BA timeline instead of restarting it.
      _controller.animateTo(
        widget.running ? 1 : 0,
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final isCrossingToRunning = _controller.value < .5;
      final phase = isCrossingToRunning
          ? _controller.value / .5
          : (_controller.value - .5) / .5;
      final eased = Curves.easeInOutCubicEmphasized.transform(phase);
      final isRunning = !isCrossingToRunning;

      // One continuous AB/BA stage: switch glyph only at the fully transparent
      // midpoint, so there is never a cross-fade overlap.
      final angle = isCrossingToRunning ? -.22 * eased : .22 * (1 - eased);
      final colorScheme = Theme.of(context).colorScheme;

      return Opacity(
        opacity: isCrossingToRunning ? 1 - eased : eased,
        child: Transform.rotate(
          alignment: Alignment.bottomRight,
          angle: angle,
          child: Icon(
            isRunning
                ? Icons.check_circle_outline_rounded
                : Icons.cancel_rounded,
            color: isRunning ? colorScheme.primary : colorScheme.error,
            size: 112,
          ),
        ),
      );
    },
  );
}

/// 子设备迷你快捷入口卡片组件
///
/// 展示子设备图标、名称、运行状态小圆点与“已启用/已停用”文本，点击后导航至对应子设备详情页。
class _DeviceMini extends StatelessWidget {
  const _DeviceMini({
    required this.icon,
    required this.title,
    required this.active,
    required this.onTap,
  });

  /// 设备图标
  final IconData icon;

  /// 设备显示名称
  final String title;

  /// 当前是否处于激活运行状态
  final bool active;

  /// 点击跳转回调
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DeviceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：图标 + 设备标题
          Row(
            children: [
              Icon(icon, size: 17, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // 第二行：状态指示圆点 + 激活状态文本
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                active
                    ? context.l10n.text('enabled') // “已启用”
                    : context.l10n.text('disabled'), // “已停用”
                style: TextStyle(
                  fontSize: 11.5,
                  color: active
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 键值对环境信息行展示组件
///
/// 上方显示属性标签（粗体），下方显示具体属性值（灰字）。
class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  /// 属性名称标签
  final String label;

  /// 属性值内容
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
