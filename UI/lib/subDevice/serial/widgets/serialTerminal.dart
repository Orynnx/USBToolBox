import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../serial/models/serialMessage.dart';
import 'serialInputBar.dart';

class SerialTerminal extends StatefulWidget {
  const SerialTerminal({
    super.key,
    required this.messages,
    required this.inputEnabled,
    required this.showShellWarning,
    required this.onSubmit,
    required this.height,
  });
  final List<SerialMessage> messages;
  final bool inputEnabled;
  final bool showShellWarning;
  final Future<void> Function(String text) onSubmit;
  final double height;
  @override
  State<SerialTerminal> createState() => _SerialTerminalState();
}

class _SerialTerminalState extends State<SerialTerminal> {
  final _scroll = ScrollController();
  bool _follow = true;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackScroll);
  }

  @override
  void didUpdateWidget(covariant SerialTerminal old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length && _follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _trackScroll() {
    if (!_scroll.hasClients) return;
    _follow = _scroll.position.extentAfter < 36;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: const Color(0xff0d0d0d),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: widget.messages.length,
                itemBuilder: (_, index) {
                  final message = widget.messages[index];
                  final time = message.timestamp;
                  final stamp =
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                  final direction = message.direction == SerialDirection.rx
                      ? 'RX'
                      : 'TX';
                  return Text(
                    '[$stamp] $direction ${message.message}',
                    style: const TextStyle(
                      color: Color(0xffe8e8e8),
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  );
                },
              ),
            ),
            SerialInputBar(
              enabled: widget.inputEnabled,
              onSubmit: widget.onSubmit,
            ),
            if (widget.showShellWarning) const _ShellExposureWarning(),
          ],
        ),
      ),
    ),
  );
}

class _ShellExposureWarning extends StatelessWidget {
  const _ShellExposureWarning();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.errorContainer,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.warning_amber_rounded, color: colors.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.text('serialShellWarningTitle'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.text('serialShellWarningBody'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
