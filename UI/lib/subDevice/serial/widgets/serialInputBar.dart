// ignore_for_file: file_names
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

class SerialInputBar extends StatefulWidget {
  const SerialInputBar({
    super.key,
    required this.enabled,
    required this.onSubmit,
  });
  final bool enabled;
  final Future<void> Function(String text) onSubmit;
  @override
  State<SerialInputBar> createState() => _SerialInputBarState();
}

class _SerialInputBarState extends State<SerialInputBar> {
  final _controller = TextEditingController();
  bool _sending = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text;
    if (!widget.enabled || _sending || text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSubmit(text);
      _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_sending;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xff303030))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(
                color: Color(0xfff1f1f1),
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: context.l10n.text('serialInputHint'),
                hintStyle: const TextStyle(color: Color(0xff8d8d8d)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              ),
              onSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            onPressed: enabled && _controller.text.trim().isNotEmpty
                ? _submit
                : null,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            color: const Color(0xfff1f1f1),
          ),
        ],
      ),
    );
  }
}
