import 'package:flutter/foundation.dart';

import '../models/drama_model.dart';

class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  String _defaultQuality = '1080p';
  bool _dataSaverMode = false;
  bool _subtitlesEnabled = true;
  String _selectedLanguage = 'Bahasa Indonesia';
  String _userName = 'GoDrama VIP';
  String _userId = 'GD-892401';

  final List<DramaModel> _watchHistory = [];
  final Set<String> _favoriteIds = {};

  String get defaultQuality => _dataSaverMode ? '480p' : _defaultQuality;
  bool get dataSaverMode => _dataSaverMode;
  bool get subtitlesEnabled => _subtitlesEnabled;
  String get selectedLanguage => _selectedLanguage;
  String get userName => _userName;
  String get userId => _userId;
  List<DramaModel> get watchHistory => List.unmodifiable(_watchHistory);
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  void setDefaultQuality(String quality) {
    _defaultQuality = quality;
    notifyListeners();
  }

  void toggleDataSaver(bool enabled) {
    _dataSaverMode = enabled;
    notifyListeners();
  }

  void toggleSubtitles(bool enabled) {
    _subtitlesEnabled = enabled;
    notifyListeners();
  }

  void setSelectedLanguage(String lang) {
    _selectedLanguage = lang;
    notifyListeners();
  }

  void updateProfileName(String name) {
    _userName = name;
    notifyListeners();
  }

  void addToWatchHistory(DramaModel drama) {
    _watchHistory.removeWhere((d) => d.id == drama.id);
    _watchHistory.insert(0, drama);
    if (_watchHistory.length > 50) {
      _watchHistory.removeLast();
    }
    notifyListeners();
  }

  void clearWatchHistory() {
    _watchHistory.clear();
    notifyListeners();
  }

  bool isFavorite(String dramaId) => _favoriteIds.contains(dramaId);

  void toggleFavorite(DramaModel drama) {
    if (_favoriteIds.contains(drama.id)) {
      _favoriteIds.remove(drama.id);
    } else {
      _favoriteIds.add(drama.id);
    }
    notifyListeners();
  }
}
