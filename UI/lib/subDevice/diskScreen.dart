// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'devicePage.dart';

/// 虚拟磁盘与存储设备（USB 大容量存储 Mass Storage）配置页面
///
/// 支持将移动设备模拟为标准 USB 闪存盘（U 盘）或启动光驱（ISO 启动盘），供连接的主机读写或引导系统。
class DiskScreen extends StatefulWidget {
  const DiskScreen({super.key});

  @override
  State<DiskScreen> createState() => _DiskScreenState();
}

class _DiskScreenState extends State<DiskScreen> {
  /// 虚拟闪存盘（U 盘）启用与挂载状态
  bool _flash = false;

  /// 虚拟引导光驱（CD-ROM / ISO）启用与挂载状态
  bool _boot = false;

  /// 当前选中的模式选项卡索引：
  /// - 0: 虚拟闪存盘 (Virtual Flash Drive)
  /// - 1: 虚拟启动盘 (Boot Drive)
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // 获取本地化文本对象
    final l = context.l10n;

    return DeviceScaffold(
      title: l.text('virtualDisks'), // 页面标题：“虚拟磁盘”
      // 导航栏右侧快速“添加镜像/新建”操作按钮
      action: IconButton(
        onPressed: () {
          // 可在此处触发文件选择器导入 ISO 或 IMG 镜像
        },
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 磁盘工作模式选择卡片（分段切换按钮）
          DeviceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.text('diskMode'), // “磁盘模式”
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      label: Text(l.text('virtualFlash')), // “虚拟闪存盘”
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text(l.text('bootDrive')), // “启动光驱”
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (value) =>
                      setState(() => _tab = value.first),
                ),
              ],
            ),
          ),

          // 2. 当前选中模式下的活动设备状态卡片
          DeviceSection(l.text('activeDevices')), // “活动设备”
          DeviceStatusCard(
            // 根据当前选中的分段展示不同的图标与文本
            icon: _tab == 0 ? Icons.storage_rounded : Icons.album_rounded,
            title: _tab == 0
                ? l.text('virtualFlash') // “虚拟闪存盘”
                : l.text('virtualBootDrive'), // “虚拟启动盘”
            detail: _tab == 0 ? l.text('mounted') : l.text('noIso'),
            enabled: _tab == 0 ? _flash : _boot,
            onChanged: (value) => setState(() {
              if (_tab == 0) {
                _flash = value;
              } else {
                _boot = value;
              }
            }),
          ),

          // 3. 存储与镜像管理操作项
          DeviceSection(l.text('storageOptions')), // “存储选项”
          DeviceCard(
            child: Column(
              children: [
                // 导入外部镜像文件选项
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(l.text('addImage')), // “添加镜像文件”
                  subtitle: Text(l.text('imageFormats')), // 支持格式提示（ISO, IMG 等）
                  onTap: () {
                    // 浏览并加载本地镜像文件
                  },
                ),
                const Divider(height: 1),
                // 新建空虚拟磁盘镜像选项
                ListTile(
                  leading: const Icon(Icons.add_box_rounded),
                  title: Text(l.text('createImage')), // “创建空镜像”
                  subtitle: Text(l.text('formatSize')), // 容量大小与格式化提示
                  onTap: () {
                    // 打开创建指定大小虚拟磁盘的对话框
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
