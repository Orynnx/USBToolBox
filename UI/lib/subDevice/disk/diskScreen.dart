// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../core/core_client.dart';
import '../../core/core_deployment_service.dart';
import '../../core/root_shell_service.dart';
import '../../storage/models/virtual_disk.dart';
import '../../storage/services/disk_storage_service.dart';
import '../../storage/services/document_picker_service.dart';
import '../../usb/usb_session_service.dart';
import '../../theme/app_theme.dart';
import '../devicePage.dart';
import 'components.dart';

/// User-owned backing files only; never scans /sdcard for disks.
class DiskScreen extends StatefulWidget {
  const DiskScreen({super.key});
  @override
  State<DiskScreen> createState() => _DiskScreenState();
}

class _DiskScreenState extends State<DiskScreen> {
  final _storage = DiskStorageService();
  final _root = RootShellService();
  late final _client = CoreClient(_root);
  late final _session = UsbSessionService(
    _root,
    CoreDeploymentService(_root, _client),
    _client,
  );
  List<VirtualDisk> _disks = [];
  final Set<String> _operating = {};
  final Set<String> _removing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _storage.load();
    if (mounted) setState(() => _disks = value);
  }

  Future<void> _save() => _storage.save(_disks);
  String _errorText(String key, Object error) =>
      context.l10n.text(key).replaceAll('%s', '$error');
  int get _mounted => _disks.where((disk) => disk.desiredEnabled).length;

  DiskDeviceItem _item(VirtualDisk disk) => DiskDeviceItem(
    id: disk.id,
    name: disk.name,
    path: disk.imagePath,
    size: '${(disk.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
    fileSystem: disk.type == VirtualDiskType.cdrom ? 'ISO' : 'IMG',
    type: disk.type == VirtualDiskType.cdrom
        ? DiskDeviceType.cdrom
        : DiskDeviceType.usb,
    state: _operating.contains(disk.id)
        ? DiskDeviceState.operating
        : disk.desiredEnabled
        ? DiskDeviceState.running
        : DiskDeviceState.stopped,
    accessMode: disk.readOnly
        ? DiskAccessMode.readOnly
        : DiskAccessMode.readWrite,
    enableFua: disk.enableFua,
    removableMedia: disk.removable,
    documentUri: disk.documentUri,
  );

  Future<void> _toggle(VirtualDisk disk) async {
    final previous = List<VirtualDisk>.from(_disks);
    setState(() => _operating.add(disk.id));
    try {
      if (!disk.desiredEnabled && !disk.managedFile) {
        await _storage.verifyRegularFile(disk.imagePath);
      }
      _disks = _disks
          .map(
            (item) => item.id == disk.id
                ? item.copyWith(desiredEnabled: !item.desiredEnabled)
                : item,
          )
          .toList();
      final status = await _session.apply(_disks);
      _disks = _disks
          .map(
            (item) => item.copyWith(
              desiredEnabled: status.storageLuns.contains(item.imagePath),
            ),
          )
          .toList();
      await _save();
    } catch (error) {
      _disks = previous;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText('usbOperationFailed', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _operating.remove(disk.id));
    }
  }

  Future<void> _stopAll() async {
    final previous = List<VirtualDisk>.from(_disks);
    setState(() {
      _operating.addAll(_disks.map((disk) => disk.id));
      _disks = _disks
          .map((disk) => disk.copyWith(desiredEnabled: false))
          .toList();
    });
    try {
      await _session.apply(_disks);
      await _save();
    } catch (error) {
      _disks = previous;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText('usbOperationFailed', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _operating.clear());
    }
  }

  Future<void> _saveItem(
    DiskDeviceItem item, {
    bool managed = false,
    int? knownSize,
    String? documentUri,
  }) async {
    final size = knownSize ?? await _storage.verifyRegularFile(item.path);
    final disk = VirtualDisk(
      id: item.id,
      name: item.name,
      imagePath: item.path,
      type: item.type == DiskDeviceType.cdrom
          ? VirtualDiskType.cdrom
          : VirtualDiskType.disk,
      readOnly: item.accessMode == DiskAccessMode.readOnly,
      removable: item.removableMedia,
      enableFua: item.enableFua,
      desiredEnabled: false,
      managedFile: managed,
      sizeBytes: size,
      documentUri: documentUri ?? item.documentUri,
    );
    setState(() {
      final index = _disks.indexWhere((value) => value.id == disk.id);
      if (index < 0) {
        _disks.add(disk);
      } else {
        _disks[index] = disk;
      }
    });
    await _save();
  }

  void _import() => DiskEditBottomSheet.showImport(
    context,
    item: DiskDeviceItem(
      id: 'disk_${DateTime.now().millisecondsSinceEpoch}',
      name: '',
      path: '',
      size: '0 MB',
      fileSystem: 'IMG',
    ),
    onSave: (item) async {
      try {
        if (item.sourceUri == null || item.treeUri == null) {
          await _saveItem(item);
          return;
        }
        final separator = item.path.lastIndexOf('/');
        if (separator <= 0) {
          throw ArgumentError(context.l10n.text('invalidImportDestination'));
        }
        final destination = DirectorySelection(
          item.treeUri!,
          item.path.substring(0, separator),
        );
        final source = DocumentSelection(
          item.sourceUri!,
          item.path.substring(separator + 1),
          item.sourceSize ?? 0,
        );
        final copied = await DocumentPickerService.copyDocument(
          source,
          destination,
        );
        await _saveItem(
          item.copyWith(path: copied.path),
          managed: true,
          knownSize: copied.size,
          documentUri: copied.uri,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_errorText('importFailed', e))),
          );
        }
      }
    },
  );

  void _create() => DiskCreateBottomSheet.show(
    context,
    onCreate: (item) async {
      try {
        final value =
            double.tryParse(
              RegExp(r'[0-9.]+').firstMatch(item.size)?.group(0) ?? '',
            ) ??
            0;
        final bytes =
            (value *
                    (item.size.contains('GB')
                        ? 1024 * 1024 * 1024
                        : 1024 * 1024))
                .round();
        final safe = item.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
        if (item.treeUri == null ||
            !(item.path == '/storage/emulated/0' ||
                item.path.startsWith('/storage/emulated/0/'))) {
          throw ArgumentError(
            context.l10n.text('selectInternalStorageDirectory'),
          );
        }
        final separator = item.path.lastIndexOf('/');
        final directory = separator > 0
            ? item.path.substring(0, separator)
            : item.path;
        final created = await DocumentPickerService.createSparse(
          DirectorySelection(item.treeUri!, directory),
          '${safe.isEmpty ? item.id : safe}.img',
          bytes,
        );
        await _saveItem(
          item.copyWith(path: created.path),
          managed: true,
          knownSize: created.size,
          documentUri: created.uri,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_errorText('createFailed', error))),
          );
        }
      }
    },
  );
  void _edit(VirtualDisk disk) {
    if (disk.desiredEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('stopDiskBeforeEditing'))),
      );
      return;
    }
    DiskEditBottomSheet.show(
      context,
      item: _item(disk),
      onSave: (item) => _saveItem(item, managed: disk.managedFile),
    );
  }

  Future<void> _delete(VirtualDisk disk) async {
    final missingFilePermission = context.l10n.text('missingFilePermission');
    final decision = await DiskDeleteBottomSheet.show(
      context,
      diskName: disk.name,
      canDeleteImageFile: disk.documentUri != null,
    );
    if (decision == null || !mounted) return;
    try {
      if (disk.desiredEnabled) await _toggle(disk);
      if (_disks.any((item) => item.id == disk.id && item.desiredEnabled)) {
        return;
      }
      if (decision.deleteImageFile) {
        final uri = disk.documentUri;
        if (uri == null) {
          throw StateError(missingFilePermission);
        }
        await DocumentPickerService.deleteDocument(uri);
      }
      if (!mounted) return;
      setState(() => _removing.add(disk.id));
      if (!appThemeManager.disableAnimations) {
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }
      if (!mounted) return;
      setState(() {
        _disks.removeWhere((item) => item.id == disk.id);
        _removing.remove(disk.id);
      });
      await _save();
    } catch (error) {
      if (mounted) {
        setState(() => _removing.remove(disk.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText('deleteFailed', error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => DeviceScaffold(
    title: context.l10n.text('virtualDisks'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DiskStatusHeader(mountedCount: _mounted, onMasterAction: _stopAll),
        const SizedBox(height: 14),
        ..._disks.map(
          (disk) => AnimatedSize(
            key: ValueKey(disk.id),
            duration: appThemeManager.disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            child: AnimatedSwitcher(
              duration: appThemeManager.disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: _removing.contains(disk.id)
                  ? const SizedBox.shrink(key: ValueKey('removed'))
                  : DiskDeviceCard(
                      key: const ValueKey('card'),
                      item: _item(disk),
                      onEdit: () => _edit(disk),
                      onToggleState: () => _toggle(disk),
                      onDelete: () => _delete(disk),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        DiskActionButtons(onImport: _import, onCreate: _create),
      ],
    ),
  );
}
