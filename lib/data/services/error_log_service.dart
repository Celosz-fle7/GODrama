import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Log error lokal (maks 20 entri terakhir) — pengganti ringan crash
/// reporting sampai ada Crashlytics/Sentry (butuh akun Firebase/Sentry).
/// Ditulis oleh global error handler di main(); dibaca dari
/// Profile > Log Error. Tidak pernah melempar: gagal tulis = debugPrint.
class ErrorLogService {
  static const _key = 'godrama_error_log';
  static const _maxEntries = 20;

  static Future<void> record(
    String tag,
    Object error, [
    StackTrace? stack,
  ]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final list = <Map<String, dynamic>>[];
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) list.add(e);
          }
        }
      }
      list.add({
        'ts': DateTime.now().toIso8601String(),
        'tag': tag,
        'message': error.toString(),
        if (stack != null)
          'stack': stack.toString().split('\n').take(8).join('\n'),
      });
      while (list.length > _maxEntries) {
        list.removeAt(0);
      }
      await prefs.setString(_key, jsonEncode(list));
    } catch (e) {
      debugPrint('[ErrorLog] Gagal menulis log: $e');
    }
  }

  /// Entri terbaru dulu. Gagal baca = daftar kosong (bukan crash).
  static Future<List<Map<String, dynamic>>> entries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final list = <Map<String, dynamic>>[];
      for (final e in decoded) {
        if (e is Map<String, dynamic>) list.add(e);
      }
      return list.reversed.toList();
    } catch (e) {
      debugPrint('[ErrorLog] Gagal baca log: $e');
      return [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('[ErrorLog] Gagal hapus log: $e');
    }
  }
}
