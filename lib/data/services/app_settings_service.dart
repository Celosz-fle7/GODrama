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
  // Riwayat impresi cuplikan (ID drama -> timestamp ms saat di-swipe/dilihat).
  // Disimpan lokal agar saat buka aplikasi, drama yang baru saja di-swipe tidak muncul lagi.
  final Map<String, int> _seenPreviews = {};

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

      final seenRaw = p.getString('godrama_seen_previews');
      if (seenRaw != null && seenRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(seenRaw) as Map;
          final now = DateTime.now().millisecondsSinceEpoch;
          decoded.forEach((key, val) {
            // Muat impresi cuplikan yang umurnya < 24 jam (86.400.000 ms)
            if (val is num && (now - val.toInt()) < 86400000) {
              _seenPreviews[key.toString()] = val.toInt();
            }
          });
        } catch (_) {}
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

  Future<void> _persistSeenPreviews() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Bersihkan entri yang sudah kadaluarsa (> 24 jam)
    _seenPreviews.removeWhere((_, ts) => (now - ts) >= 86400000);
    // Batasi kapasitas maksimal 300 entri terbaru
    if (_seenPreviews.length > 300) {
      final sortedKeys = _seenPreviews.keys.toList()
        ..sort((a, b) => _seenPreviews[a]!.compareTo(_seenPreviews[b]!));
      for (int i = 0; i < sortedKeys.length - 300; i++) {
        _seenPreviews.remove(sortedKeys[i]);
      }
    }
    await _prefs?.setString('godrama_seen_previews', jsonEncode(_seenPreviews));
  }

  /// Catat drama sebagai sudah pernah di-swipe / diintip di cuplikan feed For You.
  void recordPreviewImpression(String dramaId) {
    if (dramaId.isEmpty) return;
    _seenPreviews[dramaId] = DateTime.now().millisecondsSinceEpoch;
    _persistSeenPreviews();
  }

  /// Memeriksa apakah cuplikan drama sedang dalam masa tahan (cooldown 12 jam sejak di-swipe).
  bool isPreviewOnCooldown(String dramaId, {int cooldownHours = 12}) {
    final ts = _seenPreviews[dramaId];
    if (ts == null) return false;
    final elapsedHours =
        (DateTime.now().millisecondsSinceEpoch - ts) / (1000 * 3600);
    return elapsedHours < cooldownHours;
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

  /// Memeriksa apakah sebuah drama harus disembunyikan sementara atau permanen dari feed For You:
  /// 1. Ditonton >= 10 episode: Disembunyikan permanen (sudah tamat / tontonan serius, ada di Riwayat).
  /// 2. Ditonton episode 1 s/d 9: Ditahan (cooldown) selama 24 jam sejak tontonan terakhir.
  /// 3. Belum ditonton tapi sudah pernah di-swipe lewat di For You: Ditahan (cooldown) selama 12 jam.
  /// 4. Belum pernah muncul di layar: Tetap tampil (fresh discovery).
  bool shouldSuppressFromForYou(String dramaId) {
    final progress = progressFor(dramaId);
    if (progress != null) {
      // Kriteria 1: Nonton >= 10 episode -> Sembunyikan permanen dari For You
      if (progress.episodeIndex >= 10) return true;

      // Kriteria 2: Nonton episode 1-9 -> Cooldown 24 jam
      if (progress.episodeIndex >= 1) {
        final hoursSince = DateTime.now().difference(progress.updatedAt).inHours;
        if (hoursSince < 24) return true;
      }
    }

    // Kriteria 3: Belum ditonton tapi sudah pernah di-swipe lewat di For You -> Cooldown 12 jam
    if (isPreviewOnCooldown(dramaId, cooldownHours: 12)) {
      return true;
    }

    return false;
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
