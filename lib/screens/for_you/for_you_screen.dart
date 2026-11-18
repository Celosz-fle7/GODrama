import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../core/player/smart_stream_proxy.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
import '../../data/services/app_settings_service.dart';
import '../../widgets/episode_drawer.dart';
import '../player/player_screen.dart';

class ForYouScreen extends StatefulWidget {
  const ForYouScreen({super.key});

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  final PageController _pageController = PageController();
  List<DramaModel> _dramas = [];
  int _activeDramaIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLiveShortDramas();
  }

  Future<void> _loadLiveShortDramas() async {
    final live = await ShortTvService.instance.fetchForYouAlgorithm();
    if (mounted) {
      setState(() {
        _dramas = live;
        _isLoading = false;
      });
    }
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
                'Memuat Tangga ShortTV Indonesia...',
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
                'Gagal memuat feed video',
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
        },
        itemBuilder: (context, index) {
          final drama = _dramas[index];
          final isCurrent = index == _activeDramaIndex;
          return _ReelItem(drama: drama, isActive: isCurrent);
        },
      ),
    );
  }
}

class _ReelItem extends StatefulWidget {
  final DramaModel drama;
  final bool isActive;

  const _ReelItem({required this.drama, required this.isActive});

  @override
  State<_ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<_ReelItem> {
  VideoPlayerController? _videoController;
  int _currentEpisode = 0;
  bool _isPlaying = true;
  List<EpisodeModel> _episodes = [];
  bool _isLoadingEpisodes = false;

  // 3 Menu Kontrol Unggulan (Kualitas, Subtitle, Speed / Lainnya)
  String _selectedQuality = '1080p';
  bool _subtitleEnabled = true;
  String _subtitleLanguage = 'Bahasa Indonesia';
  double _playbackSpeed = 1.0;
  bool _isDraggingScrubber = false;
  double _scrubberValue = 0.0;

  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    _selectedQuality = AppSettingsService.instance.defaultQuality;
    _subtitleEnabled = AppSettingsService.instance.subtitlesEnabled;
    _episodes = widget.drama.episodes;
    if (widget.isActive) {
      _initVideo();
    }
  }

  @override
  void didUpdateWidget(covariant _ReelItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initVideo();
    } else if (!widget.isActive && oldWidget.isActive) {
      _disposeVideo();
    }
  }

  Future<void> _initVideo() async {
    if (_episodes.isEmpty && !_isLoadingEpisodes) {
      _isLoadingEpisodes = true;
      final liveEps = await ShortTvService.instance.fetchShortTvEpisodes(
        widget.drama.id,
      );
      _isLoadingEpisodes = false;
      if (mounted && liveEps.isNotEmpty) {
        setState(() {
          _episodes = liveEps;
        });
      }
    }

    if (_episodes.isEmpty) return;
    final ep = _episodes[_currentEpisode.clamp(0, _episodes.length - 1)];

    // Catat ke watch history di AppSettingsService
    AppSettingsService.instance.addToWatchHistory(widget.drama);

    // Dapatkan url berdasarkan kualitas yang dipilih
    final streamUrl = ep.getUrlForQuality(_selectedQuality);
    final proxiedUrl = SmartStreamProxy.instance.getProxyUrl(streamUrl);

    _disposeVideo();

    _videoController = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl))
      ..initialize().then((_) {
        if (mounted) {
          _videoController?.setPlaybackSpeed(_playbackSpeed);
          _videoController?.setLooping(true);
          _videoController?.play();
          setState(() {
            _isPlaying = true;
          });

          // Mulai timer untuk progress scrubber
          _startProgressTracker();

          // Smart Preload episode berikutnya di background
          if (_currentEpisode + 1 < _episodes.length) {
            final nextEp = _episodes[_currentEpisode + 1];
            SmartStreamProxy.instance.preloadNextEpisode(nextEp.videoUrl);
          }
        }
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

  // Ganti Kualitas Video on the fly tanpa reset detik video
  void _changeQuality(String quality) {
    if (_selectedQuality == quality || _videoController == null) return;
    final currentPos = _videoController!.value.position;
    setState(() {
      _selectedQuality = quality;
    });

    final ep = _episodes[_currentEpisode.clamp(0, _episodes.length - 1)];
    final newUrl = ep.getUrlForQuality(quality);
    final proxiedUrl = SmartStreamProxy.instance.getProxyUrl(newUrl);

    _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl))
      ..initialize().then((_) {
        if (mounted) {
          _videoController?.seekTo(currentPos);
          _videoController?.setPlaybackSpeed(_playbackSpeed);
          _videoController?.play();
          setState(() {
            _isPlaying = true;
          });
        }
      });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF1E232E),
        content: Text('Kualitas diubah ke: $quality'),
      ),
    );
  }

  // Cycle Kecepatan Pemutaran (1.0x -> 1.25x -> 1.5x -> 2.0x -> 1.0x)
  void _cyclePlaybackSpeed() {
    double nextSpeed = 1.0;
    if (_playbackSpeed == 1.0) {
      nextSpeed = 1.25;
    } else if (_playbackSpeed == 1.25) {
      nextSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }

    setState(() {
      _playbackSpeed = nextSpeed;
    });
    _videoController?.setPlaybackSpeed(nextSpeed);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        backgroundColor: const Color(0xFF1E232E),
        content: Text('Kecepatan video: ${nextSpeed}x'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFav = AppSettingsService.instance.isFavorite(widget.drama.id);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video Player atau Poster Banner
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

              // Center Pause Icon
              if (!_isPlaying)
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

        // Subtitle Overlay (Jika Aktif)
        if (_subtitleEnabled)
          Positioned(
            left: 20,
            right: 80,
            bottom: 110,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.closed_caption_rounded,
                      color: Color(0xFFFF3366),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '[$_subtitleLanguage - Sulih Suara Resmi]',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Top Left: Live Protocol Status Pill
        Positioned(
          top: 48,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.flash_on_rounded,
                  color: Color(0xFFFFD700),
                  size: 14,
                ),
                SizedBox(width: 4),
                Text(
                  'ShortTV Indo',
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

        // Bottom Left Info Overlay
        Positioned(
          left: 16,
          right: 80,
          bottom: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Episode Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF3366), Color(0xFFFF5E3A)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Episode ${_currentEpisode + 1}/${widget.drama.totalEpisodes}',
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
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

        // Right Action Bar: Menu Interaktif Lengkap Termasuk 3 Menu Utama
        Positioned(
          right: 12,
          bottom: 30,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Favorite / Like Button
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
                  label: isFav ? 'Tersimpan' : 'Suka',
                ),
              ),
              const SizedBox(height: 14),

              // 2. Series / Episode Drawer Button
              GestureDetector(
                onTap: () {
                  EpisodeDrawer.show(
                    context,
                    drama: widget.drama.copyWith(
                      episodes: _episodes,
                      totalEpisodes: _episodes.isNotEmpty
                          ? _episodes.length
                          : widget.drama.totalEpisodes,
                    ),
                    currentEpisodeIndex: _currentEpisode,
                    onEpisodeSelected: (newIndex) {
                      setState(() {
                        _currentEpisode = newIndex;
                        _initVideo();
                      });
                    },
                  );
                },
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
                  label: 'Series',
                ),
              ),
              const SizedBox(height: 14),

              // 3. MENU 1: Kualitas Video (Quality Switcher)
              GestureDetector(
                onTap: _showQualityPickerSheet,
                child: _buildActionItem(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFFF3366),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _selectedQuality,
                      style: const TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  label: 'Kualitas',
                ),
              ),
              const SizedBox(height: 14),

              // 4. MENU 2: Subtitle & Sulih Suara (CC)
              GestureDetector(
                onTap: _showSubtitleSheet,
                child: _buildActionItem(
                  icon: Icon(
                    _subtitleEnabled
                        ? Icons.closed_caption_rounded
                        : Icons.closed_caption_off_rounded,
                    color: _subtitleEnabled
                        ? const Color(0xFFFF3366)
                        : Colors.white70,
                    size: 26,
                  ),
                  label: 'Subtitle',
                ),
              ),
              const SizedBox(height: 14),

              // 5. MENU 3: Kecepatan & Kontrol Lainnya (Playback Speed & More)
              GestureDetector(
                onTap: _cyclePlaybackSpeed,
                child: _buildActionItem(
                  icon: Text(
                    '${_playbackSpeed}x',
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _playbackSpeed > 1.0
                          ? const Color(0xFFFF3366)
                          : Colors.white,
                    ),
                  ),
                  label: 'Speed',
                ),
              ),
              const SizedBox(height: 14),

              // 6. Tombol Share / Bagikan Tautan Drama
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(
                      text:
                          'Nonton drama "${widget.drama.title}" di GoDrama: https://github.com/Celosz-fle7/GODrama',
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      duration: Duration(seconds: 1),
                      backgroundColor: Color(0xFF1E232E),
                      content: Text('Tautan drama disalin ke clipboard!'),
                    ),
                  );
                },
                child: _buildActionItem(
                  icon: const Icon(
                    Icons.share_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  label: 'Share',
                ),
              ),
              const SizedBox(height: 14),

              // 7. Full Player Expand Button
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayerScreen(
                        drama: widget.drama,
                        initialEpisodeIndex: _currentEpisode,
                      ),
                    ),
                  );
                },
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

        // Video Progress Scrubber Bar di paling bawah layar
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

  // Bottom Sheet Pemilihan Kualitas Video (Menu 1)
  void _showQualityPickerSheet() {
    final available = ['1080p', '720p', '480p'];
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
                  'Kualitas Streaming Reel',
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
                          ? '1080p Full HD (Kualitas Tertinggi)'
                          : q == '720p'
                          ? '720p HD (Standar Rekomendasi)'
                          : '480p Hemat Kuota (Streaming Cepat)',
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

  // Bottom Sheet Subtitle & Sulih Suara (Menu 2)
  void _showSubtitleSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Subtitle & Audio Sulih Suara',
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Info Sulih Suara Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141720),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF3366).withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.mic_external_on_rounded,
                            color: Color(0xFFFF3366),
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Audio: Sulih Suara Bahasa Indonesia',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Rekaman sulih suara studio resmi bawaan ShortTV',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Toggle Subtitle
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFFFF3366),
                      title: const Text(
                        'Tampilkan Subtitle Teks',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Teks terjemahan di layar video reel',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      value: _subtitleEnabled,
                      onChanged: (val) {
                        setSheetState(() {
                          _subtitleEnabled = val;
                        });
                        setState(() {
                          _subtitleEnabled = val;
                        });
                        AppSettingsService.instance.toggleSubtitles(val);
                      },
                    ),

                    if (_subtitleEnabled) ...[
                      const Divider(color: Colors.white10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.translate_rounded,
                          color: Colors.white70,
                        ),
                        title: const Text(
                          'Bahasa Indonesia',
                          style: TextStyle(color: Colors.white),
                        ),
                        trailing: _subtitleLanguage == 'Bahasa Indonesia'
                            ? const Icon(Icons.check, color: Color(0xFFFF3366))
                            : null,
                        onTap: () {
                          setSheetState(
                            () => _subtitleLanguage = 'Bahasa Indonesia',
                          );
                          setState(
                            () => _subtitleLanguage = 'Bahasa Indonesia',
                          );
                          Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.language_rounded,
                          color: Colors.white70,
                        ),
                        title: const Text(
                          'English (Original)',
                          style: TextStyle(color: Colors.white),
                        ),
                        trailing: _subtitleLanguage == 'English'
                            ? const Icon(Icons.check, color: Color(0xFFFF3366))
                            : null,
                        onTap: () {
                          setSheetState(() => _subtitleLanguage = 'English');
                          setState(() => _subtitleLanguage = 'English');
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
