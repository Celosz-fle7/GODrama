import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
import '../../data/services/app_settings_service.dart';
import '../../widgets/episode_drawer.dart';
import '../player/player_screen.dart';

class ForYouScreen extends StatefulWidget {
  final bool isActive;

  const ForYouScreen({super.key, this.isActive = true});

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  final PageController _pageController = PageController();
  List<DramaModel> _dramas = [];
  int _activeDramaIndex = 0;
  bool _isLoading = true;
  // Pagination: halaman 1 dulu (cepat), halaman berikut saat swipe
  // mendekati akhir feed.
  final Set<String> _seenIds = {};
  int _currentPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadLiveShortDramas();
  }

  @override
  void didUpdateWidget(covariant ForYouScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      setState(() {});
    }
  }

  Future<void> _loadLiveShortDramas() async {
    final live = await ShortTvService.instance.fetchForYouPage(1);
    if (mounted) {
      _seenIds
        ..clear()
        ..addAll(live.map((d) => d.id));
      setState(() {
        _dramas = live;
        _currentPage = 1;
        _hasMore = live.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    final nextPage = _currentPage + 1;
    final live = await ShortTvService.instance.fetchForYouPage(nextPage);
    if (!mounted) return;
    final fresh = live.where((d) => _seenIds.add(d.id)).toList();
    setState(() {
      _dramas.addAll(fresh);
      _currentPage = nextPage;
      // Feed punya halaman 1-3; halaman kosong = habis.
      _hasMore = live.isNotEmpty && nextPage < 3;
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 14),
              Text(
                'Memuat Cuplikan Drama Indonesia...',
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_dramas.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: AppColors.textMuted,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'Gagal memuat feed cuplikan',
                style: TextStyle(color: Colors.white, fontFamily: 'Urbanist'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadLiveShortDramas();
                },
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _dramas.length,
        onPageChanged: (index) {
          setState(() {
            _activeDramaIndex = index;
          });
          if (index >= _dramas.length - 3) _loadMore();
        },
        itemBuilder: (context, index) {
          final drama = _dramas[index];
          final isCurrent = widget.isActive && (index == _activeDramaIndex);
          return _ReelItem(
            key: ValueKey('${drama.id}_${widget.isActive}'),
            drama: drama,
            isActive: isCurrent,
            isNext: widget.isActive && (index == _activeDramaIndex + 1),
          );
        },
      ),
    );
  }
}

class _ReelItem extends StatefulWidget {
  final DramaModel drama;
  final bool isActive;
  // Reel berikutnya: videonya di-init lebih awal (preload) tapi tidak
  // diputar sampai jadi aktif — swipe ke reel berikut jadi instan.
  final bool isNext;

  const _ReelItem({
    super.key,
    required this.drama,
    required this.isActive,
    this.isNext = false,
  });

  @override
  State<_ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<_ReelItem> {
  VideoPlayerController? _videoController;
  bool _isPlaying = true;
  List<EpisodeModel> _episodes = [];
  bool _isLoadingEpisodes = false;
  // Init video sedang berjalan: jangan init ulang (then() yang tertunda
  // akan memutarnya bila reel sudah aktif).
  bool _isInitializingVideo = false;

  // Menu Pengaturan Cuplikan (diakses via Titik 3)
  String _selectedQuality = '1080p';
  double _playbackSpeed = 1.0;
  bool _clearViewMode = false;
  // Gagal load episode / init video cuplikan.
  bool _videoError = false;
  // Token pergantian kualitas: hanya switch terbaru yang boleh menukar
  // controller (ketukan ganda cepat tidak menimpa satu sama lain).
  int _qualitySwitchToken = 0;

  // Scrubber State
  bool _isDraggingScrubber = false;
  double _scrubberValue = 0.0;
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    _selectedQuality = AppSettingsService.instance.defaultQuality;
    _episodes = widget.drama.episodes;
    if (widget.isActive || widget.isNext) {
      _initTeaserVideo();
    }
  }

  @override
  void didUpdateWidget(covariant _ReelItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // Jadi aktif: putar controller yang sudah di-preload, atau init baru.
      if (_videoController != null &&
          _videoController!.value.isInitialized) {
        _videoController?.play();
        _startProgressTracker();
        setState(() => _isPlaying = true);
      } else {
        _initTeaserVideo();
      }
    } else if (widget.isNext && !oldWidget.isNext) {
      // Jadi reel berikut: preload (init saja, tanpa play).
      _initTeaserVideo();
    } else if (!widget.isActive && !widget.isNext && oldWidget.isActive) {
      _disposeVideo();
    }
  }

  /// Memutar cuplikan (Episode 1) secara looping sebagai teaser.
  /// Hanya episode 1 yang di-fetch — daftar episode lengkap tidak
  /// dibutuhkan untuk cuplikan (player mengambil sendiri saat dibuka).
  Future<void> _initTeaserVideo() async {
    if (_isInitializingVideo) return;
    if (_videoController != null &&
        _videoController!.value.isInitialized) {
      return;
    }
    if (mounted) setState(() => _videoError = false);
    if (_episodes.isEmpty && !_isLoadingEpisodes) {
      _isLoadingEpisodes = true;
      final liveEps = await ShortTvService.instance.fetchShortTvEpisodes(
        widget.drama.id,
        endPosition: 1,
      );
      _isLoadingEpisodes = false;
      if (mounted && liveEps.isNotEmpty) {
        setState(() {
          _episodes = liveEps;
        });
      }
    }

    if (_episodes.isEmpty) {
      if (mounted) setState(() => _videoError = true);
      return;
    }
    // Cuplikan For You selalu memainkan Episode 1 (Teaser)
    final teaserEp = _episodes.first;

    final streamUrl = teaserEp.getUrlForQuality(_selectedQuality);

    _disposeVideo();
    _isInitializingVideo = true;

    _videoController = VideoPlayerController.networkUrl(Uri.parse(streamUrl))
      ..initialize()
          .then((_) {
            _isInitializingVideo = false;
            if (mounted) {
              _videoController?.setPlaybackSpeed(_playbackSpeed);
              _videoController?.setLooping(true); // Looping cuplikan saja
              // Hanya putar bila reel ini aktif; reel preload diam sampai
              // gilirannya (didUpdateWidget yang memutarnya).
              if (widget.isActive) {
                _videoController?.play();
                setState(() {
                  _isPlaying = true;
                });
                _startProgressTracker();
              }
            }
          })
          .catchError((err) {
            _isInitializingVideo = false;
            debugPrint('[ForYouScreen] Video init error: $err');
            if (mounted) setState(() => _videoError = true);
          });
  }

  void _startProgressTracker() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted &&
          _videoController != null &&
          _videoController!.value.isInitialized) {
        if (!_isDraggingScrubber) {
          setState(() {});
        }
      }
    });
  }

  void _disposeVideo() {
    _positionTimer?.cancel();
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_clearViewMode) {
      setState(() => _clearViewMode = false);
      return;
    }
    if (_videoController == null) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        _isPlaying = false;
      } else {
        _videoController!.play();
        _isPlaying = true;
      }
    });
  }

  /// Ganti kualitas tanpa henti: controller lama tetap memutar selama
  /// controller baru di-init; begitu siap, posisi disamakan lalu ditukar.
  /// Gagal init = kualitas lama tetap jalan + snackbar, bukan layar hitam.
  Future<void> _changeQuality(String quality) async {
    if (_selectedQuality == quality || _videoController == null) return;
    if (_episodes.isEmpty) return;
    final teaserEp = _episodes.first;
    final newUrl = teaserEp.getUrlForQuality(quality);
    final oldController = _videoController!;
    final switchToken = ++_qualitySwitchToken;

    final newController = VideoPlayerController.networkUrl(Uri.parse(newUrl));
    try {
      await newController.initialize();
    } catch (e) {
      debugPrint('[ForYouScreen] Gagal init kualitas $quality: $e');
      newController.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF1E232E),
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
    newController.setLooping(true);
    final wasPlaying = oldController.value.isPlaying;
    if (widget.isActive && wasPlaying) newController.play();
    setState(() {
      _selectedQuality = quality;
      _videoController = newController;
      _isPlaying = widget.isActive && wasPlaying;
    });
    oldController.dispose();
    if (widget.isActive) _startProgressTracker();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF1E232E),
        content: Text('Kualitas cuplikan diubah ke: $quality'),
      ),
    );
  }

  void _changePlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _videoController?.setPlaybackSpeed(speed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 800),
        backgroundColor: const Color(0xFF1E232E),
        content: Text('Kecepatan video: ${speed}x'),
      ),
    );
  }

  Future<void> _openFullPlayer([int startEpIndex = 0]) async {
    _disposeVideo();
    setState(() => _isPlaying = false);

    // Player mengambil daftar episodenya sendiri (lazy: chunk pertama
    // dulu, sisanya di latar belakang). Reel hanya punya episode 1 untuk
    // cuplikan — jangan lempar itu sebagai daftar lengkap.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          drama: widget.drama,
          initialEpisodeIndex: startEpIndex,
        ),
      ),
    );

    if (mounted && widget.isActive) {
      _initTeaserVideo();
    }
  }

  /// Buka drawer episode. Reel hanya memegang episode 1 (cuplikan), jadi
  /// daftar lengkap di-fetch dulu — dengan dialog loading singkat.
  Future<void> _showEpisodeDrawer() async {
    if (_episodes.length <= 1) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
      final full = await ShortTvService.instance.fetchShortTvEpisodes(
        widget.drama.id,
      );
      if (mounted) Navigator.of(context).pop();
      if (!mounted) return;
      if (full.isNotEmpty) {
        setState(() => _episodes = full);
      }
    }
    if (!mounted || _episodes.isEmpty) return;
    EpisodeDrawer.show(
      context,
      drama: widget.drama.copyWith(
        episodes: _episodes,
        totalEpisodes: _episodes.length,
      ),
      currentEpisodeIndex: 0,
      onEpisodeSelected: (selectedIdx) {
        _openFullPlayer(selectedIdx);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFav = AppSettingsService.instance.isFavorite(widget.drama.id);
    // Reel hanya memegang episode 1 untuk cuplikan — jumlah episode
    // diambil dari data drama (server), bukan panjang list cuplikan.
    final totalEps = widget.drama.totalEpisodes;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video Player atau Poster Banner Teaser
        GestureDetector(
          onTap: _togglePlayPause,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_videoController != null &&
                  _videoController!.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size.width,
                    height: _videoController!.value.size.height,
                    child: VideoPlayer(_videoController!),
                  ),
                )
              else
                CachedNetworkImage(
                  imageUrl: widget.drama.bannerUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.black),
                ),

              // Gradient Overlay Atas & Bawah
              if (!_clearViewMode)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                        Colors.black.withOpacity(0.88),
                      ],
                      stops: const [0.0, 0.45, 0.9],
                    ),
                  ),
                ),

              // Pause Icon Overlay
              if (!_isPlaying && !_clearViewMode)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Error cuplikan: video gagal dimuat, tawarkan coba lagi.
        if (_videoError &&
            (_videoController == null ||
                !_videoController!.value.isInitialized))
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.white70,
                    size: 40,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Video gagal dimuat',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Urbanist',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _initTeaserVideo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          ),

        // Seluruh UI Kontrol (Hanya Muncul jika !_clearViewMode)
        if (!_clearViewMode) ...[
          // Top Left: Badge Cuplikan Teaser & Gateway
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.movie_creation_rounded,
                    color: Color(0xFFFF3366),
                    size: 14,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Cuplikan Teaser',
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Left: Info Drama & Tombol Utama "Tonton Semua Episode"
          Positioned(
            left: 16,
            right: 84,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // TOMBOL UTAMA: "Tonton Semua Episode" (Kunci pengalaman pengguna)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openFullPlayer(0),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF3366), Color(0xFFFF5E3A)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3366).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          totalEps > 0
                              ? 'Tonton Semua Episode ($totalEps Ep)'
                              : 'Tonton Semua Episode',
                          style: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),

                // Title
                Text(
                  widget.drama.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                // Description
                Text(
                  widget.drama.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xCCFFFFFF),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          // Right Action Bar: Suka, Simpan, Series & MENU TITIK 3
          Positioned(
            right: 12,
            bottom: 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Suka / Like
                GestureDetector(
                  onTap: () {
                    AppSettingsService.instance.toggleFavorite(widget.drama);
                    setState(() {});
                  },
                  child: _buildActionItem(
                    icon: Icon(
                      isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: isFav ? const Color(0xFFFF3366) : Colors.white,
                      size: 28,
                    ),
                    label: isFav ? 'Disukai' : 'Suka',
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Series / Drawer Episode
                GestureDetector(
                  onTap: _showEpisodeDrawer,
                  child: _buildActionItem(
                    icon: SvgPicture.asset(
                      AppAssets.btnSeriesList,
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                    label: 'Episode',
                  ),
                ),
                const SizedBox(height: 16),

                // 3. MENU TITIK 3 (Kualitas, Speed, Mode Bersih, Bagikan)
                GestureDetector(
                  onTap: _showMoreOptionsMenu,
                  child: _buildActionItem(
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    label: 'Lainnya',
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Tombol Buka Player Penuh
                GestureDetector(
                  onTap: () => _openFullPlayer(0),
                  child: _buildActionItem(
                    icon: const Icon(
                      Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    label: 'Player',
                  ),
                ),
              ],
            ),
          ),

          // Video Progress Scrubber Bar Tipis di Paling Bawah
          if (_videoController != null && _videoController!.value.isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 12,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 0,
                    ),
                    trackHeight: 2.5,
                    activeTrackColor: const Color(0xFFFF3366),
                    inactiveTrackColor: Colors.white24,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _isDraggingScrubber
                        ? _scrubberValue
                        : _videoController!.value.position.inMilliseconds
                              .toDouble()
                              .clamp(
                                0.0,
                                _videoController!.value.duration.inMilliseconds
                                    .toDouble(),
                              ),
                    min: 0.0,
                    max:
                        _videoController!.value.duration.inMilliseconds
                                .toDouble() >
                            0
                        ? _videoController!.value.duration.inMilliseconds
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
                      _videoController?.seekTo(
                        Duration(milliseconds: val.toInt()),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],

        // Clear View Mode Indicator (Jika Aktif)
        if (_clearViewMode)
          Positioned(
            top: 48,
            right: 16,
            child: GestureDetector(
              onTap: () => setState(() => _clearViewMode = false),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Kembalikan Tampilan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionItem({required Widget icon, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Center(child: icon),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// MODAL TITIK 3 LENGKAP & MODERN (Kualitas, Kecepatan, Clear View, Share)
  void _showMoreOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Opsi & Pengaturan Cuplikan',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. Opsi Kualitas Video
                    ListTile(
                      leading: const Icon(
                        Icons.hd_rounded,
                        color: Color(0xFFFF3366),
                      ),
                      title: const Text(
                        'Kualitas Video',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Resolusi saat ini: $_selectedQuality',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white54,
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showQualityPickerSheet();
                      },
                    ),
                    const Divider(color: Colors.white10),

                    // 2. Opsi Kecepatan Putar (Playback Speed)
                    ListTile(
                      leading: const Icon(
                        Icons.speed_rounded,
                        color: Color(0xFFFF3366),
                      ),
                      title: const Text(
                        'Kecepatan Putar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Kecepatan saat ini: ${_playbackSpeed}x',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white54,
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showSpeedPickerSheet();
                      },
                    ),
                    const Divider(color: Colors.white10),

                    // 3. Opsi Mode Bersih (Clear View)
                    ListTile(
                      leading: const Icon(
                        Icons.visibility_off_rounded,
                        color: Colors.white70,
                      ),
                      title: const Text(
                        'Mode Layar Bersih',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Sembunyikan tombol UI untuk tampilan video jernih',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _clearViewMode = true;
                        });
                      },
                    ),
                    const Divider(color: Colors.white10),

                    // 4. Bagikan Drama (Share)
                    ListTile(
                      leading: const Icon(
                        Icons.share_rounded,
                        color: Colors.white70,
                      ),
                      title: const Text(
                        'Bagikan Cuplikan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Salin tautan drama ini ke clipboard',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        Clipboard.setData(
                          ClipboardData(
                            text:
                                'Nonton cuplikan "${widget.drama.title}" di GoDrama: https://github.com/Celosz-fle7/GODrama',
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: Duration(seconds: 1),
                            backgroundColor: Color(0xFF1E232E),
                            content: Text('Tautan cuplikan berhasil disalin!'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQualityPickerSheet() {
    // Hanya resolusi yang benar-benar punya URL untuk cuplikan ini.
    final offered = _episodes.isNotEmpty
        ? _episodes.first.availableQualities
        : <String>[];
    final available = offered.isNotEmpty ? offered : [_selectedQuality];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Pilih Kualitas Cuplikan',
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ...available.map((q) {
                  final isSelected = q == _selectedQuality;
                  return ListTile(
                    leading: Icon(
                      Icons.hd_rounded,
                      color: isSelected
                          ? const Color(0xFFFF3366)
                          : Colors.white60,
                    ),
                    title: Text(
                      q == '1080p'
                          ? '1080p Full HD (Kualitas Tinggi)'
                          : q == '720p'
                          ? '720p HD Standard (Rekomendasi)'
                          : q == '480p'
                          ? '480p Hemat Kuota (Cepat)'
                          : q,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFFFF3366)
                            : Colors.white,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFFFF3366),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeQuality(q);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpeedPickerSheet() {
    final speeds = [1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Kecepatan Putar Video',
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ...speeds.map((s) {
                  final isSelected = s == _playbackSpeed;
                  return ListTile(
                    title: Text(
                      '${s}x ${s == 1.0 ? '(Normal)' : ''}',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        color: isSelected
                            ? const Color(0xFFFF3366)
                            : Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Color(0xFFFF3366))
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _changePlaybackSpeed(s);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
