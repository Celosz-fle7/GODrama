import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
import '../../data/services/app_settings_service.dart';
import '../../widgets/episode_drawer.dart';

class PlayerScreen extends StatefulWidget {
  final DramaModel drama;
  final int initialEpisodeIndex;

  const PlayerScreen({
    super.key,
    required this.drama,
    this.initialEpisodeIndex = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late int _currentEpisodeIndex;
  VideoPlayerController? _controller;
  bool _showControls = true;
  List<EpisodeModel> _episodes = [];
  bool _isLoadingEpisodes = false;
  String _selectedQuality = '1080p';
  double _playbackSpeed = 1.0;
  // Error state: gagal load daftar episode / gagal init video.
  bool _episodesFailed = false;
  String? _videoError;
  // Fetch sisa episode di latar belakang (setelah chunk pertama main).
  // Future yang sama dipakai bersama: tombol Next yang ditekan saat fetch
  // berjalan ikut menunggu hasilnya, bukan fetch kedua.
  Future<void>? _remainingFuture;
  bool _remainingExhausted = false;
  // Token pergantian kualitas: hanya switch terbaru yang boleh menukar
  // controller (ketukan ganda cepat tidak menimpa satu sama lain).
  int _qualitySwitchToken = 0;

  // Scrubber state
  bool _isDraggingScrubber = false;
  double _scrubberValue = 0.0;
  Timer? _controlsTimer;
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    _currentEpisodeIndex = widget.initialEpisodeIndex;
    _selectedQuality = AppSettingsService.instance.defaultQuality;
    _episodes = widget.drama.episodes;
    // Lanjutkan dari progres tersimpan bila pemanggil tidak minta episode
    // tertentu (mis. dibuka dari Home/Search/Favorit, bukan dari Riwayat).
    if (_currentEpisodeIndex == 0) {
      final saved = AppSettingsService.instance.progressFor(widget.drama.id);
      if (saved != null && saved.episodeIndex > 0) {
        _currentEpisodeIndex = saved.episodeIndex;
      }
    }
    _setupVideo();
    _resetControlsTimer();
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (_showControls) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _controller?.value.isPlaying == true) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  /// Simpan episode + posisi saat ini agar bisa dilanjutkan nanti.
  void _saveProgress() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    AppSettingsService.instance.updateWatchProgress(
      widget.drama.id,
      episodeIndex: _currentEpisodeIndex,
      positionSeconds: controller.value.position.inSeconds,
      durationSeconds: duration.inSeconds,
    );
  }

  void _retryVideo() {
    setState(() {
      _videoError = null;
      _episodesFailed = false;
    });
    _setupVideo();
  }

  Future<void> _setupVideo() async {
    if (mounted) {
      setState(() {
        _episodesFailed = false;
        _videoError = null;
      });
    }
    if (_episodes.isEmpty && !_isLoadingEpisodes) {
      _isLoadingEpisodes = true;
      // Lazy: chunk pertama saja (10 episode) sebelum frame pertama.
      // Kecuali resume di episode jauh — ambil sampai episode itu.
      final targetEps = widget.drama.totalEpisodes > 0
          ? widget.drama.totalEpisodes
          : 100;
      var firstEnd = 10;
      if (_currentEpisodeIndex >= firstEnd) {
        firstEnd = _currentEpisodeIndex + 1;
      }
      if (firstEnd > targetEps) firstEnd = targetEps;
      final liveEps = await ShortTvService.instance.fetchShortTvEpisodes(
        widget.drama.id,
        startPos: 1,
        endPosition: firstEnd,
      );
      _isLoadingEpisodes = false;
      if (!mounted) return;
      if (liveEps.isNotEmpty) {
        setState(() {
          _episodes = liveEps;
        });
      } else {
        // Gagal load episode: tampilkan error + retry, bukan spinner selamanya.
        setState(() {
          _episodesFailed = true;
        });
        return;
      }
    }

    if (_episodes.isEmpty) return;
    _currentEpisodeIndex = _currentEpisodeIndex.clamp(0, _episodes.length - 1);
    final ep = _episodes[_currentEpisodeIndex];

    // Catat ke riwayat tontonan (progres lama dipertahankan).
    AppSettingsService.instance.addToWatchHistory(widget.drama);

    if (!ep.resolutions.containsKey(_selectedQuality) &&
        ep.resolutions.isNotEmpty) {
      _selectedQuality = ep.resolutions.keys.first;
    }
    final streamUrl = ep.getUrlForQuality(_selectedQuality);

    _positionTimer?.cancel();
    _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl))
      ..initialize()
          .then((_) {
            if (mounted) {
              // Resume posisi tersimpan bila episode ini yang terakhir ditonton.
              // Posisi di 5 detik terakhir dianggap sudah tamat: mulai dari 0.
              final saved = AppSettingsService.instance
                  .progressFor(widget.drama.id);
              final duration = _controller!.value.duration;
              final shouldResume =
                  saved != null &&
                  saved.episodeIndex == _currentEpisodeIndex &&
                  saved.positionSeconds > 0 &&
                  duration > Duration.zero &&
                  saved.positionSeconds < duration.inSeconds - 5;
              if (shouldResume) {
                _controller?.seekTo(
                  Duration(seconds: saved.positionSeconds),
                );
              }
              _controller?.setPlaybackSpeed(_playbackSpeed);
              _controller?.play();
              setState(() {});

              // Auto play episode berikutnya ketika episode saat ini tamat
              _controller?.addListener(_checkVideoEnd);

              // Monitor posisi scrubber secara berkala
              _positionTimer = Timer.periodic(
                const Duration(milliseconds: 250),
                (_) {
                  if (mounted &&
                      _controller != null &&
                      _controller!.value.isInitialized) {
                    if (!_isDraggingScrubber) {
                      setState(() {});
                    }
                  }
                },
              );

              // Simpan progres awal episode ini. Saat resume, jangan timpa
              // posisi tersimpan (seek masih berjalan, posisi terbaca 0).
              if (!shouldResume) _saveProgress();

              // Video sudah main: ambil sisa episode di latar belakang
              // (drawer + tombol next jadi lengkap tanpa menunda playback).
              _loadRemainingEpisodes();
            }
          })
          .catchError((err) {
            debugPrint('[PlayerScreen] Video init error: $err');
            if (mounted) {
              setState(() {
                _videoError =
                    'Video gagal dimuat. Periksa koneksi lalu coba lagi.';
              });
            }
          });
  }

  /// Ambil episode di luar chunk pertama, di latar belakang setelah video
  /// mulai main. Tidak memblokir playback; drawer terisi bertahap.
  /// Bila fetch sudah berjalan, pemanggil ikut menunggu Future yang sama.
  Future<void> _loadRemainingEpisodes() {
    if (_remainingExhausted) return Future.value();
    final targetEps = widget.drama.totalEpisodes > 0
        ? widget.drama.totalEpisodes
        : 100;
    if (_episodes.length >= targetEps) return Future.value();
    _remainingFuture ??= _fetchRemainingEpisodes(targetEps).whenComplete(() {
      _remainingFuture = null;
    });
    return _remainingFuture!;
  }

  Future<void> _fetchRemainingEpisodes(int targetEps) async {
    final rest = await ShortTvService.instance.fetchShortTvEpisodes(
      widget.drama.id,
      startPos: _episodes.length + 1,
      endPosition: targetEps,
    );
    if (rest.isEmpty) {
      _remainingExhausted = true;
      return;
    }
    if (!mounted) return;
    final known = _episodes.map((e) => e.episodeNumber).toSet();
    final fresh = rest.where((e) => !known.contains(e.episodeNumber)).toList();
    if (fresh.isEmpty) {
      _remainingExhausted = true;
      return;
    }
    setState(() {
      _episodes.addAll(fresh);
      _episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    });
  }

  void _checkVideoEnd() {
    if (_controller != null &&
        _controller!.value.isInitialized &&
        !_controller!.value.isPlaying &&
        _controller!.value.position >= _controller!.value.duration &&
        _controller!.value.duration > Duration.zero) {
      // Auto-next menghormati pengaturan "Putar Otomatis Episode Berikutnya".
      // Bila mati, video diam di akhir episode; user menekan Next sendiri.
      if (AppSettingsService.instance.autoPlayNext) {
        _playNextEpisode();
      }
    }
  }

  /// Ganti kualitas tanpa henti: controller lama tetap memutar selama
  /// controller baru di-init; begitu siap, posisi disamakan lalu ditukar.
  /// Listener auto-next dipasang ke controller baru; timer posisi tidak
  /// disentuh (membaca _controller yang aktif). Gagal init = kualitas
  /// lama tetap jalan + snackbar, bukan panel error.
  Future<void> _changeQuality(String quality) async {
    if (_selectedQuality == quality || _controller == null) return;
    if (_episodes.isEmpty) return;
    final ep = _episodes[_currentEpisodeIndex.clamp(0, _episodes.length - 1)];
    final newUrl = ep.getUrlForQuality(quality);
    final oldController = _controller!;
    final switchToken = ++_qualitySwitchToken;

    final newController = VideoPlayerController.networkUrl(Uri.parse(newUrl));
    try {
      await newController.initialize();
    } catch (e) {
      debugPrint('[PlayerScreen] Gagal init kualitas $quality: $e');
      newController.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mengganti kualitas, kualitas lama dipakai'),
          ),
        );
      }
      return;
    }
    if (!mounted || switchToken != _qualitySwitchToken) {
      newController.dispose();
      return;
    }

    final pos = oldController.value.position;
    await newController.seekTo(pos);
    newController.setPlaybackSpeed(_playbackSpeed);
    final wasPlaying = oldController.value.isPlaying;
    if (wasPlaying) newController.play();
    newController.addListener(_checkVideoEnd);
    setState(() {
      _selectedQuality = quality;
      _videoError = null;
      _controller = newController;
    });
    oldController.removeListener(_checkVideoEnd);
    oldController.dispose();
  }

  void _changeSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _controller?.setPlaybackSpeed(speed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 800),
        backgroundColor: const Color(0xFF1E232E),
        content: Text('Kecepatan video: ${speed}x'),
      ),
    );
  }

  @override
  void dispose() {
    _saveProgress();
    _controlsTimer?.cancel();
    _positionTimer?.cancel();
    _controller?.removeListener(_checkVideoEnd);
    _controller?.dispose();
    super.dispose();
  }

  void _selectEpisode(int index) {
    if (index == _currentEpisodeIndex || _episodes.isEmpty) return;
    _saveProgress();
    setState(() {
      _currentEpisodeIndex = index.clamp(0, _episodes.length - 1);
    });
    _setupVideo();
  }

  Future<void> _playNextEpisode() async {
    if (_currentEpisodeIndex < _episodes.length - 1) {
      _selectEpisode(_currentEpisodeIndex + 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          backgroundColor: const Color(0xFF1E232E),
          content: Text('Memutar Episode ${_currentEpisodeIndex + 1}...'),
        ),
      );
      return;
    }
    // Di ujung list yang sudah ter-load: sisa episode mungkin masih
    // di-fetch di latar belakang. Tunggu dulu sebelum menyatakan habis.
    final targetEps = widget.drama.totalEpisodes > 0
        ? widget.drama.totalEpisodes
        : 100;
    if (_episodes.length < targetEps && !_remainingExhausted) {
      await _loadRemainingEpisodes();
      if (!mounted) return;
      if (_currentEpisodeIndex < _episodes.length - 1) {
        _selectEpisode(_currentEpisodeIndex + 1);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 1),
        backgroundColor: Color(0xFF1E232E),
        content: Text('Ini adalah episode terakhir.'),
      ),
    );
  }

  void _playPreviousEpisode() {
    if (_currentEpisodeIndex > 0) {
      _selectEpisode(_currentEpisodeIndex - 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          backgroundColor: const Color(0xFF1E232E),
          content: Text('Memutar Episode ${_currentEpisodeIndex + 1}...'),
        ),
      );
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller?.value.isPlaying == true) {
        _controller?.pause();
      } else {
        _controller?.play();
      }
    });
    _resetControlsTimer();
  }

  void _openEpisodeDrawer() {
    final totalEps = _episodes.isNotEmpty
        ? _episodes.length
        : widget.drama.totalEpisodes;

    EpisodeDrawer.show(
      context,
      drama: widget.drama.copyWith(
        episodes: _episodes,
        totalEpisodes: totalEps,
      ),
      currentEpisodeIndex: _currentEpisodeIndex,
      onEpisodeSelected: (index) {
        _selectEpisode(index);
      },
    );
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        // Hanya resolusi yang benar-benar punya URL untuk episode ini.
        final ep = _episodes[_currentEpisodeIndex.clamp(
          0,
          _episodes.length - 1,
        )];
        final offered = ep.availableQualities;
        final qualities = offered.isNotEmpty ? offered : [_selectedQuality];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Pilih Kualitas Video',
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              ...qualities.map((q) {
                final isSel = q == _selectedQuality;
                return ListTile(
                  leading: Icon(
                    Icons.hd_rounded,
                    color: isSel ? AppColors.primary : Colors.white60,
                  ),
                  title: Text(
                    q == '1080p'
                        ? '$q (Full HD)'
                        : q == '720p'
                            ? '$q (HD)'
                            : q == '480p'
                                ? '$q (Hemat Kuota)'
                                : q,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      color: isSel ? AppColors.primary : Colors.white,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSel
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _changeQuality(q);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Kecepatan Putar',
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              ...speeds.map((s) {
                final isSel = s == _playbackSpeed;
                return ListTile(
                  title: Text(
                    s == 1.0 ? 'Normal (1.0x)' : '${s}x',
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      color: isSel ? AppColors.primary : Colors.white,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSel
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _changeSpeed(s);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildErrorPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _videoError ?? 'Gagal memuat daftar episode.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _retryVideo,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFav = AppSettingsService.instance.isFavorite(widget.drama.id);
    final totalEps = _episodes.isNotEmpty
        ? _episodes.length
        : widget.drama.totalEpisodes;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
          _resetControlsTimer();
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -300) {
              // Swipe Up -> Episode Berikutnya
              _playNextEpisode();
            } else if (details.primaryVelocity! > 300) {
              // Swipe Down -> Episode Sebelumnya
              _playPreviousEpisode();
            }
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. VIDEO PLAYER FULL SCREEN (LAYAR PENUH VERTIKAL)
            if (_controller != null && _controller!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              )
            else if (_videoError != null || _episodesFailed)
              _buildErrorPanel()
            else
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),

            // 2. GRADIENT OVERLAYS ATAS & BAWAH (ketika kontrol aktif)
            if (_showControls) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 140,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 220,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.92),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // 3. TOP APP BAR (ketika kontrol aktif)
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.drama.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                totalEps > 0
                                    ? 'Episode ${_currentEpisodeIndex + 1} / $totalEps'
                                    : 'Episode ${_currentEpisodeIndex + 1}',
                                style: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Speed Pill
                        GestureDetector(
                          onTap: _showSpeedPicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white24,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // Quality Pill
                        GestureDetector(
                          onTap: _showQualityPicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            margin: const EdgeInsets.only(left: 4, right: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              _selectedQuality,
                              style: const TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 4. CENTER PLAY/PAUSE (ketika kontrol aktif)
            if (_showControls)
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 42,
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: _currentEpisodeIndex > 0
                            ? Colors.white
                            : Colors.white24,
                      ),
                      onPressed: _currentEpisodeIndex > 0
                          ? _playPreviousEpisode
                          : null,
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      iconSize: 64,
                      icon: Icon(
                        _controller?.value.isPlaying == true
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      iconSize: 42,
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: _currentEpisodeIndex < totalEps - 1
                            ? Colors.white
                            : Colors.white24,
                      ),
                      onPressed: _currentEpisodeIndex < totalEps - 1
                          ? _playNextEpisode
                          : null,
                    ),
                  ],
                ),
              ),

            // 5. BOTTOM CONTROLS & EPISODE DRAWER BUTTON (ketika kontrol aktif)
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Scrubber & Duration Row
                        Row(
                          children: [
                            Text(
                              _controller != null &&
                                      _controller!.value.isInitialized
                                  ? _formatDuration(_controller!.value.position)
                                  : '00:00',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFamily: 'Urbanist',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  thumbColor: AppColors.primary,
                                  trackHeight: 3,
                                  activeTrackColor: AppColors.primary,
                                  inactiveTrackColor: Colors.white24,
                                ),
                                child: Slider(
                                  value: _isDraggingScrubber
                                      ? _scrubberValue
                                      : (_controller != null &&
                                              _controller!.value.isInitialized)
                                          ? _controller!.value.position
                                              .inMilliseconds
                                              .toDouble()
                                              .clamp(
                                                0.0,
                                                _controller!.value.duration
                                                    .inMilliseconds
                                                    .toDouble(),
                                              )
                                          : 0.0,
                                  min: 0.0,
                                  max: (_controller != null &&
                                          _controller!.value.isInitialized &&
                                          _controller!.value.duration
                                                  .inMilliseconds >
                                              0)
                                      ? _controller!.value.duration
                                          .inMilliseconds
                                          .toDouble()
                                      : 1.0,
                                  onChangeStart: (val) {
                                    setState(() {
                                      _isDraggingScrubber = true;
                                      _scrubberValue = val;
                                    });
                                  },
                                  onChanged: (val) {
                                    setState(() {
                                      _scrubberValue = val;
                                    });
                                  },
                                  onChangeEnd: (val) {
                                    setState(() {
                                      _isDraggingScrubber = false;
                                    });
                                    _controller?.seekTo(
                                      Duration(milliseconds: val.toInt()),
                                    );
                                    _resetControlsTimer();
                                  },
                                ),
                              ),
                            ),
                            Text(
                              _controller != null &&
                                      _controller!.value.isInitialized
                                  ? _formatDuration(_controller!.value.duration)
                                  : '00:00',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFamily: 'Urbanist',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Action Row: Daftar Episode Button & Favorite
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: _openEpisodeDrawer,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.divider,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.playlist_play_rounded,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      totalEps > 0
                                          ? 'Daftar Episode ($totalEps Ep)'
                                          : 'Daftar Episode',
                                      style: const TextStyle(
                                        fontFamily: 'Urbanist',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                      color: Colors.white60,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            IconButton(
                              icon: Icon(
                                isFav
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: isFav ? AppColors.primary : Colors.white,
                                size: 24,
                              ),
                              onPressed: () {
                                setState(() {
                                  AppSettingsService.instance
                                      .toggleFavorite(widget.drama);
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
