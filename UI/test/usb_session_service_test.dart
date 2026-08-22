import 'package:flutter_test/flutter_test.dart';
import 'package:hyperusb_ui/core/core_client.dart';
import 'package:hyperusb_ui/core/core_deployment_service.dart';
import 'package:hyperusb_ui/core/root_shell_service.dart';
import 'package:hyperusb_ui/storage/models/virtual_disk.dart';
import 'package:hyperusb_ui/usb/usb_session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRoot extends RootShellService {
  final commands = <String>[];
  final currentConfig =
      '{"device":{"serialNumber":"KEEP","vendorExtension":7},'
      '"keyboard":{"boot":true},"serial":{"enabled":true},'
      '"uvc":{"enabled":true,"formats":[]},'
      '"ncm":{"enabled":true,"deviceMac":"0a:48:59:50:45:01"},'
      '"futureSection":{"keep":"yes"}}';

  @override
  Future<String> runRootCommand(
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(command);
    if (command.startsWith('if [ -f ')) return currentConfig;
    if (command.contains('STATUS')) {
      return 'OK {"state":"active","storageLuns":["/storage/emulated/0/disk.img"],"keyboard":true,"serial":true,"uvc":true}\n';
    }
    if (command.contains('SET') || command.contains('PING')) return 'OK\n';
    return '';
  }
}

class _FakeDeployment extends CoreDeploymentService {
  _FakeDeployment(super.root, super.client);

  @override
  Future<void> ensureReady() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'storage update preserves NCM, other functions and unknown fields',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = _FakeRoot();
      final client = CoreClient(root);
      final session = UsbSessionService(
        root,
        _FakeDeployment(root, client),
        client,
      );
      const disk = VirtualDisk(
        id: 'disk',
        name: 'Disk',
        imagePath: '/storage/emulated/0/disk.img',
        type: VirtualDiskType.disk,
        readOnly: false,
        removable: true,
        enableFua: false,
        desiredEnabled: true,
        ownership: DiskBackingOwnership.linked,
        sizeBytes: 4096,
      );

      await session.apply([disk]);

      final write = root.commands.firstWhere(
        (command) => command.startsWith('umask 077; printf'),
      );
      expect(write, contains('"ncm":{"enabled":true'));
      expect(write, contains('"keyboard":{"boot":true}'));
      expect(write, contains('"serial":{"enabled":true}'));
      expect(write, contains('"uvc":{"enabled":true,"formats":[]}'));
      expect(write, contains('"futureSection":{"keep":"yes"}'));
      expect(write, contains('"vendorExtension":7'));
      expect(write, contains('"imagePath":"/storage/emulated/0/disk.img"'));
    },
  );
}
