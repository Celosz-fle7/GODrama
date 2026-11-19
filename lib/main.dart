import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'core/player/smart_stream_proxy.dart';
import 'data/services/app_settings_service.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Muat pengaturan, riwayat, dan favorit tersimpan sebelum UI tampil.
  await AppSettingsService.instance.init();

  // Inisialisasi local stream proxy untuk video caching & smart preloading
  await SmartStreamProxy.instance.start();

  // Edge to edge transparent system overlay
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF13151F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const GoDramaApp());
}

class GoDramaApp extends StatelessWidget {
  const GoDramaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoDrama',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainShell(),
    );
  }
}
