// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../devicePage.dart';
import 'components.dart';

/// 虚拟磁盘与存储设备（USB 大容量存储 Mass Storage）配置页面
class DiskScreen extends StatefulWidget {
  const DiskScreen({super.key});

  @override
  State<DiskScreen> createState() => _DiskScreenState();
}

class _DiskScreenState extends State<DiskScreen> {
  // 模拟磁盘设备列表
  final List<DiskDeviceItem> _disks = [
    DiskDeviceItem(
      id: 'disk_1',
      name: 'Ventoy MultiBoot',
      path: '/sdcard/images/ventoy.img',
      size: '64.0 GB',
      fileSystem: 'exFAT',
      type: DiskDeviceType.usb,
      state: DiskDeviceState.running,
      accessMode: DiskAccessMode.readWrite,
      enableFua: true,
      removableMedia: true,
    ),
    DiskDeviceItem(
      id: 'disk_2',
      name: 'Windows 11 Setup ISO',
      path: '/sdcard/images/Win11_24H2.iso',
      size: '5.8 GB',
      fileSystem: 'ISO',
      type: DiskDeviceType.cdrom,
      state: DiskDeviceState.stopped,
      accessMode: DiskAccessMode.readOnly,
      enableFua: false,
      removableMedia: true,
    ),
    DiskDeviceItem(
      id: 'disk_3',
      name: 'Arch Linux Install Disk',
      path: '/sdcard/images/archlinux-x86_64.img',
      size: '1.2 GB',
      fileSystem: 'FAT32',
      type: DiskDeviceType.usb,
      state: DiskDeviceState.stopped,
      accessMode: DiskAccessMode.readOnly,
      enableFua: false,
      removableMedia: true,
    ),
    DiskDeviceItem(
      id: 'disk_error_demo',
      name: '损坏的系统镜像',
      path: '/sdcard/images/broken_backup.img',
      size: '4.0 GB',
      fileSystem: 'RAW',
      type: DiskDeviceType.usb,
      state: DiskDeviceState.stopped,
      accessMode: DiskAccessMode.readOnly,
      enableFua: false,
      removableMedia: true,
    ),
  ];

  int get _mountedCount =>
      _disks.where((d) => d.state == DiskDeviceState.running).length;

  Future<void> _toggleDiskState(DiskDeviceItem disk) async {
    final originalState = disk.state;
    // 切换为操作中 Loading 状态
    setState(() {
      disk.state = DiskDeviceState.operating;
    });

    // 模拟底层异步挂载/卸载驱动耗时
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    // 模拟镜像损坏或路径异常错误处理逻辑
    if (disk.id == 'disk_error_demo' ||
        disk.path.contains('broken') ||
        disk.path.contains('corrupted')) {
      setState(() {
        disk.state = DiskDeviceState.stopped;
      });

      final DiskErrorReason reason = disk.path.contains('broken')
          ? DiskErrorReason.corruptedImage
          : disk.path.contains('notfound')
              ? DiskErrorReason.fileNotFound
              : DiskErrorReason.internalError;

      DiskErrorBottomSheet.show(
        context,
        item: disk,
        reason: reason,
        onEdit: () => _openEditSheet(disk),
        onDelete: () => _deleteDisk(disk),
      );
      return;
    }

    setState(() {
      disk.state = originalState == DiskDeviceState.running
          ? DiskDeviceState.stopped
          : DiskDeviceState.running;
    });
  }

  Future<void> _stopAllMountedDisks() async {
    final mountedDisks =
        _disks.where((d) => d.state == DiskDeviceState.running).toList();
    if (mountedDisks.isEmpty) return;

    setState(() {
      for (final d in mountedDisks) {
        d.state = DiskDeviceState.operating;
      }
    });

    await Future.delayed(const Duration(milliseconds: 750));
    if (!mounted) return;

    setState(() {
      for (final d in mountedDisks) {
        d.state = DiskDeviceState.stopped;
      }
    });
  }

  void _openEditSheet(DiskDeviceItem disk) {
    DiskEditBottomSheet.show(
      context,
      item: disk,
      onSave: (updated) {
        setState(() {
          final index = _disks.indexWhere((d) => d.id == updated.id);
          if (index != -1) {
            _disks[index] = updated;
          }
        });
      },
    );
  }

  void _deleteDisk(DiskDeviceItem disk) {
    setState(() {
      _disks.removeWhere((d) => d.id == disk.id);
    });
  }

  void _openAddNewSheet() {
    final newItem = DiskDeviceItem(
      id: 'disk_${DateTime.now().millisecondsSinceEpoch}',
      name: '',
      path: '/sdcard/images/new_drive.img',
      size: '16.0 GB',
      fileSystem: 'FAT32',
      type: DiskDeviceType.usb,
      state: DiskDeviceState.stopped,
      accessMode: DiskAccessMode.readWrite,
      enableFua: false,
      removableMedia: true,
    );

    DiskEditBottomSheet.show(
      context,
      item: newItem,
      onSave: (created) {
        setState(() {
          _disks.add(created);
        });
      },
    );
  }

  void _openCreateSheet() {
    DiskCreateBottomSheet.show(
      context,
      onCreate: (created) {
        setState(() {
          _disks.add(created);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DeviceScaffold(
      title: l10n.text('virtualDisks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 顶部系统级功能状态栏（Section Status Header）
          DiskStatusHeader(
            mountedCount: _mountedCount,
            onMasterAction: _stopAllMountedDisks,
          ),
          const SizedBox(height: 14),

          // 2. 磁盘设备列表
          ..._disks.map((disk) => DiskDeviceCard(
                key: ValueKey(disk.id),
                item: disk,
                onEdit: () => _openEditSheet(disk),
                onToggleState: () => _toggleDiskState(disk),
                onDelete: () => _deleteDisk(disk),
              )),

          const SizedBox(height: 10),

          // 3. 导入镜像 / 新建镜像 操作按钮（一行各占一半宽度）
          DiskActionButtons(
            onImport: _openAddNewSheet,
            onCreate: _openCreateSheet,
          ),
        ],
      ),
    );
  }
}
