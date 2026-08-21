import 'package:flutter_test/flutter_test.dart';
import 'package:hyperusb_ui/main.dart';
import 'package:hyperusb_ui/subDevice/mainScreen.dart';
import 'package:hyperusb_ui/subDevice/devicePage.dart';

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
}
