import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'subDevice/mainScreen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const HyperUsbApp());
}

class HyperUsbApp extends StatelessWidget {
  const HyperUsbApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HyperUSB',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff596a9e)),
      scaffoldBackgroundColor: const Color(0xfffaf9fe),
      appBarTheme: const AppBarTheme(centerTitle: false),
    ),
    home: const MainScreen(),
  );
}
