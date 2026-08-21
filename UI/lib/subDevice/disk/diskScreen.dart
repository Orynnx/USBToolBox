// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../devicePage.dart';

/// 虚拟磁盘与存储设备（USB 大容量存储 Mass Storage）配置页面
///
/// 支持将移动设备模拟为标准 USB 闪存盘（U 盘）或启动光驱（ISO 启动盘），供连接的主机读写或引导系统。
class DiskScreen extends StatelessWidget {
  const DiskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyDeviceScreen(title: context.l10n.text('virtualDisks'));
  }
}
