import 'package:flutter_test/flutter_test.dart';
import 'package:hyperusb_ui/core/core_client.dart';
import 'package:hyperusb_ui/core/core_deployment_service.dart';
import 'package:hyperusb_ui/core/root_shell_service.dart';
import 'package:hyperusb_ui/hid/keyboard_service.dart';
import 'package:hyperusb_ui/storage/models/virtual_disk.dart';
import 'package:hyperusb_ui/storage/services/disk_storage_service.dart';
import 'package:hyperusb_ui/usb/usb_session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRootShellService extends RootShellService {
  final List<String> executedCommands = [];

  @override
  Future<String> runRootCommand(
    String command, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    executedCommands.add(command);
    if (command.contains('toybox nc')) {
      if (command.contains('SET')) return 'OK\n';
      if (command.contains('STATUS')) {
        return 'OK {"state":"active","storageLuns":[],"keyboard":true,"serial":false,"uvc":false}\n';
      }
      if (command.contains('BOOT_KEY')) return 'OK\n';
      if (command.contains('PING')) return 'OK\n';
    }
    return '';
  }
}

class FakeDiskStorageService extends DiskStorageService {
  @override
  Future<List<VirtualDisk>> load() async {
    return [
      VirtualDisk(
        id: 'disk-1',
        name: 'FlashDisk',
        imagePath: '/data/local/tmp/test.img',
        sizeBytes: 1024 * 1024,
        type: VirtualDiskType.disk,
        desiredEnabled: true,
        readOnly: false,
        removable: true,
        enableFua: true,
        ownership: DiskBackingOwnership.managedCopy,
      ),
    ];
  }
}

class FakeCoreDeploymentService extends CoreDeploymentService {
  FakeCoreDeploymentService(super.root, super.client);
  bool readyEnsured = false;

  @override
  Future<void> ensureReady() async {
    readyEnsured = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeyboardService tests', () {
    late FakeRootShellService fakeRoot;
    late CoreClient coreClient;
    late FakeCoreDeploymentService fakeDeployment;
    late UsbSessionService sessionService;
    late FakeDiskStorageService fakeDisks;
    late KeyboardService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeRoot = FakeRootShellService();
      coreClient = CoreClient(fakeRoot);
      fakeDeployment = FakeCoreDeploymentService(fakeRoot, coreClient);
      sessionService = UsbSessionService(fakeRoot, fakeDeployment, coreClient);
      fakeDisks = FakeDiskStorageService();
      service = KeyboardService(
        root: fakeRoot,
        client: coreClient,
        deployment: fakeDeployment,
        session: sessionService,
        disks: fakeDisks,
      );
    });

    test(
      'enable() ensures deployment and applies keyboard.boot=true preserving disks',
      () async {
        await service.enable();

        expect(fakeDeployment.readyEnsured, isTrue);
        expect(service.currentStatus.enabled, isTrue);
        expect(service.currentStatus.ready, isTrue);

        final hasConfigWithKeyboardBoot = fakeRoot.executedCommands.any(
          (cmd) =>
              cmd.contains('"keyboard":{"boot":true}') &&
              cmd.contains('"luns":[{"imagePath":"/data/local/tmp/test.img"'),
        );
        expect(hasConfigWithKeyboardBoot, isTrue);
      },
    );

    test('sendKey(A) issues BOOT_KEY A', () async {
      await service.sendKey('A');

      final hasBootKeyA = fakeRoot.executedCommands.any(
        (cmd) => cmd.contains('BOOT_KEY A'),
      );
      expect(hasBootKeyA, isTrue);
    });

    test('sendModifiers(SHIFT) issues BOOT_KEY SHIFT', () async {
      await service.sendModifiers(['SHIFT']);

      final hasBootKeyShift = fakeRoot.executedCommands.any(
        (cmd) => cmd.contains('BOOT_KEY SHIFT'),
      );
      expect(hasBootKeyShift, isTrue);
    });

    test('sendShortcut(ALT, F4) issues single BOOT_KEY ALT F4', () async {
      await service.sendShortcut(['ALT'], 'F4');

      final hasBootKeyAltF4 = fakeRoot.executedCommands.any(
        (cmd) => cmd.contains('BOOT_KEY ALT F4'),
      );
      expect(hasBootKeyAltF4, isTrue);
    });

    test(
      'sendShortcut(CTRL, SHIFT, ESC) issues single BOOT_KEY CTRL SHIFT ESC',
      () async {
        await service.sendShortcut(['CTRL', 'SHIFT'], 'ESC');

        final hasBootKeyCtrlShiftEsc = fakeRoot.executedCommands.any(
          (cmd) => cmd.contains('BOOT_KEY CTRL SHIFT ESC'),
        );
        expect(hasBootKeyCtrlShiftEsc, isTrue);
      },
    );

    test('typeText(Ab1!) sends strokes sequentially in order', () async {
      await service.typeText('Ab1!', intervalMs: 1);

      final bootKeyCommands = fakeRoot.executedCommands
          .where((cmd) => cmd.contains('BOOT_KEY'))
          .toList();

      expect(bootKeyCommands.length, 4);
      expect(bootKeyCommands[0], contains('BOOT_KEY SHIFT A'));
      expect(bootKeyCommands[1], contains('BOOT_KEY B'));
      expect(bootKeyCommands[2], contains('BOOT_KEY 1'));
      expect(bootKeyCommands[3], contains('BOOT_KEY SHIFT 1'));
    });

    test(
      'cancelTyping stops pending keystrokes immediately without dummy releases',
      () async {
        service.cancelTyping();
        expect(service.currentStatus.isSending, isFalse);
      },
    );
  });
}
