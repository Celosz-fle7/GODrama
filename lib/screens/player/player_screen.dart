import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/app_colors.dart';
import '../../core/player/smart_stream_proxy.dart';
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
  bool _subtitlesEnabled = true;
  final String _subtitleLanguage = 'Bahasa Indonesia';
  double _playbackSpeed = 1.0;

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

  Future<void> _setupVideo() async {
    if (_episodes.isEmpty && !_isLoadingEpisodes) {
      _isLoadingEpisodes = true;
      final targetEps = widget.drama.totalEpisodes > 0
          ? widget.drama.totalEpisodes
          : 100;
      final liveEps = await ShortTvService.instance.fetchShortTvEpisodes(
        widget.drama.id,
        startPos: 1,
        endPosition: targetEps,
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

  void _checkVideoEnd() {
    if (_controller != null &&
        _controller!.value.isInitialized &&
        !_controller!.value.isPlaying &&
        _controller!.value.position >= _controller!.value.duration &&
        _controller!.value.duration > Duration.zero) {
      _playNextEpisode();
    }
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
    _controller?.removeListener(_checkVideoEnd);
    _controller?.dispose();
    super.dispose();
  }

  void _selectEpisode(int index) {
    if (index == _currentEpisodeIndex || _episodes.isEmpty) return;
    setState(() {
      _currentEpisodeIndex = index.clamp(0, _episodes.length - 1);
    });
    _setupVideo();
  }

  void _playNextEpisode() {
    if (_currentEpisodeIndex < _episodes.length - 1) {
      _selectEpisode(_currentEpisodeIndex + 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          backgroundColor: const Color(0xFF1E232E),
          content: Text('Memutar Episode ${_currentEpisodeIndex + 1}...'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF1E232E),
          content: Text('Ini adalah episode terakhir.'),
        ),
      );
    }
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
        final qualities = ['1080p', '720p', '480p'];
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
                            : '$q (Hemat Kuota)',
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

            // 3. SUBTITLE OVERLAY (selalu tampil di layar penuh jika diaktifkan)
            if (_subtitlesEnabled &&
                _controller != null &&
                _controller!.value.isInitialized)
              Positioned(
                bottom: _showControls ? 130 : 40,
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

            // 4. TOP APP BAR (ketika kontrol aktif)
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
                                'Episode ${_currentEpisodeIndex + 1} / $totalEps',
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
                        // Subtitle Toggle
                        IconButton(
                          icon: Icon(
                            _subtitlesEnabled
                                ? Icons.closed_caption_rounded
                                : Icons.closed_caption_off_rounded,
                            color: _subtitlesEnabled
                                ? AppColors.primary
                                : Colors.white60,
                          ),
                          onPressed: () {
                            setState(() {
                              _subtitlesEnabled = !_subtitlesEnabled;
                            });
                            _resetControlsTimer();
                          },
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

            // 5. CENTER PLAY/PAUSE (ketika kontrol aktif)
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

            // 6. BOTTOM CONTROLS & EPISODE DRAWER BUTTON (ketika kontrol aktif)
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
                                      'Daftar Episode ($totalEps Ep)',
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
