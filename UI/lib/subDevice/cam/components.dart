// ignore_for_file: file_names

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../uvc/services/uvc_service.dart';

class CamSourceSelector extends StatelessWidget {
  const CamSourceSelector({
    super.key,
    required this.selectedSource,
    required this.onSourceChanged,
    required this.enabled,
  });

  final UvcSource selectedSource;
  final ValueChanged<UvcSource> onSourceChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SegmentedButton<UvcSource>(
    showSelectedIcon: false,
    segments: [
      ButtonSegment(value: UvcSource.back, label: Text(context.l10n.text('back'))),
      ButtonSegment(value: UvcSource.front, label: Text(context.l10n.text('front'))),
      ButtonSegment(value: UvcSource.screen, label: Text(context.l10n.text('screen'))),
      ButtonSegment(value: UvcSource.file, label: Text(context.l10n.text('videoFile'))),
    ],
    selected: {selectedSource},
    onSelectionChanged: enabled
        ? (value) => onSourceChanged(value.first)
        : null,
  );
}

/// The single UVC control point: off, active, and an uninterruptible working
/// state while Core and the Producer are being changed together.
class UvcPowerCard extends StatelessWidget {
  const UvcPowerCard({
    super.key,
    required this.running,
    required this.busy,
    required this.onToggle,
    this.error,
  });

  final bool running;
  final bool busy;
  final VoidCallback onToggle;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final stateText = busy
        ? context.l10n.text('uvcSwitching')
        : running
        ? context.l10n.text('uvcStreaming')
        : context.l10n.text('uvcStopped');
    return Card(
      elevation: 0,
      color: running ? colors.primaryContainer : colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.videocam_rounded,
                  color: running ? colors.onPrimaryContainer : colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.text('usbWebcam'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stateText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: running
                              ? colors.onPrimaryContainer.withValues(alpha: .72)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _UvcThreeStateButton(
                  running: running,
                  busy: busy,
                  onToggle: onToggle,
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _UvcThreeStateButton extends StatelessWidget {
  const _UvcThreeStateButton({
    required this.running,
    required this.busy,
    required this.onToggle,
  });

  final bool running;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = running ? colors.onPrimary : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      enabled: !busy,
      label: context.l10n.text(busy ? 'uvcSwitching' : running ? 'stopUvc' : 'startUvc'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 54,
        height: 32,
        decoration: BoxDecoration(
          color: running ? colors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: busy ? null : onToggle,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    )
                  : Icon(
                      running ? Icons.power_settings_new_rounded : Icons.power_off_rounded,
                      size: 19,
                      color: foreground,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class CamFileSourceSection extends StatelessWidget {
  const CamFileSourceSection({
    super.key,
    required this.fileName,
    required this.onPickFile,
    required this.enabled,
  });

  final String? fileName;
  final VoidCallback onPickFile;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: ListTile(
        leading: Icon(Icons.movie_outlined, color: colors.primary),
        title: Text(fileName ?? context.l10n.text('noVideoFileSelected')),
        subtitle: Text(context.l10n.text('videoFileDescription')),
        trailing: IconButton(
          tooltip: context.l10n.text('selectFile'),
          onPressed: enabled ? onPickFile : null,
          icon: const Icon(Icons.folder_open_rounded),
        ),
      ),
    );
  }
}

class CamStreamStatusCard extends StatelessWidget {
  const CamStreamStatusCard({
    super.key,
    required this.status,
  });

  final UvcStreamStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final online = status.running;
    return Card(
      elevation: 0,
      color: online ? colors.primaryContainer : colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.text('realtimeStatus'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            _Metric(
              icon: Icons.high_quality_outlined,
              label: context.l10n.text('outputSpec'),
              value: '${status.width} × ${status.height} · ${status.fps} FPS · ${status.format.toUpperCase()}',
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(child: Text(label)),
      Text(value, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}
