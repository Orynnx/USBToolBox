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
}
