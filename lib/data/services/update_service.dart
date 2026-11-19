import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final bool isForceUpdate;
  final String title;
  final String changelog;
  final String downloadUrl;

  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.isForceUpdate,
    required this.title,
    required this.changelog,
    required this.downloadUrl,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionCode: json['version_code'] ?? 1,
      versionName: json['version_name'] ?? '1.0.0',
      isForceUpdate: json['is_force_update'] ?? false,
      title: json['title'] ?? 'Pembaruan Tersedia!',
      changelog: json['changelog'] ?? 'Peningkatan performa dan perbaikan bug.',
      downloadUrl:
          json['download_url'] ??
          'https://github.com/Celosz-fle7/GODrama/releases/latest',
    );
  }
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  // Versi aplikasi dibaca dari PackageInfo (pubspec), BUKAN hardcoded.
  // Nilai hardcoded dulu (1 / 1.0.0) membuat dialog update muncul selamanya.
  int _currentVersionCode = 0;
  String _currentVersionName = '';
  bool _versionLoaded = false;

  int get currentVersionCode => _currentVersionCode;
  String get currentVersionName => _currentVersionName;
  String get currentVersionLabel => _currentVersionCode > 0
      ? 'v$_currentVersionName ($_currentVersionCode)'
      : '';

  static const String versionCheckUrl =
      "https://raw.githubusercontent.com/Celosz-fle7/GODrama/main/version.json";

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  bool _dialogShowing = false;

  /// Muat versi terpasang sekali, lalu cache. Mengembalikan false bila
  /// versi tidak bisa dibaca — dalam hal itu perbandingan tidak jujur
  /// dilakukan, jadi cek update dibatalkan.
  Future<bool> ensureVersionLoaded() async {
    if (_versionLoaded) return _currentVersionCode > 0;
    _versionLoaded = true;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersionCode = int.tryParse(info.buildNumber) ?? 0;
      _currentVersionName = info.version;
    } catch (_) {
      _currentVersionCode = 0;
      _currentVersionName = '';
    }
    return _currentVersionCode > 0;
  }

  /// Memeriksa pembaruan aplikasi.
  /// Jika [silent] bernilai true, tidak akan memunculkan dialog/snackbar jika tidak ada pembaruan.
  Future<void> checkForUpdate(
    BuildContext context, {
    bool silent = true,
  }) async {
    final versionOk = await ensureVersionLoaded();
    if (!versionOk) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF1E232E),
            content: Text(
              'Tidak bisa membaca versi aplikasi saat ini.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
      return;
    }
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final response = await _dio.get(
        '$versionCheckUrl?t=$timestamp',
        options: Options(responseType: ResponseType.json),
      );

      if (response.statusCode == 200 && response.data != null) {
        Map<String, dynamic> data;
        if (response.data is Map<String, dynamic>) {
          data = response.data;
        } else if (response.data is Map) {
          data = Map<String, dynamic>.from(response.data);
        } else {
          return;
        }

        final updateInfo = UpdateInfo.fromJson(data);

        if (updateInfo.versionCode > currentVersionCode) {
          if (context.mounted && !_dialogShowing) {
            _showUpdatePopup(context, updateInfo);
          }
        } else if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E232E),
              content: Text(
                'GoDrama sudah dalam versi terbaru (v$currentVersionName)',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Check update error: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text(
              'Gagal memeriksa pembaruan: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  void _showUpdatePopup(BuildContext context, UpdateInfo updateInfo) {
    _dialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: !updateInfo.isForceUpdate,
      builder: (dialogContext) {
        return WillPopScope(
          onWillPop: () async => !updateInfo.isForceUpdate,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D27),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 30,
                    spreadRadius: 5,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon badge header
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF3366), Color(0xFFFF5E3A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF3366).withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title & Version Badge
                  Center(
                    child: Text(
                      updateInfo.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3366).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF3366).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Versi Terbaru: v${updateInfo.versionName}',
                        style: const TextStyle(
                          color: Color(0xFFFF3366),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Changelog box
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12141C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Catatan Pembaruan:',
                            style: TextStyle(
                              color: Color(0xFF8E95A5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            updateInfo.changelog,
                            style: const TextStyle(
                              color: Color(0xFFE2E4E9),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tombol Perbarui Sekarang
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF3366), Color(0xFFFF5E3A)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3366).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () async {
                        final uri = Uri.parse(updateInfo.downloadUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Perbarui Sekarang',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tombol Nanti (hanya jika bukan force update)
                  if (!updateInfo.isForceUpdate) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        _dialogShowing = false;
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text(
                        'Nanti Saja',
                        style: TextStyle(
                          color: Color(0xFF8E95A5),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _dialogShowing = false;
    });
  }
}
