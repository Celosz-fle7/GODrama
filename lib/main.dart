import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'data/services/app_settings_service.dart';
import 'data/services/error_log_service.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tangkap error yang tidak tertangkap: tampilkan seperti biasa (debug)
  // + catat ke log error lokal (Profile > Log Error) agar bisa dilacak.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorLogService.record(
      'FlutterError',
      details.exception,
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLogService.record('Uncaught', error, stack);
    debugPrint('[Uncaught] $error');
    return true;
  };

  // Muat pengaturan, riwayat, dan favorit tersimpan sebelum UI tampil.
  await AppSettingsService.instance.init();

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
