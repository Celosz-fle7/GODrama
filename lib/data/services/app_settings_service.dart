import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/drama_model.dart';

/// Posisi tonton terakhir sebuah drama, untuk resume.
class WatchProgress {
  final int episodeIndex;
  final int positionSeconds;
  final int durationSeconds;
  final DateTime updatedAt;

  const WatchProgress({
    this.episodeIndex = 0,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    required this.updatedAt,
  });

  double get episodeFraction => durationSeconds > 0
      ? (positionSeconds / durationSeconds).clamp(0.0, 1.0)
      : 0.0;

  Map<String, dynamic> toJson() {
    return {
      'episodeIndex': episodeIndex,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory WatchProgress.fromJson(Map<String, dynamic> json) {
    return WatchProgress(
      episodeIndex: (json['episodeIndex'] as num?)?.toInt() ?? 0,
      positionSeconds: (json['positionSeconds'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Satu entri riwayat: drama + progres tonton terakhirnya.
class HistoryEntry {
  final DramaModel drama;
  final WatchProgress progress;

  const HistoryEntry({required this.drama, required this.progress});

  HistoryEntry copyWith({DramaModel? drama, WatchProgress? progress}) {
    return HistoryEntry(
      drama: drama ?? this.drama,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toJson() {
    return {'drama': drama.toJson(), 'progress': progress.toJson()};
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      drama: DramaModel.fromJson(
        (json['drama'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      progress: WatchProgress.fromJson(
        (json['progress'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
    );
  }
}

class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  SharedPreferences? _prefs;
  bool _initialized = false;

  String _defaultQuality = '1080p';
  bool _autoPlayNext = true;
  String _userName = 'Tamu';
  String _userId = '';

  final List<HistoryEntry> _history = [];
  // Favorit menyimpan objek drama lengkap, bukan hanya ID — daftar favorit
  // harus bisa tampil tanpa bergantung pada feed lain.
  final List<DramaModel> _favorites = [];

  String get defaultQuality => _defaultQuality;
  bool get autoPlayNext => _autoPlayNext;
  String get userName => _userName;
  String get userId => _userId;
  List<DramaModel> get watchHistory =>
      List.unmodifiable(_history.map((e) => e.drama));
  List<HistoryEntry> get historyEntries => List.unmodifiable(_history);
  List<DramaModel> get favoriteDramas => List.unmodifiable(_favorites);
  Set<String> get favoriteIds => Set.unmodifiable(_favorites.map((d) => d.id));

  /// Muat semua state tersimpan. Dipanggil sekali dari main() sebelum runApp.
  /// Tanpa init, service tetap jalan (mode memori saja).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs!;
      _defaultQuality = p.getString('godrama_quality') ?? _defaultQuality;
      _autoPlayNext = p.getBool('godrama_autoplay') ?? _autoPlayNext;
      _userName = p.getString('godrama_username') ?? _userName;

      // Migrasi sekali jalan dari pengaturan lama yang sudah dihapus:
      // Mode Hemat Kuota dulu hanya memaksa 480p — pindahkan ke kualitas.
      if (p.getBool('godrama_data_saver') ?? false) {
        _defaultQuality = '480p';
        await p.setString('godrama_quality', '480p');
      }
      await p.remove('godrama_data_saver');
      await p.remove('godrama_avatar');
      // Nama default lama 'GoDrama VIP' mengklaim status VIP yang tidak
      // ada — ganti ke 'Tamu' bila user belum pernah mengganti namanya.
      if (_userName == 'GoDrama VIP') {
        _userName = 'Tamu';
        await p.setString('godrama_username', 'Tamu');
      }

      // ID user dibuat sekali per instalasi, lalu dipakai seterusnya.
      _userId = p.getString('godrama_userid') ?? '';
      if (_userId.isEmpty) {
        final rand = Random.secure();
        _userId = 'GD-${List.generate(6, (_) => rand.nextInt(10)).join()}';
        await p.setString('godrama_userid', _userId);
      }

      final historyRaw = p.getString('godrama_history');
      if (historyRaw != null && historyRaw.isNotEmpty) {
        final decoded = jsonDecode(historyRaw) as List;
        _history.addAll(
          decoded
              .whereType<Map>()
              .map((m) => HistoryEntry.fromJson(m.cast<String, dynamic>()))
              .where((e) => e.drama.id.isNotEmpty),
        );
      }

      final favRaw = p.getString('godrama_favorites');
      if (favRaw != null && favRaw.isNotEmpty) {
        final decoded = jsonDecode(favRaw) as List;
        _favorites.addAll(
          decoded
              .whereType<Map>()
              .map((m) => DramaModel.fromJson(m.cast<String, dynamic>()))
              .where((d) => d.id.isNotEmpty),
        );
      }
    } catch (e) {
      // Gagal baca storage bukan fatal: lanjut mode memori.
      debugPrint('[AppSettingsService] Gagal baca storage: $e');
    }
    notifyListeners();
  }

  Future<void> _persistHistory() async {
    final encoded = jsonEncode(_history.map((e) => e.toJson()).toList());
    await _prefs?.setString('godrama_history', encoded);
  }

  Future<void> _persistFavorites() async {
    final encoded = jsonEncode(_favorites.map((d) => d.toJson()).toList());
    await _prefs?.setString('godrama_favorites', encoded);
  }

  void setDefaultQuality(String quality) {
    _defaultQuality = quality;
    _prefs?.setString('godrama_quality', quality);
    notifyListeners();
  }

  void toggleAutoPlayNext(bool enabled) {
    _autoPlayNext = enabled;
    _prefs?.setBool('godrama_autoplay', enabled);
    notifyListeners();
  }

  void updateProfileName(String name) {
    _userName = name;
    _prefs?.setString('godrama_username', name);
    notifyListeners();
  }

  WatchProgress? progressFor(String dramaId) {
    for (final entry in _history) {
      if (entry.drama.id == dramaId) return entry.progress;
    }
    return null;
  }

  void addToWatchHistory(DramaModel drama) {
    final existingIndex = _history.indexWhere((e) => e.drama.id == drama.id);
    // Entri lama dipertahankan progresnya, hanya naik ke paling atas
    // dan metadata dramanya diperbarui.
    final keptProgress = existingIndex >= 0
        ? _history[existingIndex].progress
        : WatchProgress(updatedAt: DateTime.now());
    if (existingIndex >= 0) _history.removeAt(existingIndex);
    _history.insert(
      0,
      HistoryEntry(drama: drama, progress: keptProgress),
    );
    if (_history.length > 50) {
      _history.removeLast();
    }
    _persistHistory();
    notifyListeners();
  }

  void updateWatchProgress(
    String dramaId, {
    required int episodeIndex,
    required int positionSeconds,
    required int durationSeconds,
  }) {
    final index = _history.indexWhere((e) => e.drama.id == dramaId);
    if (index < 0) return;
    _history[index] = _history[index].copyWith(
      progress: WatchProgress(
        episodeIndex: episodeIndex,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        updatedAt: DateTime.now(),
      ),
    );
    _persistHistory();
    // Tanpa notifyListeners: progres berubah saat video jalan, dan tidak ada
    // UI yang perlu rebuild tiap simpan.
  }

  void clearWatchHistory() {
    _history.clear();
    _persistHistory();
    notifyListeners();
  }

  bool isFavorite(String dramaId) => _favorites.any((d) => d.id == dramaId);

  void toggleFavorite(DramaModel drama) {
    final index = _favorites.indexWhere((d) => d.id == drama.id);
    if (index >= 0) {
      _favorites.removeAt(index);
    } else {
      _favorites.insert(0, drama);
    }
    _persistFavorites();
    notifyListeners();
  }
}
