import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperusb_ui/l10n/app_localizations.dart';
import 'package:hyperusb_ui/subDevice/disk/components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const documents = MethodChannel('org.orynnx.hyperusb/documents');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(documents, null);
  });

  testWidgets('import sheet folder button only opens the native file picker', (
    tester,
  ) async {
    final calls = <String>[];
    DiskDeviceItem? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(documents, (call) async {
          calls.add(call.method);
          if (call.method == 'pickFile') {
            return <String, Object>{
              'uri':
                  'content://com.android.fileexplorer.documents/document/primary%3ADownload%2Fdisk.img',
              'name': 'disk.img',
              'size': 4096,
              'directPath': '/storage/emulated/0/Download/disk.img',
            };
          }
          fail('Unexpected native call: ${call.method}');
        });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => DiskEditBottomSheet.showImport(
              context,
              item: DiskDeviceItem(
                id: 'import-test',
                name: '',
                path: '',
                size: '',
                fileSystem: 'RAW',
                type: DiskDeviceType.usb,
                accessMode: DiskAccessMode.readWrite,
              ),
              onSave: (item) => saved = item,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.folder_open_rounded));
    await tester.pumpAndSettle();

    expect(calls, ['pickFile']);
    expect(find.text('/storage/emulated/0/Download/disk.img'), findsOneWidget);
    expect(find.text('disk.img'), findsOneWidget);

    final pathField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '路径',
    );
    await tester.enterText(pathField, '/storage/emulated/0/manual.img');
    await tester.tap(find.widgetWithText(FilledButton, '导入镜像'));
    await tester.pumpAndSettle();

    expect(saved?.path, '/storage/emulated/0/manual.img');
    expect(saved?.sourceUri, isNull);
  });

  testWidgets('unavailable disk action remains clickable', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiskActionButton(
            state: DiskDeviceState.unavailable,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DiskActionButton));
    expect(pressed, isTrue);
  });

  testWidgets('linked disk delete sheet omits backing-file controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => DiskDeleteBottomSheet.show(
              context,
              diskName: 'linked.img',
              canDeleteImageFile: false,
            ),
            child: const Text('delete linked'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('delete linked'));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining('不可删除'), findsNothing);
    expect(find.textContaining('linked.img'), findsOneWidget);
  });

  testWidgets('managed disk delete sheet offers backing-file deletion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => DiskDeleteBottomSheet.show(
              context,
              diskName: 'managed.img',
              canDeleteImageFile: true,
            ),
            child: const Text('delete managed'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('delete managed'));
    await tester.pumpAndSettle();

    expect(find.text('同时从存储中删除镜像文件', skipOffstage: false), findsOneWidget);
    expect(find.byType(CheckboxListTile, skipOffstage: false), findsOneWidget);
  });
}
