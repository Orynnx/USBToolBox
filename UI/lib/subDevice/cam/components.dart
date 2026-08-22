// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../uvc/services/uvc_service.dart';
import '../devicePage.dart';

/// 相机输出能力配置项 (分辨率与刷新率)
class UvcProfile {
  const UvcProfile({
    required this.width,
    required this.height,
    required this.fps,
    required this.label,
  });

  final int width;
  final int height;
  final int fps;
  final String label;

  String get id => '${width}x$height@$fps';
  String get specText => '$width × $height';
  String get rateText => '$fps FPS · $label';

  /// 内置标准相机输出能力预设列表
  static const List<UvcProfile> defaultProfiles = [
    UvcProfile(width: 1920, height: 1080, fps: 60, label: 'FHD 1080p'),
    UvcProfile(width: 1920, height: 1080, fps: 30, label: 'FHD 1080p'),
    UvcProfile(width: 1280, height: 720, fps: 60, label: 'HD 720p'),
    UvcProfile(width: 1280, height: 720, fps: 30, label: 'HD 720p'),
    UvcProfile(width: 640, height: 480, fps: 30, label: 'VGA 480p'),
  ];
}

/// 1. USB 摄像头能力总开关卡片
class UvcCapabilityCard extends StatelessWidget {
  const UvcCapabilityCard({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  /// 摄像头能力是否开启
  final bool enabled;

  /// 是否处于阻塞操作状态中
  final bool busy;

  /// 切换回调
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return DeviceCard(
      child: Row(
        children: [
          // 左侧摄像头图标徽标
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: enabled
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.videocam_rounded,
              color: enabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          // 中间标题与能力描述
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.text('usbWebcam'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.text('uvcCapabilityDesc'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧支持阻塞置灰的原生 Switch
          Switch(
            value: enabled,
            onChanged: busy ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

/// 2. 视频源选择器（多选一：后置、前置、屏幕、视频文件）
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
          ButtonSegment(
            value: UvcSource.back,
            label: Text(context.l10n.text('back')),
          ),
          ButtonSegment(
            value: UvcSource.front,
            label: Text(context.l10n.text('front')),
          ),
          ButtonSegment(
            value: UvcSource.screen,
            label: Text(context.l10n.text('screen')),
          ),
          ButtonSegment(
            value: UvcSource.file,
            label: Text(context.l10n.text('videoFile')),
          ),
        ],
        selected: {selectedSource},
        onSelectionChanged:
            enabled ? (value) => onSourceChanged(value.first) : null,
      );
}

/// 3. 本地 MP4 视频文件选择组件
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

/// 4. 启用传输控制卡片（支持阻塞 Switch 开关）
class UvcStreamCard extends StatelessWidget {
  const UvcStreamCard({
    super.key,
    required this.running,
    required this.busy,
    required this.capabilityEnabled,
    required this.onToggle,
    this.error,
  });

  /// 是否正在推流传输
  final bool running;

  /// 是否处于阻塞操作状态中
  final bool busy;

  /// 能力总开关是否已启用
  final bool capabilityEnabled;

  /// 启停传输切换回调
  final VoidCallback onToggle;

  /// 错误提示
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
                // 左侧传输图标
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: running
                        ? colors.onPrimaryContainer.withValues(alpha: 0.12)
                        : colors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.sensors_rounded,
                    color: running
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                // 中间标题与传输状态描述
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.text('enableStreaming'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stateText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: running
                              ? colors.onPrimaryContainer.withValues(alpha: .75)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 右侧原生 Android Switch 开关（阻塞或未开启能力时置灰）
                Switch(
                  value: running,
                  onChanged: (!capabilityEnabled || busy) ? null : (_) => onToggle(),
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

/// 5. 旋转相机控制卡片 (顺时针旋转 90°)
class CamRotateCard extends StatelessWidget {
  const CamRotateCard({
    super.key,
    required this.rotationAngle,
    required this.onRotate,
  });

  /// 当前旋转角度 (0, 90, 180, 270)
  final int rotationAngle;

  /// 点击顺时针旋转回调
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return DeviceCard(
      child: Row(
        children: [
          // 左侧旋转图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.screen_rotation_rounded,
              color: colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // 标题与说明
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.text('rotateCamera'),
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.text('rotateCameraDesc'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 旋转操作按钮 (展示当前角度并支持单点顺时针旋转 90°)
          FilledButton.tonalIcon(
            onPressed: onRotate,
            icon: const Icon(Icons.rotate_right_rounded, size: 18),
            label: Text('$rotationAngle°'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 6. 相机输出能力列表展示卡片 (支持的分辨率和刷新率，仅能单选)
class CamResolutionListCard extends StatelessWidget {
  const CamResolutionListCard({
    super.key,
    required this.profiles,
    required this.selectedProfileId,
    required this.onSelectProfile,
  });

  /// 支持的能力规格列表
  final List<UvcProfile> profiles;

  /// 当前选中的规格 ID
  final String selectedProfileId;

  /// 单选切换回调
  final ValueChanged<UvcProfile> onSelectProfile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DeviceCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < profiles.length; i++) ...[
            _ProfileItemTile(
              profile: profiles[i],
              isSelected: profiles[i].id == selectedProfileId,
              onTap: () => onSelectProfile(profiles[i]),
            ),
            if (i < profiles.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileItemTile extends StatelessWidget {
  const _ProfileItemTile({
    required this.profile,
    required this.isSelected,
    required this.onTap,
  });

  final UvcProfile profile;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: onTap,
      leading: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: isSelected ? 6.5 : 2,
          ),
        ),
      ),
      title: Text(
        profile.specText,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        profile.rateText,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isSelected
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ACTIVE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            )
          : null,
    );
  }
}
