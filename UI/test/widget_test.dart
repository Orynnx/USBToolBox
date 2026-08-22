import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hyperusb_ui/main.dart';
import 'package:hyperusb_ui/subDevice/mainScreen.dart';
import 'package:hyperusb_ui/subDevice/devicePage.dart';
import 'package:hyperusb_ui/subDevice/serial/serialScreen.dart';

void main() {
  testWidgets('USB Device Controller shows every device entry point', (
    tester,
  ) async {
    await tester.pumpWidget(const HyperUsbApp());
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.text('虚拟磁盘'), findsOneWidget);
    expect(find.text('虚拟 HID'), findsOneWidget);
    expect(find.text('虚拟摄像头'), findsOneWidget);
    expect(find.text('虚拟串口'), findsOneWidget);
    expect(find.text('虚拟网卡'), findsOneWidget);
  });

  testWidgets('device pages use the shared Material scaffold', (tester) async {
    await tester.pumpWidget(const HyperUsbApp());
    await tester.tap(find.text('虚拟磁盘'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceScaffold), findsOneWidget);
  });

  testWidgets('serial screen exposes only the three product modes', (
    tester,
  ) async {
    await tester.pumpWidget(const HyperUsbApp());
    final serialEntry = find.text('虚拟串口');
    await tester.ensureVisible(serialEntry);
    await tester.tap(serialEntry);
    await tester.pumpAndSettle();

    expect(find.byType(SerialScreen), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('用户'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);
    expect(find.text('波特率'), findsNothing);
    expect(find.text('数据位'), findsNothing);
    expect(find.text('校验位'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('net screen displays NCM adapter, MAC cards, DHCP and proxy toggles', (
    tester,
  ) async {
    await tester.pumpWidget(const HyperUsbApp());
    final netEntry = find.text('虚拟网卡');
    await tester.ensureVisible(netEntry);
    await tester.tap(netEntry);
    await tester.pumpAndSettle();

    expect(find.text('虚拟网卡'), findsWidgets);
    expect(find.text('NCM 虚拟网卡'), findsOneWidget);
    expect(find.text('为计算机和 Windows 设备构建 USB 网络通道'), findsOneWidget);
    expect(find.text('网卡设置'), findsOneWidget);
    expect(find.text('Android 侧 MAC 地址'), findsOneWidget);
    expect(find.text('USB 侧 MAC 地址'), findsOneWidget);
    expect(find.text('DHCP'), findsOneWidget);
    expect(find.text('从 Android 访问设备'), findsOneWidget);
    expect(find.text('从设备访问 Android'), findsOneWidget);
    expect(find.text('流量代理'), findsOneWidget);
    expect(find.text('也一并使用安卓的代理'), findsOneWidget);

    // Click Android MAC tile to open edit dialog
    await tester.tap(find.text('Android 侧 MAC 地址'));
    await tester.pumpAndSettle();
    expect(find.text('编辑 MAC 地址 (Android 侧 MAC 地址)'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // Default DHCP is on -> edit buttons are hidden
    expect(find.byKey(const ValueKey('editDeviceIp')), findsNothing);
    expect(find.byKey(const ValueKey('editAndroidIp')), findsNothing);

    // Toggle DHCP off
    final dhcpSwitch = find.descendant(
      of: find.widgetWithText(ListTile, 'DHCP'),
      matching: find.byType(Switch),
    );
    await tester.tap(dhcpSwitch);
    await tester.pumpAndSettle();

    // Now edit buttons are visible
    expect(find.byKey(const ValueKey('editDeviceIp')), findsOneWidget);
    expect(find.byKey(const ValueKey('editAndroidIp')), findsOneWidget);

    // Click edit IP button to verify dialog title is "编辑 IP"
    await tester.tap(find.byKey(const ValueKey('editDeviceIp')));
    await tester.pumpAndSettle();
    expect(find.text('编辑 IP'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('cam screen displays capability switch, source selector, and stream switch', (
    tester,
  ) async {
    await tester.pumpWidget(const HyperUsbApp());
    final camEntry = find.text('虚拟摄像头');
    await tester.ensureVisible(camEntry);
    await tester.tap(camEntry);
    await tester.pumpAndSettle();

    expect(find.text('USB 摄像头'), findsWidgets);
    expect(find.text('启用USB摄像头能力支持'), findsOneWidget);
    expect(find.text('后置'), findsOneWidget);
    expect(find.text('前置'), findsOneWidget);
    expect(find.text('屏幕'), findsOneWidget);
    expect(find.text('视频文件'), findsOneWidget);
    expect(find.text('启用传输'), findsOneWidget);
  });

  testWidgets('about screen displays developer info, 5-tap easter egg, version card, and contact channels', (
    tester,
  ) async {
    await tester.pumpWidget(const HyperUsbApp());
    // Navigate to Settings bottom nav tab
    final settingsNav = find.text('设置');
    await tester.tap(settingsNav);
    await tester.pumpAndSettle();

    // Tap 关于
    final aboutTile = find.text('关于');
    await tester.tap(aboutTile);
    await tester.pumpAndSettle();

    expect(find.text('Orynnx'), findsOneWidget);
    expect(find.text('凛野想要，凛野得到！'), findsOneWidget);
    expect(find.text('版本信息'), findsOneWidget);
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('1.0.0+1'), findsOneWidget);
    expect(find.text('感谢你使用我开发的HyperUSB！'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('QQ'), findsOneWidget);

    // Tap developer card 5 times to trigger easter egg
    final devCard = find.text('Orynnx');
    for (int i = 0; i < 5; i++) {
      await tester.tap(devCard);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.text('补药点了！！！'), findsOneWidget);
  });
}
