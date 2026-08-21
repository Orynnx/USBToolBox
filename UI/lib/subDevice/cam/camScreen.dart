// ignore_for_file: file_names

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../storage/services/document_picker_service.dart';
import '../../uvc/services/uvc_service.dart';
import '../devicePage.dart';
import 'components.dart';

/// UVC page. Android captures/decodes frames and sends Core's uvc.sock
/// protocol; this widget contains no simulated stream state.
class CamScreen extends StatefulWidget {
  const CamScreen({super.key});

  @override
  State<CamScreen> createState() => _CamScreenState();
}

class _CamScreenState extends State<CamScreen> {
  final _service = UvcService();
  UvcSource _source = UvcSource.back;
  DocumentSelection? _video;
  UvcStreamStatus _status = const UvcStreamStatus.stopped();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await _service.refresh();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _pickVideo() async {
    final video = await DocumentPickerService.pickVideo();
    if (video == null || !mounted) return;
    if (!video.name.toLowerCase().endsWith('.mp4')) {
      setState(() => _error = context.l10n.text('mp4FileRequired'));
      return;
    }
    setState(() => _video = video);
  }

  Future<void> _toggle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_status.running) {
        await _service.stop();
        _status = const UvcStreamStatus.stopped();
      } else {
        _status = await _service.start(_source, videoUri: _video?.uri);
      }
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final value = '$error';
    if (value.contains('camera_permission_denied')) {
      return context.l10n.text('cameraPermissionDenied');
    }
    if (value.contains('screen_capture_permission_denied')) {
      return context.l10n.text('screenPermissionDenied');
    }
    if (value.contains('video_file_required')) {
      return context.l10n.text('videoFileRequired');
    }
    return value;
  }

  @override
  Widget build(BuildContext context) => DeviceScaffold(
    title: context.l10n.text('usbWebcam'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UvcPowerCard(
          running: _status.running,
          busy: _busy,
          error: _error,
          onToggle: _toggle,
        ),
        const SizedBox(height: 16),
        CamSourceSelector(
          selectedSource: _source,
          enabled: !_busy && !_status.running,
          onSourceChanged: (value) => setState(() => _source = value),
        ),
        if (_source == UvcSource.file) ...[
          const SizedBox(height: 16),
          CamFileSourceSection(
            fileName: _video?.name,
            onPickFile: _pickVideo,
            enabled: !_busy && !_status.running,
          ),
        ],
        const SizedBox(height: 16),
        CamStreamStatusCard(
          status: _status,
        ),
      ],
    ),
  );
}
