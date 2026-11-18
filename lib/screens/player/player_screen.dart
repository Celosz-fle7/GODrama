import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../core/player/smart_stream_proxy.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
import '../../data/services/app_settings_service.dart';
import '../../widgets/drama_card.dart';
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
  bool _subtitlesEnabled = true;
  String _subtitleLanguage = 'Bahasa Indonesia';
  double _playbackSpeed = 1.0;
  List<DramaModel> _recommendedDramas = [];

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
    _subtitlesEnabled = AppSettingsService.instance.subtitlesEnabled;
    _episodes = widget.drama.episodes;
    _setupVideo();
    _loadRecommendations();
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

  Future<void> _loadRecommendations() async {
    final live = await ShortTvService.instance.fetchShortTvDramas(
      page: 1,
      perPage: 10,
    );
    if (mounted && live.isNotEmpty) {
      setState(() {
        _recommendedDramas = live
            .where((d) => d.id != widget.drama.id)
            .toList();
      });
    }
  }

  Future<void> _setupVideo() async {
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
    final ep = _episodes[_currentEpisodeIndex.clamp(0, _episodes.length - 1)];

    // Catat ke riwayat tontonan
    AppSettingsService.instance.addToWatchHistory(widget.drama);

    if (!ep.resolutions.containsKey(_selectedQuality) &&
        ep.resolutions.isNotEmpty) {
      _selectedQuality = ep.resolutions.keys.first;
    }
    final rawStreamUrl = ep.getUrlForQuality(_selectedQuality);
    final proxiedUrl = SmartStreamProxy.instance.getProxyUrl(rawStreamUrl);

    _positionTimer?.cancel();
    _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl))
      ..initialize()
          .then((_) {
            if (mounted) {
              _controller?.setPlaybackSpeed(_playbackSpeed);
              _controller?.play();
              setState(() {});

              // Monitor posisi secara berkala
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

              // Preload episode berikutnya di latar belakang
              if (_currentEpisodeIndex + 1 < _episodes.length) {
                final nextEp = _episodes[_currentEpisodeIndex + 1];
                SmartStreamProxy.instance.preloadNextEpisode(nextEp.videoUrl);
              }
            }
          })
          .catchError((err) {
            debugPrint('[PlayerScreen] Video init error: $err');
          });
  }

  void _changeQuality(String quality) {
    if (_selectedQuality == quality || _controller == null) return;
    final currentPos = _controller!.value.position;
    setState(() {
      _selectedQuality = quality;
    });

    final ep = _episodes[_currentEpisodeIndex.clamp(0, _episodes.length - 1)];
    final newUrl = ep.getUrlForQuality(quality);
    final proxiedUrl = SmartStreamProxy.instance.getProxyUrl(newUrl);

    _positionTimer?.cancel();
    _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl))
      ..initialize()
          .then((_) {
            if (mounted) {
              _controller?.seekTo(currentPos);
              _controller?.setPlaybackSpeed(_playbackSpeed);
              _controller?.play();
              setState(() {});

              _positionTimer = Timer.periodic(
                const Duration(milliseconds: 250),
                (_) {
                  if (mounted && !_isDraggingScrubber) {
                    setState(() {});
                  }
                },
              );
            }
          })
          .catchError((err) {
            debugPrint('[PlayerScreen] Change quality error: $err');
          });
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
    _controlsTimer?.cancel();
    _positionTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _selectEpisode(int index) {
    if (index == _currentEpisodeIndex) return;
    setState(() {
      _currentEpisodeIndex = index;
    });
    _setupVideo();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isFav = AppSettingsService.instance.isFavorite(widget.drama.id);
    final totalEps = _episodes.isNotEmpty
        ? _episodes.length
        : widget.drama.totalEpisodes;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Video Player Container
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  if (_controller != null && _controller!.value.isInitialized)
                    Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  else
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),

                  // Subtitle Overlay pada Player
                  if (_subtitlesEnabled &&
                      _controller != null &&
                      _controller!.value.isInitialized)
                    Positioned(
                      bottom: _showControls ? 56 : 14,
                      left: 20,
                      right: 20,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '[$_subtitleLanguage - Sulih Suara Resmi]',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Tap gesture untuk toggle tampilan kontrol
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
                      _resetControlsTimer();
                    },
                    child: Container(color: Colors.transparent),
                  ),

                  // Overlay Controls
                  if (_showControls) ...[
                    // Top Bar
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.75),
                              Colors.transparent,
                            ],
                          ),
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
                              child: Text(
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
                            ),
                            // Subtitle Toggle Button
                            IconButton(
                              icon: Icon(
                                _subtitlesEnabled
                                    ? Icons.closed_caption_rounded
                                    : Icons.closed_caption_off_rounded,
                                color: _subtitlesEnabled
                                    ? const Color(0xFFFF3366)
                                    : Colors.white70,
                                size: 24,
                              ),
                              onPressed: () {
                                setState(() {
                                  _subtitlesEnabled = !_subtitlesEnabled;
                                });
                                AppSettingsService.instance.toggleSubtitles(
                                  _subtitlesEnabled,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 1),
                                    content: Text(
                                      _subtitlesEnabled
                                          ? 'Subtitle & Sulih Suara Aktif'
                                          : 'Subtitle Dinonaktifkan',
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Playback Speed Selector Pill
                            GestureDetector(
                              onTap: _showSpeedPicker,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.white30,
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
                            // Quality Picker Pill
                            GestureDetector(
                              onTap: _showQualityPicker,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF3366)
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFFFF3366),
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

                    // Center Playback Controls (Previous, Play/Pause, Next)
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Previous Episode Button
                          IconButton(
                            iconSize: 38,
                            icon: Icon(
                              Icons.skip_previous_rounded,
                              color: _currentEpisodeIndex > 0
                                  ? Colors.white
                                  : Colors.white24,
                            ),
                            onPressed: _currentEpisodeIndex > 0
                                ? () => _selectEpisode(_currentEpisodeIndex - 1)
                                : null,
                          ),
                          const SizedBox(width: 20),

                          // Play / Pause Button
                          IconButton(
                            iconSize: 56,
                            icon: Icon(
                              _controller?.value.isPlaying == true
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_filled_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              setState(() {
                                if (_controller?.value.isPlaying == true) {
                                  _controller?.pause();
                                } else {
                                  _controller?.play();
                                }
                              });
                              _resetControlsTimer();
                            },
                          ),
                          const SizedBox(width: 20),

                          // Next Episode Button
                          IconButton(
                            iconSize: 38,
                            icon: Icon(
                              Icons.skip_next_rounded,
                              color: _currentEpisodeIndex < totalEps - 1
                                  ? Colors.white
                                  : Colors.white24,
                            ),
                            onPressed: _currentEpisodeIndex < totalEps - 1
                                ? () => _selectEpisode(_currentEpisodeIndex + 1)
                                : null,
                          ),
                        ],
                      ),
                    ),

                    // Bottom Progress Slider & Time Indicator
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.85),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _controller != null &&
                                          _controller!.value.isInitialized
                                      ? _formatDuration(
                                          _controller!.value.position,
                                        )
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
                                      thumbColor: const Color(0xFFFF3366),
                                      trackHeight: 3,
                                      activeTrackColor: const Color(0xFFFF3366),
                                      inactiveTrackColor: Colors.white24,
                                    ),
                                    child: Slider(
                                      value: _isDraggingScrubber
                                          ? _scrubberValue
                                          : (_controller != null &&
                                                _controller!
                                                    .value
                                                    .isInitialized)
                                          ? _controller!
                                                .value
                                                .position
                                                .inMilliseconds
                                                .toDouble()
                                                .clamp(
                                                  0.0,
                                                  _controller!
                                                      .value
                                                      .duration
                                                      .inMilliseconds
                                                      .toDouble(),
                                                )
                                          : 0.0,
                                      min: 0.0,
                                      max:
                                          (_controller != null &&
                                              _controller!
                                                  .value
                                                  .isInitialized &&
                                              _controller!
                                                      .value
                                                      .duration
                                                      .inMilliseconds >
                                                  0)
                                          ? _controller!
                                                .value
                                                .duration
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
                                      ? _formatDuration(
                                          _controller!.value.duration,
                                        )
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
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Scrollable Content below player
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title & Action Row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.drama.title,
                            style: const TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: AppColors.gold,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.drama.rating}',
                                style: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.gold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '$totalEps Episodes • ${widget.drama.viewCount} views',
                                style: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Quick Action Buttons Row (Like, Favorite/MyList, Share)
                          Row(
                            children: [
                              // Favorite / My List Toggle
                              ElevatedButton.icon(
                                onPressed: () {
                                  AppSettingsService.instance.toggleFavorite(
                                    widget.drama,
                                  );
                                  setState(() {});
                                },
                                icon: Icon(
                                  isFav
                                      ? Icons.bookmark_added_rounded
                                      : Icons.bookmark_add_outlined,
                                  color: isFav
                                      ? Colors.white
                                      : AppColors.primary,
                                  size: 18,
                                ),
                                label: Text(
                                  isFav ? 'Di Daftar' : 'Tambah Favorit',
                                  style: TextStyle(
                                    color: isFav
                                        ? Colors.white
                                        : AppColors.primary,
                                    fontFamily: 'Urbanist',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isFav
                                      ? AppColors.primary
                                      : AppColors.surface,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: isFav
                                          ? AppColors.primary
                                          : AppColors.divider,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Share Button
                              OutlinedButton.icon(
                                onPressed: () {
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
                                      content: Text(
                                        'Tautan drama disalin ke clipboard!',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.share_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'Bagikan',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Urbanist',
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.divider,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Tags
                          Wrap(
                            spacing: 8,
                            children: widget.drama.tags.map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.divider,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  tag,
                                  style: const TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const Divider(color: AppColors.divider, height: 24),

                    // Episode Selector Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Episodes (1-$totalEps)',
                            style: const TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              EpisodeDrawer.show(
                                context,
                                drama: widget.drama.copyWith(
                                  episodes: _episodes,
                                  totalEpisodes: totalEps,
                                ),
                                currentEpisodeIndex: _currentEpisodeIndex,
                                onEpisodeSelected: _selectEpisode,
                              );
                            },
                            child: const Row(
                              children: [
                                Text(
                                  'Semua Episode',
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quick Episode Horizontal Pills (1, 2, 3...)
                    SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: totalEps.clamp(1, 30),
                        itemBuilder: (context, idx) {
                          final isSelected = idx == _currentEpisodeIndex;
                          return GestureDetector(
                            onTap: () => _selectEpisode(idx),
                            child: Container(
                              width: 48,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.divider,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Synopsis
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sinopsis Drama',
                            style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.drama.description,
                            style: const TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 13,
                              height: 1.4,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_recommendedDramas.isNotEmpty) ...[
                      const Divider(color: AppColors.divider, height: 32),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Drama Terkait Lainnya',
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _recommendedDramas.length,
                          itemBuilder: (context, index) {
                            final item = _recommendedDramas[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: DramaCard(
                                width: 110,
                                drama: item,
                                onTap: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          PlayerScreen(drama: item),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedPicker() {
    final speeds = [1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Kecepatan Pemutaran',
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...speeds.map((s) {
                final isSelected = s == _playbackSpeed;
                return ListTile(
                  title: Text(
                    '${s}x ${s == 1.0 ? '(Normal)' : ''}',
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: isSelected ? AppColors.primary : Colors.white,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.primary)
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

  void _showQualityPicker() {
    if (_episodes.isEmpty) return;
    final ep = _episodes[_currentEpisodeIndex.clamp(0, _episodes.length - 1)];
    final available = ep.resolutions.keys.toList();
    if (available.isEmpty) {
      available.addAll(['1080p', '720p', '480p']);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
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
                  ),
                ),
              ),
              ...available.map((q) {
                final isSelected = q == _selectedQuality;
                return ListTile(
                  title: Text(
                    q == '1080p'
                        ? '1080p Full HD'
                        : q == '720p'
                        ? '720p HD Standard'
                        : '480p Hemat Kuota',
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: isSelected ? AppColors.primary : Colors.white,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.primary)
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
}
