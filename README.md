# GoDrama

GoDrama is a modern Flutter short drama streaming app inspired by the UI/UX
architecture of JoyReels: vertical For You feed, Home tabs, player with
episode drawer, search, My List, and profile — backed by the ShortTV
(MovieBox) API with per-install identity.

## Features
- **TikTok-style For You Feed**: vertical full-screen swipeable reels,
  paged loading, next-reel preload, seamless quality switching.
- **Dynamic Home Experience**: hero carousel, 4 category tabs
  (Untuk Anda / Terbaru / Terpanas / Peringkat), paged grid with
  scroll-to-load-more.
- **Dedicated Player Screen**: episode drawer, auto-next (respects the
  auto-play setting), resume from saved episode + position, lazy episode
  loading (first chunk plays immediately, rest loads in background),
  real quality picker (only resolutions the episode actually offers).
- **Search**: debounced search with paged results; trending landing from
  a single cached sections request.
- **My List & Profile**: watch history (real episode + progress),
  favorites (full objects), per-install user ID — all persisted locally.
- **Honest data**: no fabricated ratings, view counts, tags, or subtitles.
  Empty means the server didn't provide it.
- **Error handling**: error UI + retry in player, reels, Home, and Search;
  local error log in Profile (last 20 entries).
- **Lean**: 12 bundled assets + 8 fonts, R8 minify + resource shrinking,
  single shared HTTP client with connection reuse.

## Getting Started
```bash
flutter pub get
flutter run
```

CI builds on Flutter 3.22.0 (see `.github/workflows/build_apk.yml`) and
runs `flutter analyze` before building the release APK.

## Release signing
Release builds use `android/key.properties` when present (see
`android/key.properties.example`); without it the build falls back to
debug signing so CI still works. Never commit the keystore or passwords.

## Versioning
`pubspec.yaml`, `version.json`, and the Profile/About labels all read the
real installed version. Creating a tag (e.g. `v1.0.14`) triggers CI to
build the APK and publish a GitHub Release, which makes the
`download_url` in `version.json` live for the in-app updater.
