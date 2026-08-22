import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperusb_ui/core/core_client.dart';
import 'package:hyperusb_ui/core/core_deployment_service.dart';
import 'package:hyperusb_ui/core/root_shell_service.dart';
import 'package:hyperusb_ui/l10n/app_localizations.dart';
import 'package:hyperusb_ui/storage/models/virtual_disk.dart';
import 'package:hyperusb_ui/storage/services/disk_storage_service.dart';
import 'package:hyperusb_ui/subDevice/mainScreen.dart';
import 'package:hyperusb_ui/usb/usb_session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRootShellService extends RootShellService {
  final List<String> executedCommands = [];
  String statusPayload =
      'OK {"state":"active","storageLuns":["/data/test.img"],"keyboard":true,"serial":true,"uvc":true}\n';

  @override
  Future<String> runRootCommand(
    String command, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    executedCommands.add(command);
    if (command.contains('STATUS')) {
      return statusPayload;
    }
    if (command.contains('SET')) {
      return 'OK\n';
    }
    if (command.contains('PING')) {
      return 'OK\n';
    }
    return '';
  }
}

class FakeDiskStorageService extends DiskStorageService {
  @override
  Future<List<VirtualDisk>> load() async {
    return [
      const VirtualDisk(
        id: 'disk-1',
        name: 'FlashDisk',
        imagePath: '/data/test.img',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MainScreen reflects real active Core status on all indicators', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fakeRoot = FakeRootShellService();
    final client = CoreClient(fakeRoot);
    final deployment = CoreDeploymentService(fakeRoot, client);
    final session = UsbSessionService(fakeRoot, deployment, client);
    final disks = FakeDiskStorageService();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MainScreen(client: client, session: session, disks: disks),
      ),
    );

    await tester.pumpAndSettle();

    // Controller running state
    expect(
      find.text('运行中'),
      findsNWidgets(2),
    ); // Card status + environment info
    expect(find.text('HyperUSB 正在控制此 USB 设备'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget); // Core integration connected
    expect(find.text('已启用'), findsNWidgets(4)); // disk, hid, uvc, serial
  });

  testWidgets('MainScreen reflects stopped Core status when inactive', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fakeRoot = FakeRootShellService();
    fakeRoot.statusPayload =
        'OK {"state":"android","storageLuns":[],"keyboard":false,"serial":false,"uvc":false}\n';
    final client = CoreClient(fakeRoot);
    final deployment = CoreDeploymentService(fakeRoot, client);
    final session = UsbSessionService(fakeRoot, deployment, client);
    final disks = FakeDiskStorageService();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MainScreen(client: client, session: session, disks: disks),
      ),
    );

    await tester.pumpAndSettle();

    // Controller stopped state
    expect(find.text('已停止'), findsNWidgets(2));
    expect(find.text('USB 由 Android 系统管理'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('已禁用'), findsNWidgets(5));
  });
}
