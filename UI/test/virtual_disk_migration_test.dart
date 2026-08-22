import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperusb_ui/storage/models/virtual_disk.dart';
import 'package:hyperusb_ui/storage/services/disk_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy managed disk migrates to managedCopy ownership', () async {
    SharedPreferences.setMockInitialValues({
      'hyperusb.virtual_disks.v1': jsonEncode([
        {
          'id': 'legacy',
          'name': 'Legacy ISO',
          'imagePath': '/storage/emulated/0/HyperUSB/legacy.iso',
          'type': 'cdrom',
          'readOnly': true,
          'removable': true,
          'enableFua': false,
          'desiredEnabled': false,
          'managedFile': true,
          'sizeBytes': 1024,
          'documentUri': 'content://managed/legacy',
        },
      ]),
    });

    final disks = await DiskStorageService().load();

    expect(disks, hasLength(1));
    expect(disks.single.ownership, DiskBackingOwnership.managedCopy);
    expect(disks.single.managedDocumentUri, 'content://managed/legacy');
    expect(disks.single.sourceUri, isNull);
  });

  test(
    'corrupt registry entries are skipped without hiding valid disks',
    () async {
      SharedPreferences.setMockInitialValues({
        'hyperusb.virtual_disks.v1': jsonEncode([
          {
            'id': 'linked',
            'name': 'Linked IMG',
            'imagePath': '/storage/emulated/0/Download/disk.img',
            'type': 'disk',
            'readOnly': false,
            'removable': true,
            'enableFua': false,
            'desiredEnabled': false,
            'managedFile': false,
            'sizeBytes': 2048,
            'documentUri': 'content://source/disk',
          },
          {'broken': true},
        ]),
      });
      final storage = DiskStorageService();

      final disks = await storage.load();

      expect(disks, hasLength(1));
      expect(disks.single.ownership, DiskBackingOwnership.linked);
      expect(disks.single.sourceUri, 'content://source/disk');
      expect(disks.single.canDeleteBacking, isFalse);
      expect(storage.loadWarnings, hasLength(1));
    },
  );
}
