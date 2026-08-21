// ignore_for_file: file_names
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../devicePage.dart';

class HidScreen extends StatelessWidget {
  const HidScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      EmptyDeviceScreen(title: context.l10n.text('virtualHid'));
}
