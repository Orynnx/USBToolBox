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
}
