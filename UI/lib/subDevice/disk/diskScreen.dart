// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final _deployment = CoreDeploymentService(_root, _client);
  late final _session = UsbSessionService(_root, _deployment, _client);
  List<VirtualDisk> _disks = [];
  final Set<String> _operating = {};
  final Set<String> _removing = {};
  final Set<String> _unavailable = {};
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _storage.load();
    if (!mounted) return;
    setState(() => _disks = value);
    await _verifyLoadedDisks();
  }

  Future<void> _verifyLoadedDisks() async {
    try {
      await _deployment.ensureReady();
    } catch (_) {
      return;
    }
    var changed = false;
    for (final disk in List<VirtualDisk>.from(_disks)) {
      try {
        final probe = await _client.probeImage(disk.imagePath);
        final normalized = disk.copyWith(
          imagePath: probe.path,
          sizeBytes: probe.sizeBytes,
        );
        final index = _disks.indexWhere((item) => item.id == disk.id);
        if (index >= 0 &&
            (probe.path != disk.imagePath ||
                probe.sizeBytes != disk.sizeBytes)) {
          _disks[index] = normalized;
          changed = true;
        }
        _unavailable.remove(disk.id);
      } on CoreException catch (error) {
        if (error.code == CoreErrorCode.imageNotFound ||
            error.code == CoreErrorCode.imageNotFile) {
          _unavailable.add(disk.id);
          if (disk.desiredEnabled) {
            final index = _disks.indexWhere((item) => item.id == disk.id);
            if (index >= 0) {
              _disks[index] = disk.copyWith(desiredEnabled: false);
              changed = true;
            }
          }
        }
      }
      if (mounted) setState(() {});
    }
    if (changed) await _save();
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
    state: _unavailable.contains(disk.id)
        ? DiskDeviceState.unavailable
        : _operating.contains(disk.id)
        ? DiskDeviceState.operating
        : disk.desiredEnabled
        ? DiskDeviceState.running
        : DiskDeviceState.stopped,
    accessMode: disk.readOnly
        ? DiskAccessMode.readOnly
        : DiskAccessMode.readWrite,
    enableFua: disk.enableFua,
    removableMedia: disk.removable,
    documentUri: disk.managedDocumentUri,
  );

  Future<void> _toggle(VirtualDisk disk) async {
    final previous = List<VirtualDisk>.from(_disks);
    setState(() => _operating.add(disk.id));
    try {
      if (!disk.desiredEnabled) {
        await _deployment.ensureReady();
        final probe = await _client.probeImage(disk.imagePath);
        _disks = _disks
            .map(
              (item) => item.id == disk.id
                  ? item.copyWith(
                      imagePath: probe.path,
                      sizeBytes: probe.sizeBytes,
                    )
                  : item,
            )
            .toList();
        _unavailable.remove(disk.id);
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
      if (error is CoreException &&
          (error.code == CoreErrorCode.imageNotFound ||
              error.code == CoreErrorCode.imageNotFile)) {
        _unavailable.add(disk.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorText('usbOperationFailed', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _operating.remove(disk.id));
    }
  }

  Future<void> _handleDiskAction(VirtualDisk disk) async {
    if (!_unavailable.contains(disk.id)) {
      await _toggle(disk);
      return;
    }
    if (!mounted) return;
    await DiskErrorBottomSheet.show(
      context,
      item: _item(disk),
      reason: DiskErrorReason.fileNotFound,
      onEdit: () => _edit(disk),
      onDelete: () => _delete(disk),
    );
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
    required DiskBackingOwnership ownership,
    String? sourceUri,
    String? managedDocumentUri,
  }) async {
    await _deployment.ensureReady();
    final probe = await _client.probeImage(item.path);
    final disk = VirtualDisk(
      id: item.id,
      name: item.name,
      imagePath: probe.path,
      type: item.type == DiskDeviceType.cdrom
          ? VirtualDiskType.cdrom
          : VirtualDiskType.disk,
      readOnly: item.accessMode == DiskAccessMode.readOnly,
      removable: item.removableMedia,
      enableFua: item.enableFua,
      desiredEnabled: false,
      ownership: ownership,
      sizeBytes: probe.sizeBytes,
      sourceUri: sourceUri,
      managedDocumentUri: managedDocumentUri,
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

  Future<void> _import() => DiskEditBottomSheet.showImport(
    context,
    item: DiskDeviceItem(
      id: 'disk_${DateTime.now().microsecondsSinceEpoch}',
      name: '',
      path: '',
      size: '',
      fileSystem: 'RAW',
      type: DiskDeviceType.usb,
      accessMode: DiskAccessMode.readWrite,
    ),
    onSave: _importSelected,
  );

  Future<void> _importSelected(DiskDeviceItem item) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final pathNotExistText = context.l10n.text('pathNotExist');
      final sourceUri = item.sourceUri;
      final directPath = item.path.startsWith('/') ? item.path : null;
      final sourceSegments = sourceUri == null
          ? const <String>[]
          : Uri.parse(sourceUri).pathSegments;
      final selectedName =
          directPath?.split('/').last ??
          (sourceUri == null
              ? item.path.split('/').last
              : sourceSegments.isEmpty
              ? item.name
              : sourceSegments.last);
      final source = sourceUri == null
          ? null
          : DocumentSelection(
              sourceUri,
              selectedName,
              item.sourceSize ?? 0,
              directPath: directPath,
            );
      if (!_isSupportedImage(selectedName)) {
        throw ArgumentError(context.l10n.text('fileNotSupported'));
      }

      CoreImageProbe? directProbe;
      Object? directError;
      if (directPath != null) {
        await _deployment.ensureReady();
        try {
          directProbe = await _client.probeImage(directPath);
        } on CoreException catch (error) {
          directError = error;
          if (error.code != CoreErrorCode.imageNotFound &&
              error.code != CoreErrorCode.imageNotFile &&
              error.code != CoreErrorCode.invalidConfigPath) {
            rethrow;
          }
        }
      }

      if (directProbe != null) {
        await _saveItem(
          item.copyWith(
            path: directProbe.path,
            size:
                '${(directProbe.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
          ),
          ownership: DiskBackingOwnership.linked,
          sourceUri: source?.uri,
        );
        return;
      }

      if (source == null) {
        throw directError ?? ArgumentError(pathNotExistText);
      }

      if (!await _confirmCopyFallback() || !mounted) return;
      final destination = await DocumentPickerService.pickDirectory();
      if (destination == null || !mounted) return;
      final task = DocumentPickerService.copyDocument(source, destination);
      final copied = await _showCopyProgress(task);
      if (copied == null || !mounted) return;
      try {
        await _saveItem(
          item.copyWith(
            path: copied.path,
            size: '${(copied.size / (1024 * 1024)).toStringAsFixed(1)} MB',
          ),
          ownership: DiskBackingOwnership.managedCopy,
          sourceUri: source.uri,
          managedDocumentUri: copied.uri,
        );
      } catch (_) {
        await DocumentPickerService.deleteDocument(copied.uri);
        rethrow;
      }
    } on PlatformException catch (error) {
      if (error.code != 'copy_cancelled' && mounted) {
        await _showImportError(
          error.code == 'insufficient_space'
              ? context.l10n.text('insufficientSpace')
              : '$error',
        );
      }
    } catch (error) {
      if (mounted) {
        await _showImportError(_importErrorDetail(error, item.path));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _importErrorDetail(Object error, String path) {
    if (error is CoreException) {
      final key = switch (error.code) {
        CoreErrorCode.imageNotFound => 'importPathNotFound',
        CoreErrorCode.imageNotFile => 'importPathNotFile',
        CoreErrorCode.invalidConfigPath => 'importPathInvalid',
        _ => null,
      };
      if (key != null) {
        return context.l10n.text(key).replaceAll('%s', path);
      }
    }
    return '$error';
  }

  Future<void> _showImportError(String detail) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('importFailedTitle')),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.text('close')),
          ),
        ],
      ),
    );
  }

  bool _isSupportedImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.img') ||
        lower.endsWith('.iso') ||
        lower.endsWith('.bin') ||
        lower.endsWith('.raw');
  }

  Future<bool> _confirmCopyFallback() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.text('copyRequiredTitle')),
          content: Text(context.l10n.text('copyRequiredBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.text('selectAndCopy')),
            ),
          ],
        ),
      ) ??
      false;

  Future<DocumentWriteResult?> _showCopyProgress(DocumentCopyTask task) async {
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('copyingImage')),
        content: ValueListenableBuilder<DocumentCopyProgress>(
          valueListenable: task.progress,
          builder: (_, progress, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: progress.fraction),
              const SizedBox(height: 12),
              Text(
                progress.totalBytes > 0
                    ? '${(progress.copiedBytes / (1024 * 1024)).toStringAsFixed(1)} / '
                          '${(progress.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                    : context.l10n.text('preparingCopy'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => task.cancel(),
            child: Text(context.l10n.text('cancel')),
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      return await task.result;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await dialog;
      await task.dispose();
    }
  }

  void _create() => DiskCreateBottomSheet.show(
    context,
    onCreate: (item) async {
      DocumentWriteResult? created;
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
        created = await DocumentPickerService.createSparse(
          DirectorySelection(item.treeUri!, directory),
          '${safe.isEmpty ? item.id : safe}.img',
          bytes,
        );
        await _saveItem(
          item.copyWith(path: created.path),
          ownership: DiskBackingOwnership.managedNew,
          managedDocumentUri: created.uri,
        );
      } catch (error) {
        if (created != null) {
          try {
            await DocumentPickerService.deleteDocument(created.uri);
          } catch (_) {}
        }
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
      onSave: (item) async {
        final changedBacking = item.path != disk.imagePath;
        await _saveItem(
          item,
          ownership: changedBacking
              ? DiskBackingOwnership.linked
              : disk.ownership,
          sourceUri: changedBacking ? null : disk.sourceUri,
          managedDocumentUri: changedBacking ? null : disk.managedDocumentUri,
        );
      },
    );
  }

  Future<void> _delete(VirtualDisk disk) async {
    final missingFilePermission = context.l10n.text('missingFilePermission');
    final decision = await DiskDeleteBottomSheet.show(
      context,
      diskName: disk.name,
      canDeleteImageFile: disk.canDeleteBacking,
    );
    if (decision == null || !mounted) return;
    try {
      if (disk.desiredEnabled) await _toggle(disk);
      if (_disks.any((item) => item.id == disk.id && item.desiredEnabled)) {
        return;
      }
      if (decision.deleteImageFile) {
        final uri = disk.managedDocumentUri;
        if (uri == null) {
          throw StateError(missingFilePermission);
        }
        if (!_unavailable.contains(disk.id)) {
          try {
            await DocumentPickerService.deleteDocument(uri);
          } catch (error) {
            var backingMissing = false;
            try {
              await _deployment.ensureReady();
              await _client.probeImage(disk.imagePath);
            } on CoreException catch (probeError) {
              backingMissing =
                  probeError.code == CoreErrorCode.imageNotFound ||
                  probeError.code == CoreErrorCode.imageNotFile;
            }
            if (!backingMissing) rethrow;
          }
        }
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
                      onToggleState: () => _handleDiskAction(disk),
                      onDelete: () => _delete(disk),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        DiskActionButtons(
          onImport: _import,
          onCreate: _create,
          importing: _importing,
        ),
      ],
    ),
  );
}
