// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// USB Core 服务管理页面
class CoreSettingsScreen extends StatelessWidget {
  const CoreSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('usbCoreSettings')),
      ),
      body: const SizedBox.shrink(),
    );
  }
}
