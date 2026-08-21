import 'package:flutter/services.dart';

import '../../core/core_client.dart';
import '../../core/core_deployment_service.dart';
import '../../core/root_shell_service.dart';
import '../../storage/services/disk_storage_service.dart';
import '../../usb/usb_session_service.dart';
import '../models/uvc_configuration.dart';
import 'system_webcam_guard.dart';

enum UvcSource { back, front, screen, file }

class UvcStreamStatus {
  const UvcStreamStatus({
    required this.running,
    this.source,
    this.width = 1280,
    this.height = 720,
    this.fps = 30,
    this.format = 'mjpeg',
  });

  final bool running;
  final UvcSource? source;
  final int width;
  final int height;
  final int fps;
  final String format;

  const UvcStreamStatus.stopped() : this(running: false);

  factory UvcStreamStatus.fromMap(Map<Object?, Object?> value) {
    final sourceName = value['source'] as String?;
    return UvcStreamStatus(
      running: value['running'] as bool? ?? false,
      source: UvcSource.values.where((it) => it.name == sourceName).firstOrNull,
      width: (value['width'] as num?)?.toInt() ?? 1280,
      height: (value['height'] as num?)?.toInt() ?? 720,
      fps: (value['fps'] as num?)?.toInt() ?? 30,
      format: value['format'] as String? ?? 'mjpeg',
    );
  }
}

/// Coordinates the UVC declaration with Core before opening the root producer.
/// The native producer only writes the documented uvc.sock data protocol.
class UvcService {
  UvcService({
    RootShellService? root,
    CoreClient? client,
    CoreDeploymentService? deployment,
    UsbSessionService? session,
    DiskStorageService? disks,
  })  : _root = root ?? RootShellService(),
        _disks = disks ?? DiskStorageService() {
    _client = client ?? CoreClient(_root);
    _deployment = deployment ?? CoreDeploymentService(_root, _client);
    _session = session ?? UsbSessionService(_root, _deployment, _client);
    _systemWebcam = SystemWebcamGuard(_root);
  }

  static const _channel = MethodChannel('org.orynnx.hyperusb/uvc');
  final RootShellService _root;
  late final CoreClient _client;
  late final CoreDeploymentService _deployment;
  late final UsbSessionService _session;
  late final SystemWebcamGuard _systemWebcam;
  final DiskStorageService _disks;
  UvcStreamStatus _status = const UvcStreamStatus.stopped();
  UvcStreamStatus get status => _status;

  Future<bool> requestCameraPermission() async =>
      await _channel.invokeMethod<bool>('requestCameraPermission') ?? false;

  Future<bool> requestScreenCapture() async =>
      await _channel.invokeMethod<bool>('requestScreenCapture') ?? false;

  Future<UvcStreamStatus> start(UvcSource source, {String? videoUri}) async {
    if ((source == UvcSource.back || source == UvcSource.front) &&
        !await requestCameraPermission()) {
      throw StateError('camera_permission_denied');
    }
    if (source == UvcSource.screen && !await requestScreenCapture()) {
      throw StateError('screen_capture_permission_denied');
    }
    if (source == UvcSource.file && (videoUri == null || videoUri.isEmpty)) {
      throw StateError('video_file_required');
    }
    final capability = (source == UvcSource.back || source == UvcSource.front)
        ? await _cameraCapability(source)
        : const UvcStreamStatus(running: false);
    // All sources use MJPEG. Uncompressed 1280x720@30 YUYV exceeds reliable
    // USB 2.0 throughput and can diverge from the negotiated descriptor.
    final configuration = UvcConfiguration(
      format: 'mjpeg',
      width: capability.width,
      height: capability.height,
      fps: capability.fps,
    );
    await _systemWebcam.acquire();
    try {
      await _deployment.ensureReady();
      await _session.apply(await _disks.load(), uvc: configuration);
      final payload = <String, dynamic>{
        'source': source.name,
        'width': capability.width,
        'height': capability.height,
        'fps': capability.fps,
      };
      if (videoUri != null) payload['videoUri'] = videoUri;
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'start',
        payload,
      );
      if (raw == null) throw StateError('uvc_producer_did_not_start');
      _status = UvcStreamStatus.fromMap(raw);
      return _status;
    } catch (_) {
      try {
        await _session.apply(await _disks.load(), uvcEnabled: false);
      } finally {
        await _systemWebcam.release();
      }
      rethrow;
    }
  }

  Future<UvcStreamStatus> _cameraCapability(UvcSource source) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'cameraCapability',
      {'source': source.name},
    );
    if (raw == null) throw StateError('camera_capability_unavailable');
    return UvcStreamStatus.fromMap(raw);
  }

  Future<void> stop() async {
    // The producer owns Android resources, but it must never prevent Core from
    // removing the UVC function/runtime. This keeps shutdown safe after a
    // partial camera, decoder, or MediaProjection failure.
    Object? producerFailure;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (error) {
      producerFailure = error;
    }
    var coreStopped = false;
    try {
      await _session.apply(await _disks.load(), uvcEnabled: false);
      coreStopped = true;
    } catch (coreFailure) {
      // Do not claim the UVC switch is off if Core could not remove the USB
      // function. The caller keeps the previous state and exposes this error.
      Error.throwWithStackTrace(coreFailure, StackTrace.current);
    }
    if (coreStopped) await _systemWebcam.release();
    _status = const UvcStreamStatus.stopped();
    if (producerFailure != null) {
      Error.throwWithStackTrace(producerFailure, StackTrace.current);
    }
  }

  Future<UvcStreamStatus> refresh() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('status');
    if (raw != null) _status = UvcStreamStatus.fromMap(raw);
    return _status;
  }
}
