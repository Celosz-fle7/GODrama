// Hanya aset yang benar-benar dipakai di UI. Konstanta mati (ikon yang
// tidak pernah dirender) dihapus — file-nya juga dihapus dari repo.
class AppAssets {
  AppAssets._();

  // Navigation Icons
  static const String navDiscoverActive =
      'assets/images/home/ic_discover_active.png';
  static const String navDiscoverInactive =
      'assets/images/home/ic_discover_inactive.png';
  static const String navForYouActive =
      'assets/images/home/ic_for_you_active.png';
  static const String navForYouInactive =
      'assets/images/home/ic_for_you_inactive.png';
  static const String navMyListActive =
      'assets/images/home/ic_my_list_active.png';
  static const String navMyListInactive =
      'assets/images/home/ic_my_list_inactive.png';
  static const String navProfileActive =
      'assets/images/home/ic_profile_active.png';
  static const String navProfileInactive =
      'assets/images/home/ic_profile_inactive.png';

  // Home Icons & SVGs
  static const String icSearch = 'assets/images/home/ic_search.svg';

  // Player Icons & SVGs
  static const String btnSeriesList =
      'assets/images/player/btn_series_list.svg';

  // Animations (Lottie)
  static const String animSeriesPlaying =
      'assets/images/player/anim_series_playing.json';

  // Profile & My List
  static const String icAvatar = 'assets/images/profile/ic_avatar.svg';
}
