import 'package:flutter/foundation.dart';

import '../models/drama_model.dart';

class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  String _defaultQuality = '1080p';
  bool _dataSaverMode = false;
  bool _subtitlesEnabled = true;
  bool _autoPlayNext = true;
  bool _notificationsEnabled = true;
  String _selectedLanguage = 'Bahasa Indonesia';
  String _userName = 'GoDrama VIP';
  String _userId = 'GD-892401';
  int _avatarIndex = 0;

  final List<DramaModel> _watchHistory = [];
  final Set<String> _favoriteIds = {};

  String get defaultQuality => _dataSaverMode ? '480p' : _defaultQuality;
  bool get dataSaverMode => _dataSaverMode;
  bool get subtitlesEnabled => _subtitlesEnabled;
  bool get autoPlayNext => _autoPlayNext;
  bool get notificationsEnabled => _notificationsEnabled;
  String get selectedLanguage => _selectedLanguage;
  String get userName => _userName;
  String get userId => _userId;
  int get avatarIndex => _avatarIndex;
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

  void toggleAutoPlayNext(bool enabled) {
    _autoPlayNext = enabled;
    notifyListeners();
  }

  void toggleNotifications(bool enabled) {
    _notificationsEnabled = enabled;
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

  void setAvatarIndex(int index) {
    _avatarIndex = index;
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
