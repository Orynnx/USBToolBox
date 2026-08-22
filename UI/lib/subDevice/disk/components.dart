// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../storage/services/document_picker_service.dart';

/// 磁盘设备类型
enum DiskDeviceType { usb, cdrom }

/// 磁盘设备运行状态
enum DiskDeviceState { stopped, operating, running }

/// 磁盘访问模式
enum DiskAccessMode { readOnly, readWrite }

/// 磁盘启用失败/错误原因
enum DiskErrorReason { corruptedImage, fileNotFound, internalError }

/// 虚拟磁盘数据模型
class DiskDeviceItem {
  final String id;
  String name;
  String path;
  String size;
  String fileSystem;
  DiskDeviceType type;
  DiskDeviceState state;
  DiskAccessMode accessMode;
  bool enableFua;
  bool removableMedia;
  String? treeUri;
  String? sourceUri;
  int? sourceSize;
  String? documentUri;

  DiskDeviceItem({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.fileSystem,
    this.type = DiskDeviceType.usb,
    this.state = DiskDeviceState.stopped,
    this.accessMode = DiskAccessMode.readWrite,
    this.enableFua = false,
    this.removableMedia = true,
    this.treeUri,
    this.sourceUri,
    this.sourceSize,
    this.documentUri,
  });

  bool get isImg => path.toLowerCase().endsWith('.img');
  bool get isIso => path.toLowerCase().endsWith('.iso');

  DiskDeviceItem copyWith({
    String? id,
    String? name,
    String? path,
    String? size,
    String? fileSystem,
    DiskDeviceType? type,
    DiskDeviceState? state,
    DiskAccessMode? accessMode,
    bool? enableFua,
    bool? removableMedia,
    String? treeUri,
    String? sourceUri,
    int? sourceSize,
    String? documentUri,
  }) {
    return DiskDeviceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      size: size ?? this.size,
      fileSystem: fileSystem ?? this.fileSystem,
      type: type ?? this.type,
      state: state ?? this.state,
      accessMode: accessMode ?? this.accessMode,
      enableFua: enableFua ?? this.enableFua,
      removableMedia: removableMedia ?? this.removableMedia,
      treeUri: treeUri ?? this.treeUri,
      sourceUri: sourceUri ?? this.sourceUri,
      sourceSize: sourceSize ?? this.sourceSize,
      documentUri: documentUri ?? this.documentUri,
    );
  }
}

/// 可变操作按钮（克制低饱和 Tonal 色彩，零发光，主次分明）
class DiskActionButton extends StatelessWidget {
  const DiskActionButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.size = 34.0,
    this.borderRadius = 9.0,
  });

  /// 状态：stopped (启动) / operating (操作中) / running (终止)
  final DiskDeviceState state;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 按钮尺寸（正方形宽高）
  final double size;

  /// 圆角大小
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color bgColor;
    final Border? border;
    final Widget iconWidget;

    switch (state) {
      case DiskDeviceState.stopped:
        // 启动）克制 Tonal Green，无游戏感发光
        final greenColor = isDark
            ? const Color(0xff4ade80)
            : const Color(0xff16a34a);
        bgColor = isDark ? const Color(0xff143527) : const Color(0xffdcfce7);
        border = Border.all(
          color: greenColor.withValues(alpha: 0.35),
          width: 1.2,
        );
        iconWidget = Icon(
          Icons.play_arrow_rounded,
          key: const ValueKey('icon_stopped'),
          color: greenColor,
          size: size * 0.62,
        );
        break;

      case DiskDeviceState.operating:
        // 操作中）Tonal Amber / Tertiary
        bgColor = colorScheme.tertiaryContainer;
        border = Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.35),
          width: 1.2,
        );
        iconWidget = SizedBox(
          key: const ValueKey('icon_operating'),
          width: size * 0.46,
          height: size * 0.46,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            valueColor: AlwaysStoppedAnimation<Color>(
              colorScheme.onTertiaryContainer,
            ),
          ),
        );
        break;

      case DiskDeviceState.running:
        // 终止）系统级 errorContainer 背景 + onErrorContainer 图标，收敛饱和度
        bgColor = colorScheme.errorContainer;
        border = Border.all(
          color: colorScheme.error.withValues(alpha: 0.35),
          width: 1.2,
        );
        iconWidget = Container(
          key: const ValueKey('icon_running'),
          width: size * 0.34,
          height: size * 0.34,
          decoration: BoxDecoration(
            color: colorScheme.onErrorContainer,
            borderRadius: BorderRadius.circular(2.0),
          ),
        );
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: state == DiskDeviceState.operating ? null : onPressed,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: iconWidget,
            ),
          ),
        ),
      ),
    );
  }
}

/// 系统设置级 Section Status Header（平铺自然，非粗暴大卡片）
class DiskStatusHeader extends StatelessWidget {
  const DiskStatusHeader({
    super.key,
    required this.mountedCount,
    required this.onMasterAction,
  });

  /// 当前挂载设备数量
  final int mountedCount;

  /// 主控制操作（全部停止）
  final VoidCallback onMasterAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasMounted = mountedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasMounted
              ? colorScheme.primary.withValues(alpha: 0.25)
              : colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasMounted
                            ? const Color(0xff22c55e)
                            : colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${l10n.text('storageDeviceSection')} · ${hasMounted ? l10n.text('storageEnabled') : l10n.text('storageDisabled')}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Text(
                    hasMounted
                        ? l10n
                              .text('devicesSharing')
                              .replaceAll('%d', '$mountedCount')
                        : l10n.text('noDevicesSharing'),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasMounted)
            TextButton(
              onPressed: onMasterAction,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                l10n.text('stop'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 设备描述卡片（高度收紧 ~104dp，Inline Metadata 排版，编辑降级为普通图标）
class DiskDeviceCard extends StatelessWidget {
  const DiskDeviceCard({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onToggleState,
    this.onDelete,
  });

  /// 磁盘设备数据
  final DiskDeviceItem item;

  /// 编辑回调
  final VoidCallback onEdit;

  /// 切换启停状态回调
  final VoidCallback onToggleState;

  /// 删除回调
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRunning = item.state == DiskDeviceState.running;

    // 设备类型图标
    final IconData typeIcon = item.type == DiskDeviceType.cdrom || item.isIso
        ? Icons.album_outlined
        : Icons.usb_rounded;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: isRunning
          ? colorScheme.surfaceContainerHigh
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRunning
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 第一行：类型图标 + 名称与路径
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isRunning
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    typeIcon,
                    color: isRunning
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        item.path,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 第二行：{容量 · 文件系统 · 只读} 靠右对齐 {✎} {[▶]}
            Row(
              children: [
                // Inline Metadata
                Text(
                  item.accessMode == DiskAccessMode.readOnly
                      ? '${item.size} · ${item.fileSystem} · ${l10n.text('readOnly')}'
                      : '${item.size} · ${item.fileSystem}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const Spacer(),

                // 编辑按钮（降级为次级普通无底色 IconButton）
                IconButton(
                  tooltip: l10n.text('edit'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  color: colorScheme.onSurfaceVariant,
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: l10n.text('delete'),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    color: colorScheme.error,
                  ),
                ],
                // 原生 Android Switch 开关（操作中时置灰不可点击）
                Switch(
                  value: isRunning,
                  onChanged: item.state == DiskDeviceState.operating
                      ? null
                      : (_) => onToggleState(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部添加操作按钮组（导入镜像 + 新建镜像，各占一半宽度）
class DiskActionButtons extends StatelessWidget {
  const DiskActionButtons({
    super.key,
    required this.onImport,
    required this.onCreate,
  });

  final VoidCallback onImport;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // 导入镜像（绑定原有导入行为）
        Expanded(
          child: SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: Text(
                l10n.text('importImage'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.28),
                  width: 1.2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // 新建镜像（弹出新建磁盘底栏）
        Expanded(
          child: SizedBox(
            height: 46,
            child: FilledButton.tonalIcon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: Text(
                l10n.text('createImage'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 兼容性别名
typedef DiskAddButton = DiskActionButtons;

/// 磁盘报错底栏组件（扁平化无嵌套）
class DiskErrorBottomSheet extends StatelessWidget {
  const DiskErrorBottomSheet({
    super.key,
    required this.item,
    required this.reason,
    required this.onEdit,
    required this.onDelete,
  });

  final DiskDeviceItem item;
  final DiskErrorReason reason;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 弹出错误底栏静态方法
  static Future<void> show(
    BuildContext context, {
    required DiskDeviceItem item,
    DiskErrorReason reason = DiskErrorReason.corruptedImage,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DiskErrorBottomSheet(
        item: item,
        reason: reason,
        onEdit: () {
          Navigator.of(ctx).pop();
          onEdit();
        },
        onDelete: () {
          Navigator.of(ctx).pop();
          onDelete();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String reasonText;
    switch (reason) {
      case DiskErrorReason.corruptedImage:
        reasonText = l10n.text('reasonCorruptedImage');
        break;
      case DiskErrorReason.fileNotFound:
        reasonText = l10n.text('reasonFileNotFound');
        break;
      case DiskErrorReason.internalError:
        reasonText = l10n.text('reasonInternalError');
        break;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题：无法启用此磁盘
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: colorScheme.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  l10n.text('cannotEnableDisk'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 原因行（平铺展示，无多余嵌套卡片）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.text('errorReason')}：',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  reasonText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 路径信息
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 17,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.path,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 编辑 | 删除 按钮各占一半宽度
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.text('edit')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(l10n.text('delete')),
                  style: FilledButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    backgroundColor: colorScheme.errorContainer.withValues(
                      alpha: 0.65,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 新建磁盘底部菜单
class DiskCreateBottomSheet extends StatefulWidget {
  const DiskCreateBottomSheet({super.key, required this.onCreate});

  final ValueChanged<DiskDeviceItem> onCreate;

  /// 弹出新建磁盘底栏静态工具方法
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<DiskDeviceItem> onCreate,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DiskCreateBottomSheet(onCreate: onCreate),
    );
  }

  @override
  State<DiskCreateBottomSheet> createState() => _DiskCreateBottomSheetState();
}

class _DiskCreateBottomSheetState extends State<DiskCreateBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;
  late final TextEditingController _sizeController;

  static const List<double> _presetGbValues = [
    0.125, // 128MB
    1.0, // 1GB
    8.0, // 8GB
    16.0, // 16GB
    64.0, // 64GB
    128.0, // 128GB
    256.0, // 256GB
  ];

  static const List<String> _presetLabels = [
    '128M',
    '1G',
    '8G',
    '16G',
    '64G',
    '128G',
    '256G',
  ];

  double _sliderIndex = 3.0; // 默认 16GB
  String? _nameError;
  String? _pathError;
  String? _sizeError;
  DirectorySelection? _directory;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Virtual Disk');
    _pathController = TextEditingController();
    _sizeController = TextEditingController(text: '16');

    _nameController.addListener(_onNameChanged);
    _pathController.addListener(_onPathChanged);
    _sizeController.addListener(_onSizeChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (_nameError != null) {
      setState(() {
        _validateName();
      });
    }
  }

  void _onPathChanged() {
    if (_pathError != null) {
      setState(() {
        _validatePath();
      });
    }
  }

  void _onSizeChanged() {
    if (_sizeError != null) {
      setState(() {
        _validateSize();
      });
    }
    _syncSliderFromText();
  }

  void _syncSliderFromText() {
    final parsed = double.tryParse(_sizeController.text.trim());
    if (parsed != null) {
      int closest = 0;
      double minDiff = (parsed - _presetGbValues[0]).abs();
      for (int i = 1; i < _presetGbValues.length; i++) {
        final diff = (parsed - _presetGbValues[i]).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = i;
        }
      }
      if ((parsed - _presetGbValues[closest]).abs() < 0.01 &&
          _sliderIndex != closest.toDouble()) {
        setState(() {
          _sliderIndex = closest.toDouble();
        });
      }
    }
  }

  bool _validateName() {
    final val = _nameController.text.trim();
    if (val.isEmpty) {
      _nameError = context.l10n.text('nameCannotBeEmpty');
      return false;
    }
    _nameError = null;
    return true;
  }

  bool _validatePath() {
    final val = _pathController.text.trim();
    final l10n = context.l10n;
    if (val.isEmpty) {
      _pathError = l10n.text('pathCannotBeEmpty');
      return false;
    }
    if (!val.startsWith('/') && !val.contains(r':\')) {
      _pathError = l10n.text('pathNotExist');
      return false;
    }
    _pathError = null;
    return true;
  }

  bool _validateSize() {
    final val = _sizeController.text.trim();
    final parsed = double.tryParse(val);
    if (parsed == null || parsed <= 0) {
      _sizeError = context.l10n.text('diskCapacityHint');
      return false;
    }
    _sizeError = null;
    return true;
  }

  bool _validateAll() {
    final nameValid = _validateName();
    final pathValid = _validatePath();
    final sizeValid = _validateSize();
    setState(() {});
    return nameValid && pathValid && sizeValid;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 第一行标题：新建磁盘
            Text(
              l10n.text('newDisk'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),

            // 第二行：名称编辑框
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.text('diskName'),
                hintText: l10n.text('diskNameHint'),
                errorText: _nameError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // 第三行：存储目录输入框 | 一个一样高的圆角矩形，内部是文件夹图标（选择文件夹）
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: l10n.text('storageDirectory'),
                        hintText: l10n.text('storageDirectoryHint'),
                        errorText: _pathError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        prefixIcon: const Icon(Icons.folder_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final selected =
                            await DocumentPickerService.pickDirectory();
                        if (selected != null && mounted) {
                          _directory = selected;
                          _pathController.text = selected.path;
                        }
                      },
                      child: Container(
                        width: 54,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.folder_open_rounded,
                          color: colorScheme.primary,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 第四行：输入框 GB
            TextField(
              controller: _sizeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.text('diskCapacity'),
                hintText: l10n.text('diskCapacityHint'),
                errorText: _sizeError,
                suffixText: 'GB',
                suffixStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                prefixIcon: const Icon(Icons.pie_chart_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // 第五行：128M 1GB 8G 16G 64GB 128GB 256GB 的拖拽条
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4.5,
                    activeTrackColor: colorScheme.primary,
                    inactiveTrackColor: colorScheme.surfaceContainerHighest,
                    thumbColor: colorScheme.primary,
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 18,
                    ),
                  ),
                  child: Slider(
                    value: _sliderIndex,
                    min: 0,
                    max: 6,
                    divisions: 6,
                    onChanged: (val) {
                      setState(() {
                        _sliderIndex = val;
                        final gb = _presetGbValues[val.round()];
                        if (gb < 1.0) {
                          _sizeController.text = '0.125';
                        } else {
                          _sizeController.text = gb.round().toString();
                        }
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _presetLabels
                        .map(
                          (lbl) => Text(
                            lbl,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(l10n.text('rawImageTitle')),
                subtitle: Text(l10n.text('rawImageDescription')),
              ),
            ),
            const SizedBox(height: 24),

            // 第七行：取消，新建，各占一半宽度
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l10n.text('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (!_validateAll()) return;

                      final name = _nameController.text.trim();
                      final folder = _pathController.text.trim().replaceAll(
                        RegExp(r'[/\\]+$'),
                        '',
                      );
                      final cleanName = name
                          .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5\-_]+'), '_')
                          .toLowerCase();
                      final fullPath =
                          '$folder/${cleanName.isEmpty ? "disk" : cleanName}.img';

                      final sizeGb =
                          double.tryParse(_sizeController.text.trim()) ?? 16.0;
                      final String formattedSize = sizeGb < 1.0
                          ? '${(sizeGb * 1024).round()} MB'
                          : '${sizeGb % 1 == 0 ? sizeGb.toInt() : sizeGb} GB';

                      if (_directory == null) {
                        _pathError = l10n.text('selectDestinationFolder');
                        setState(() {});
                        return;
                      }
                      final newDisk = DiskDeviceItem(
                        id: 'disk_${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        path: fullPath,
                        size: formattedSize,
                        fileSystem: 'RAW',
                        type: DiskDeviceType.usb,
                        state: DiskDeviceState.stopped,
                        accessMode: DiskAccessMode.readWrite,
                        enableFua: false,
                        removableMedia: true,
                        treeUri: _directory!.uri,
                      );

                      widget.onCreate(newDisk);
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l10n.text('create')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑/添加磁盘底部菜单（内置表单校验）
class DiskEditBottomSheet extends StatefulWidget {
  const DiskEditBottomSheet({
    super.key,
    required this.initialItem,
    required this.onSave,
    this.isImport = false,
  });

  final DiskDeviceItem initialItem;
  final ValueChanged<DiskDeviceItem> onSave;
  final bool isImport;

  /// 弹出底部菜单静态工具方法
  static Future<void> show(
    BuildContext context, {
    required DiskDeviceItem item,
    required ValueChanged<DiskDeviceItem> onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DiskEditBottomSheet(initialItem: item, onSave: onSave),
    );
  }

  static Future<void> showImport(
    BuildContext context, {
    required DiskDeviceItem item,
    required ValueChanged<DiskDeviceItem> onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DiskEditBottomSheet(
        initialItem: item,
        onSave: onSave,
        isImport: true,
      ),
    );
  }

  @override
  State<DiskEditBottomSheet> createState() => _DiskEditBottomSheetState();
}

class _DiskEditBottomSheetState extends State<DiskEditBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;
  late DiskAccessMode _accessMode;
  late bool _enableFua;
  late bool _removableMedia;

  String? _nameError;
  String? _pathError;
  DocumentSelection? _source;
  DirectorySelection? _destination;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialItem.name);
    _pathController = TextEditingController(text: widget.initialItem.path);
    _accessMode = widget.initialItem.accessMode;
    _enableFua = widget.initialItem.enableFua;
    _removableMedia = widget.initialItem.removableMedia;

    _nameController.addListener(_onNameChanged);
    _pathController.addListener(_onPathChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (_nameError != null) {
      setState(() {
        _validateName();
      });
    }
  }

  void _onPathChanged() {
    setState(() {
      if (_pathError != null) {
        _validatePath();
      }
    });
  }

  bool _validateName() {
    final val = _nameController.text.trim();
    if (val.isEmpty) {
      _nameError = context.l10n.text('nameCannotBeEmpty');
      return false;
    }
    _nameError = null;
    return true;
  }

  bool _validatePath() {
    final val = _pathController.text.trim();
    final l10n = context.l10n;
    if (val.isEmpty) {
      _pathError = l10n.text('pathCannotBeEmpty');
      return false;
    }

    final lower = val.toLowerCase();
    final hasSupportedExt =
        lower.endsWith('.img') ||
        lower.endsWith('.iso') ||
        lower.endsWith('.bin') ||
        lower.endsWith('.raw');

    if (!hasSupportedExt) {
      _pathError = l10n.text('fileNotSupported');
      return false;
    }

    // 检查路径合法性
    if (!val.startsWith('/') && !val.contains(r':\')) {
      _pathError = l10n.text('pathNotExist');
      return false;
    }

    _pathError = null;
    return true;
  }

  bool _validateAll() {
    final nameValid = _validateName();
    final pathValid = _validatePath();
    setState(() {});
    return nameValid && pathValid;
  }

  bool get _isImg => _pathController.text.toLowerCase().endsWith('.img');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 第一行标题：编辑磁盘
            Text(
              widget.isImport
                  ? l10n.text('importImage')
                  : l10n.text('editDisk'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),

            // 第二行：名称编辑框（非空校验与红色错误提醒）
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.text('diskName'),
                hintText: l10n.text('diskNameHint'),
                errorText: _nameError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // 第三行：路径输入框（格式与存在性校验） | 一个一样高的圆角矩形，内部是文件夹图标
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      readOnly: widget.isImport,
                      decoration: InputDecoration(
                        labelText: l10n.text('filePath'),
                        hintText: l10n.text('filePathHint'),
                        errorText: _pathError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        prefixIcon: const Icon(
                          Icons.insert_drive_file_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 选择文件按钮（高度与输入框完全一致的圆角矩形）
                  Material(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final source = await DocumentPickerService.pickFile();
                        if (source == null || !mounted) return;
                        final destination =
                            await DocumentPickerService.pickDirectory();
                        if (destination == null || !mounted) return;
                        _source = source;
                        _destination = destination;
                        _pathController.text =
                            '${destination.path}/${source.name}';
                        if (_nameController.text.trim().isEmpty) {
                          _nameController.text = source.name;
                        }
                      },
                      child: Container(
                        width: 54,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.folder_open_rounded,
                          color: colorScheme.primary,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 如果是img文件：第四行：二选一滑块选择器，只读，读写
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: _isImg
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.text('accessMode'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<DiskAccessMode>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: DiskAccessMode.readOnly,
                              label: Text(l10n.text('readOnly')),
                              icon: const Icon(Icons.lock_outline_rounded),
                            ),
                            ButtonSegment(
                              value: DiskAccessMode.readWrite,
                              label: Text(l10n.text('readWrite')),
                              icon: const Icon(Icons.edit_note_rounded),
                            ),
                          ],
                          selected: {_accessMode},
                          onSelectionChanged: (val) {
                            setState(() {
                              _accessMode = val.first;
                            });
                          },
                        ),
                        const SizedBox(height: 14),

                        // 当为img文件且设置为读写时：第五行：启用FUA（Force Unit Access），开关项
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOutCubic,
                          child: _accessMode == DiskAccessMode.readWrite
                              ? Card(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  color: colorScheme.surfaceContainerLow,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: SwitchListTile.adaptive(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 2,
                                    ),
                                    secondary: const Icon(
                                      Icons.flash_on_outlined,
                                    ),
                                    title: Text(
                                      l10n.text('enableFua'),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      l10n.text('enableFuaDesc'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    value: _enableFua,
                                    onChanged: (val) {
                                      setState(() {
                                        _enableFua = val;
                                      });
                                    },
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            // 第六行：视为可移动介质（开关项）
            Card(
              margin: EdgeInsets.zero,
              color: colorScheme.surfaceContainerLow,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                secondary: const Icon(Icons.usb_outlined),
                title: Text(
                  l10n.text('removableMedia'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  l10n.text('removableMediaDesc'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _removableMedia,
                onChanged: (val) {
                  setState(() {
                    _removableMedia = val;
                  });
                },
              ),
            ),
            const SizedBox(height: 22),

            // 第七行：取消，保存，各占一半宽度（保存时检查必填与合法性）
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l10n.text('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (!_validateAll()) {
                        return;
                      }

                      final name = _nameController.text.trim();
                      final path = _pathController.text.trim();

                      final ext = path.toLowerCase();
                      final String fileSystem = ext.endsWith('.iso')
                          ? 'ISO'
                          : ext.endsWith('.raw')
                          ? 'RAW'
                          : ext.endsWith('.bin')
                          ? 'BIN'
                          : (widget.initialItem.fileSystem.isEmpty ||
                                    widget.initialItem.fileSystem == 'RAW'
                                ? 'FAT32'
                                : widget.initialItem.fileSystem);

                      final updated = widget.initialItem.copyWith(
                        name: name,
                        path: path,
                        fileSystem: fileSystem,
                        type: ext.endsWith('.iso')
                            ? DiskDeviceType.cdrom
                            : DiskDeviceType.usb,
                        accessMode: _accessMode,
                        enableFua: _enableFua,
                        removableMedia: _removableMedia,
                        treeUri: _destination?.uri,
                        sourceUri: _source?.uri,
                        sourceSize: _source?.size,
                      );
                      widget.onSave(updated);
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.isImport
                          ? l10n.text('importImage')
                          : l10n.text('save'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DiskDeleteDecision {
  const DiskDeleteDecision({required this.deleteImageFile});
  final bool deleteImageFile;
}

class DiskDeleteBottomSheet extends StatefulWidget {
  const DiskDeleteBottomSheet({
    super.key,
    required this.diskName,
    required this.canDeleteImageFile,
  });

  final String diskName;
  final bool canDeleteImageFile;

  static Future<DiskDeleteDecision?> show(
    BuildContext context, {
    required String diskName,
    required bool canDeleteImageFile,
  }) => showModalBottomSheet<DiskDeleteDecision>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => DiskDeleteBottomSheet(
      diskName: diskName,
      canDeleteImageFile: canDeleteImageFile,
    ),
  );

  @override
  State<DiskDeleteBottomSheet> createState() => _DiskDeleteBottomSheetState();
}

class _DiskDeleteBottomSheetState extends State<DiskDeleteBottomSheet> {
  bool _deleteImageFile = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.text('deleteConfirmTitle'),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n
                .text('deleteConfigDescription')
                .replaceAll('%s', widget.diskName),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _deleteImageFile,
            onChanged: widget.canDeleteImageFile
                ? (value) => setState(() => _deleteImageFile = value ?? false)
                : null,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(context.l10n.text('deleteImageFile')),
            subtitle: Text(
              widget.canDeleteImageFile
                  ? context.l10n.text('deleteImageFileDescription')
                  : context.l10n.text('deleteImageUnavailable'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.text('cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    DiskDeleteDecision(deleteImageFile: _deleteImageFile),
                  ),
                  child: Text(context.l10n.text('confirm')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
