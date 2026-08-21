import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../serial/models/serialMode.dart';

class SerialModeSelector extends StatelessWidget {
  const SerialModeSelector({
    super.key,
    required this.current,
    required this.processing,
    required this.onChanged,
  });
  final SerialMode current;
  final bool processing;
  final ValueChanged<SerialMode> onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<SerialMode>(
    segments: [
      ButtonSegment(
        value: SerialMode.off,
        label: Text(context.l10n.text('serialOff')),
      ),
      ButtonSegment(
        value: SerialMode.user,
        label: Text(context.l10n.text('serialUser')),
      ),
      ButtonSegment(
        value: SerialMode.shell,
        label: Text(context.l10n.text('serialShell')),
      ),
    ],
    selected: {current},
    showSelectedIcon: false,
    onSelectionChanged: processing
        ? null
        : (selection) => onChanged(selection.first),
  );
}
