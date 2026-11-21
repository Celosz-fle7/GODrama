import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
import '../../data/services/app_settings_service.dart';
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

  void _onReelAutoNext(int fromIndex) {
    if (fromIndex == _activeDramaIndex &&
        _activeDramaIndex < _dramas.length - 1) {
      if (_activeDramaIndex < _dramas.length) {
        AppSettingsService.instance.recordPreviewImpression(
          _dramas[_activeDramaIndex].id,
        );
      }
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  Future<void> _loadLiveShortDramas() async {
    _currentPage = 1;
    final results = <DramaModel>[];
    int page = 1;

    // Smart Discovery Filter: Sembunyikan drama yang sudah ditonton (>=10 eps),
    // tahan drama yang baru dicoba (1-9 eps, cooldown 24 jam),
    // dan tahan drama yang baru saja di-swipe lewat di cuplikan (cooldown 12 jam).
    // Ambil page berikutnya otomatis agar feed di tangan user selalu konten segar!
    while (results.length < 10 && page <= 12) {
      final live = await ShortTvService.instance.fetchForYouPage(page);
      if (live.isEmpty) break;
      final filtered = live
          .where(
            (d) => !AppSettingsService.instance.shouldSuppressFromForYou(d.id),
          )
          .toList();
      for (final d in filtered) {
        if (!_seenIds.contains(d.id)) {
          results.add(d);
        }
      }
      _currentPage = page;
      page++;
      if (live.length < 10) break;
    }

    // Safety Fallback: Bila seluruh drama sedang dalam cooldown (misal user sudah swipe ratusan drama),
    // muat ulang tanpa filter impresi agar feed tidak pernah kosong sama sekali.
    if (results.isEmpty) {
      final fallbackLive = await ShortTvService.instance.fetchForYouPage(1);
      results.addAll(fallbackLive);
      _currentPage = 1;
    }

    if (mounted) {
      _seenIds
        ..clear()
        ..addAll(results.map((d) => d.id));
      setState(() {
        _dramas = results;
        _activeDramaIndex = 0;
        _hasMore = results.isNotEmpty;
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
    final filtered = live
        .where(
          (d) => !AppSettingsService.instance.shouldSuppressFromForYou(d.id),
        )
        .toList();
    final fresh = filtered.where((d) => _seenIds.add(d.id)).toList();
    setState(() {
      _dramas.addAll(fresh);
      _currentPage = nextPage;
      _hasMore = live.isNotEmpty;
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
                'Memuat Drama Indonesia...',
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
                'Gagal memuat feed drama',
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
          // Catat drama yang baru saja di-swipe lewat sebagai sudah diintip
          if (_activeDramaIndex < _dramas.length) {
            AppSettingsService.instance.recordPreviewImpression(
              _dramas[_activeDramaIndex].id,
            );
          }
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
            onAutoNext: () => _onReelAutoNext(index),
          );
        },
      ),
    );
  }
}

class _ReelItem extends StatefulWidget {
  final DramaModel drama;
  final bool isActive;
  // Reel berikutnya: videonya di-init lebih awal (preload standby 5-10 detik)
  // tapi tidak diputar sampai jadi aktif — swipe ke reel berikut jadi instan tanpa loading.
  final bool isNext;
  final VoidCallback? onAutoNext;

  const _ReelItem({
    super.key,
    required this.drama,
    required this.isActive,
    this.isNext = false,
    this.onAutoNext,
  });

  @override
  State<_ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<_ReelItem> {
  VideoPlayerController? _videoController;
  bool _isPlaying = true;
  List<EpisodeModel> _episodes = [];
  bool _isLoadingEpisodes = false;
  // Init video sedang berjalan: jangan init ulang
  bool _isInitializingVideo = false;

  String _selectedQuality = '1080p';
  final double _playbackSpeed = 1.0;
  bool _clearViewMode = false;
  bool _videoError = false;
  bool _isSynopsisExpanded = false;

  // Scrubber State
  bool _isDraggingScrubber = false;
  double _scrubberValue = 0.0;
  Timer? _positionTimer;
  Timer? _autoNextTimer;

  void _startAutoNextTimer() {
    _autoNextTimer?.cancel();
    // Beri waktu 45 detik cuplikan preview: bila user santai tanpa swipe, auto ganti ke drama berikutnya
    _autoNextTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && widget.isActive && _isPlaying) {
        widget.onAutoNext?.call();
      }
    });
  }

  void _checkVideoEnd() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isPlaying &&
        controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      if (mounted && widget.isActive) {
        widget.onAutoNext?.call();
      }
    }
  }

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
      // Jadi aktif: putar controller yang sudah di-preload (standby) atau init baru.
      if (_videoController != null && _videoController!.value.isInitialized) {
        _videoController?.seekTo(Duration.zero);
        _videoController?.play();
        _startProgressTracker();
        _startAutoNextTimer();
        setState(() => _isPlaying = true);
      } else {
        _initTeaserVideo();
      }
    } else if (widget.isNext && !oldWidget.isNext) {
      // Jadi reel berikut: preload standby (init saja, tanpa play).
      _initTeaserVideo();
    } else if (!widget.isActive && !widget.isNext && oldWidget.isActive) {
      _disposeVideo();
    }
  }

  /// Memutar cuplikan (Episode 1) sebagai teaser preview.
  Future<void> _initTeaserVideo() async {
    if (_isInitializingVideo) return;
    if (_videoController != null && _videoController!.value.isInitialized) {
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
              _videoController?.setLooping(false);
              _videoController?.addListener(_checkVideoEnd);
              // Hanya putar bila reel ini aktif; reel preload diam standby di buffer
              if (widget.isActive) {
                _videoController?.play();
                setState(() {
                  _isPlaying = true;
                });
                _startProgressTracker();
                _startAutoNextTimer();
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
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    _positionTimer?.cancel();
    _positionTimer = null;
    _videoController?.removeListener(_checkVideoEnd);
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    _isPlaying = false;
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

  Future<void> _openFullPlayer([int startEpIndex = 0]) async {
    _disposeVideo();
    setState(() => _isPlaying = false);

    // Player mengambil daftar episodenya sendiri (lazy: chunk pertama
    // dulu, sisanya di latar belakang).
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

  void _showCommentsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1E26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Diskusi & Komentar (385)',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    child: const Text(
                      'R',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: const Text(
                    'Rian Pratama',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Alur ceritanya seru banget, plot twist di ep 10 di luar dugaan!',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  trailing: const Text(
                    '1j lalu',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple.withOpacity(0.2),
                    child: const Text(
                      'S',
                      style: TextStyle(
                        color: Colors.purpleAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: const Text(
                    'Siti Aisyah',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Dubbing Indonesianya rapi dan jernih, lanjut nonton!',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  trailing: const Text(
                    '3j lalu',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _shareDrama() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tautan "${widget.drama.title}" berhasil disalin!'),
        backgroundColor: AppColors.surface,
        duration: const Duration(seconds: 2),
      ),
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
          // Top Left: Provider Badge (jika ada, tanpa tulisan Cuplikan Teaser)
          if (widget.drama.providerBadge != null &&
              widget.drama.providerBadge!.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
                child: Text(
                  widget.drama.providerBadge!,
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          // Bottom Left: Judul, Horizontal Genre Chips, Sinopsis Expandable & Tombol Lebar 'Tonton Lengkap'
          Positioned(
            left: 16,
            right: 80,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Judul Drama
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
                const SizedBox(height: 4),

                // 2. Horizontal Genre Chips
                if (widget.drama.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      height: 24,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.drama.tags.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white24,
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                widget.drama.tags[i],
                                style: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // 3. Sinopsis 2 Baris Expandable (EP.1 | ... Lebih banyak)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isSynopsisExpanded = !_isSynopsisExpanded;
                    });
                  },
                  child: RichText(
                    maxLines: _isSynopsisExpanded ? 6 : 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xDDFFFFFF),
                        height: 1.35,
                      ),
                      children: [
                        const TextSpan(
                          text: 'EP.1 | ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        TextSpan(
                          text: widget.drama.description.isNotEmpty
                              ? widget.drama.description
                              : 'Saksikan kisah seru drama pendek berkualitas dalam tayangan lengkap di GoDrama.',
                        ),
                        TextSpan(
                          text: _isSynopsisExpanded
                              ? ' (Tutup)'
                              : ' ...Lebih banyak',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 4. Tombol Lebar "Tonton Lengkap"
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => _openFullPlayer(0),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: AppColors.primary.withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 22),
                        SizedBox(width: 6),
                        Text(
                          'Tonton Lengkap',
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, size: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sisi Kanan: Cukup 3 Ikon (Bookmark, Komentar, Bagikan)
          Positioned(
            right: 12,
            bottom: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Bookmark / Simpan
                GestureDetector(
                  onTap: () {
                    AppSettingsService.instance.toggleFavorite(widget.drama);
                    setState(() {});
                  },
                  child: _buildActionItem(
                    icon: Icon(
                      isFav
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: isFav ? AppColors.primary : Colors.white,
                      size: 26,
                    ),
                    label: isFav ? 'Tersimpan' : 'Bookmark',
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Komentar
                GestureDetector(
                  onTap: _showCommentsSheet,
                  child: _buildActionItem(
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    label: 'Komentar',
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Bagikan
                GestureDetector(
                  onTap: _shareDrama,
                  child: _buildActionItem(
                    icon: const Icon(
                      Icons.share_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    label: 'Bagikan',
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
}
