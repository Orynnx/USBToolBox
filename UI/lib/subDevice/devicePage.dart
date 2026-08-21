// ignore_for_file: file_names

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 全局默认主色调（淡紫蓝色，用于图标与选中态强调）
const _primary = Color(0xff596a9e);

/// 子设备详情页面的公共骨架组件（通用脚手架）
///
/// 负责承载子设备配置页面的导航栏（AppBar）、安全区域边距（SafeArea）以及滚动视图（SingleChildScrollView）。
/// 具体的内容与业务逻辑由各个子页面（如 DiskScreen, HidScreen 等）自行实现。
class DeviceScaffold extends StatelessWidget {
  const DeviceScaffold({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(26, 14, 26, 34),
  });

  /// 页面顶部导航栏标题
  final String title;

  /// 页面主体内容部件
  final Widget child;

  /// 导航栏右侧可选操作按钮（例如“新建/添加”操作）
  final Widget? action;

  /// 页面可滚动区域的内边距，默认为左右 26，上 14，下 34
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: action == null ? null : [action!],
    ),
    body: SafeArea(
      top: false, // 顶部由 AppBar 处理安全边距
      child: SingleChildScrollView(padding: padding, child: child),
    ),
  );
}

/// 子设备通用卡片容器组件
///
/// 提供扁平化圆角背景、统一的卡片内边距，并支持水波纹点击反馈效果。
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  /// 卡片内部嵌套的子部件
  final Widget child;

  /// 卡片点击事件回调；若为 null 则无点击交互
  final VoidCallback? onTap;

  /// 卡片内部内边距，默认四周 16
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias, // 抗锯齿裁剪，确保水波纹和背景限制在圆角内
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// 分组小节标题组件
///
/// 用于在设置卡片组上方显示小节分类名称（如“视频源”、“输出规格”、“存储选项”等）。
class DeviceSection extends StatelessWidget {
  const DeviceSection(this.title, {super.key});

  /// 分组小节名称文本
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 9),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xff717380),
      ),
    ),
  );
}

/// 设备启停与状态展示卡片组件
///
/// 包含：
/// 1. 左侧：圆形状态指示图标（启用时呈现浅绿底深绿图标，未启用时为灰色底主色图标）；
/// 2. 中间：设备名称及当前运行状态描述（例如“运行中”、“已停用”）；
/// 3. 右侧：直接控制该子设备启停的 Switch 开关。
class DeviceStatusCard extends StatelessWidget {
  const DeviceStatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.enabled,
    required this.onChanged,
    this.detail,
  });

  /// 设备功能图标
  final IconData icon;

  /// 设备主标题名称
  final String title;

  /// 状态描述文本（若为 null 则自动根据 enabled 状态显示“运行中”或“已停用”）
  final String? detail;

  /// 当前是否处于启用运行状态
  final bool enabled;

  /// 切换启停开关时的状态变更回调
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => DeviceCard(
    child: Row(
      children: [
        // 左侧圆形图标状态徽标
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xffc4ead6) : const Color(0xffe3e3ec),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: enabled ? const Color(0xff16784e) : _primary,
          ),
        ),
        const SizedBox(width: 13),
        // 中间文本描述区域
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail ??
                    (enabled
                        ? context.l10n.text('running')
                        : context.l10n.text('disabled')),
                style: const TextStyle(fontSize: 13, color: Color(0xff787a87)),
              ),
            ],
          ),
        ),
        // 右侧启停 Switch 开关
        Switch(value: enabled, onChanged: onChanged),
      ],
    ),
  );
}

/// 单选/标签胶囊芯片组件
///
/// 基于 Material [ChoiceChip] 封装，用于分辨率、波特率、视频源等选项的快速点选。
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// 选项标签文本
  final String label;

  /// 当前项是否被选中
  final bool selected;

  /// 点击选中时的回调事件
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}

/// 默认组件间距大小常量
const double deviceGap = 12;
