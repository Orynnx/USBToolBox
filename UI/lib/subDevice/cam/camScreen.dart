// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../storage/services/document_picker_service.dart';
import '../../uvc/services/uvc_service.dart';
import '../devicePage.dart';
import 'components.dart';

/// USB UVC 虚拟摄像头配置与视频推流控制页面
class CamScreen extends StatefulWidget {
  const CamScreen({super.key});

  @override
  State<CamScreen> createState() => _CamScreenState();
}

class _CamScreenState extends State<CamScreen> {
  final _service = UvcService();

  /// 摄像头能力总开关
  bool _capabilityEnabled = true;

  /// 当前选中的视频源 (后置 / 前置 / 屏幕 / 视频文件)
  UvcSource _source = UvcSource.back;

  /// 本地 MP4 视频文件
  DocumentSelection? _video;

  /// 当前 UVC 视频流状态
  UvcStreamStatus _status = const UvcStreamStatus.stopped();

  /// 是否处于异步阻塞切换中
  bool _busy = false;

  /// 错误信息
  String? _error;

  /// 相机顺时针旋转角度 (0, 90, 180, 270)
  int _rotationAngle = 0;

  /// 当前选中的输出分辨率与刷新率规格
  UvcProfile _selectedProfile = UvcProfile.defaultProfiles[1]; // 1920x1080 @ 30fps

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await _service.refresh();
    if (mounted) {
      setState(() {
        _status = status;
        if (status.running) {
          _capabilityEnabled = true;
          if (status.source != null) {
            _source = status.source!;
          }
        }
      });
    }
  }

  /// 选择本地 MP4 视频文件
  Future<void> _pickVideo() async {
    final video = await DocumentPickerService.pickVideo();
    if (video == null || !mounted) return;
    if (!video.name.toLowerCase().endsWith('.mp4')) {
      setState(() => _error = context.l10n.text('mp4FileRequired'));
      return;
    }
    setState(() => _video = video);
  }

  /// 顺时针旋转相机 90°
  void _rotate90() {
    setState(() {
      _rotationAngle = (_rotationAngle + 90) % 360;
    });
  }

  /// 切换推流传输状态
  Future<void> _toggleStreaming() async {
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

  /// 友好错误提示转换
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DeviceScaffold(
      title: l10n.text('usbWebcam'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. USB 摄像头能力总开关卡片 (支持阻塞)
          UvcCapabilityCard(
            enabled: _capabilityEnabled,
            busy: _busy,
            onChanged: (val) {
              setState(() {
                _capabilityEnabled = val;
                if (!val && _status.running) {
                  _toggleStreaming();
                }
              });
            },
          ),
          const SizedBox(height: 14),

          // 2. 视频源选择器 (多选一：后置、前置、屏幕、视频文件)
          if (_capabilityEnabled) ...[
            CamSourceSelector(
              selectedSource: _source,
              enabled: !_busy && !_status.running,
              onSourceChanged: (value) => setState(() => _source = value),
            ),
            if (_source == UvcSource.file) ...[
              const SizedBox(height: 12),
              CamFileSourceSection(
                fileName: _video?.name,
                onPickFile: _pickVideo,
                enabled: !_busy && !_status.running,
              ),
            ],
            const SizedBox(height: 14),

            // 3. 启用传输卡片 (支持阻塞置灰的原生 Switch)
            UvcStreamCard(
              running: _status.running,
              busy: _busy,
              capabilityEnabled: _capabilityEnabled,
              error: _error,
              onToggle: _toggleStreaming,
            ),

            // 4. 启用传输开关开启后出现的配置菜单 (旋转相机 + 单选分辨率与刷新率列表)
            if (_status.running) ...[
              const SizedBox(height: 14),
              CamRotateCard(
                rotationAngle: _rotationAngle,
                onRotate: _rotate90,
              ),
              DeviceSection(l10n.text('supportedResolutionsFps')),
              CamResolutionListCard(
                profiles: UvcProfile.defaultProfiles,
                selectedProfileId: _selectedProfile.id,
                onSelectProfile: (profile) {
                  setState(() {
                    _selectedProfile = profile;
                  });
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
