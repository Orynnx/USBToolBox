// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'dart:async';
import '../../l10n/app_localizations.dart';
import '../../serial/models/serialMessage.dart';
import '../../serial/models/serialMode.dart';
import '../../serial/services/serialService.dart';
import '../../theme/app_theme.dart';
import '../devicePage.dart';
import 'widgets/serialModeSelector.dart';
import 'widgets/serialTerminal.dart';

class SerialScreen extends StatefulWidget {
  const SerialScreen({super.key});

  @override
  State<SerialScreen> createState() => _SerialScreenState();
}

class _SerialScreenState extends State<SerialScreen> {
  final _service = SerialService.instance;
  SerialServiceStatus _status = SerialService.instance.currentStatus;
  List<SerialMessage> _messages = SerialService.instance.currentMessages;
  late final StreamSubscription<SerialServiceStatus> _statusSubscription;
  late final StreamSubscription<List<SerialMessage>> _messageSubscription;
  bool _processing = false;
  @override
  void initState() {
    super.initState();
    _statusSubscription = _service.status.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _messageSubscription = _service.messages.listen((messages) {
      if (mounted) setState(() => _messages = messages);
    });
    _service.initialize().catchError((_) {
      // A mode transition reports its own actionable error. Startup remains
      // non-blocking so an inactive CDC function can still be enabled by User.
    });
  }

  @override
  void dispose() {
    _statusSubscription.cancel();
    _messageSubscription.cancel();
    super.dispose();
  }

  Future<void> _setMode(SerialMode mode) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await _service.setMode(mode);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.text('serialSwitchFailed')}: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _send(String text) async {
    try {
      await _service.send(text);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.text('serialSendFailed')}: $error'),
          ),
        );
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .48;
    return DeviceScaffold(
      title: context.l10n.text('usbSerial'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SerialModeSelector(
            current: _status.mode,
            processing: _processing,
            onChanged: _setMode,
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: appThemeManager.disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: SerialTerminal(
              key: ValueKey(_status.mode),
              messages: _messages,
              inputEnabled: _status.ready && !_processing,
              showShellWarning: _status.mode == SerialMode.shell,
              onSubmit: _send,
              height: height,
            ),
          ),
        ],
      ),
    );
  }
}
