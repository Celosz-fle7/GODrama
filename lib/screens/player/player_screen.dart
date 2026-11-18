import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../core/player/smart_stream_proxy.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
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
  bool _isLiked = false;
  List<EpisodeModel> _episodes = [];
  bool _isLoadingEpisodes = false;
  String _selectedQuality = '1080p';
  bool _subtitlesEnabled = true;
  List<DramaModel> _recommendedDramas = [];

  @override
  void initState() {
    super.initState();
    _currentEpisodeIndex = widget.initialEpisodeIndex;
    _episodes = widget.drama.episodes;
    _setupVideo();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    final live = await ShortTvService.instance.fetchShortTvDramas(page: 1, perPage: 10);
    if (mounted && live.isNotEmpty) {
      setState(() {
        _recommendedDramas = live.where((d) => d.id != widget.drama.id).toList();
      });
    }
  }

  Future<void> _setupVideo() async {
    if (_episodes.isEmpty && !_isLoadingEpisodes) {
      _isLoadingEpisodes = true;
      final liveEps = await ShortTvService.instance.fetchShortTvEpisodes(widget.drama.id);
      _isLoadingEpisodes = false;
      if (mounted && liveEps.isNotEmpty) {
        setState(() {
          _episodes = liveEps;
        });
      }
    }

    if (_episodes.isEmpty) return;
    final ep = _episodes[_currentEpisodeIndex.clamp(0, _episodes.length - 1)];

    // Pilih resolusi yang tersedia di episode
    if (!ep.resolutions.containsKey(_selectedQuality) && ep.resolutions.isNotEmpty) {
      _selectedQuality = ep.resolutions.keys.first;
    }
    final rawStreamUrl = ep.getUrlForQuality(_selectedQuality);
    final proxiedUrl = SmartStreamProxy.instance.getProxyUrl(rawStreamUrl);

    _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller?.play();

          // Preload episode berikutnya di latar belakang
          if (_currentEpisodeIndex + 1 < _episodes.length) {
            final nextEp = _episodes[_currentEpisodeIndex + 1];
            SmartStreamProxy.instance.preloadNextEpisode(nextEp.videoUrl);
          }
        }
      });
  }

  void _changeQuality(String quality) async {
    if (_selectedQuality == quality || _controller == null) return;
    final currentPos = _controller!.value.position;
    setState(() {
      _selectedQuality = quality;
    });

    final ep = _episodes[_currentEpisodeIndex];
    final newUrl = ep.getUrlForQuality(quality);
    final proxiedUrl = SmartStreamProxy.instance.getProxyUrl(newUrl);

    _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl))
      ..initialize().then((_) {
        if (mounted) {
          _controller?.seekTo(currentPos);
          _controller?.play();
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _selectEpisode(int index) {
    setState(() {
      _currentEpisodeIndex = index;
    });
    _setupVideo();
  }

  @override
  Widget build(BuildContext context) {
    final ep = widget.drama.episodes.isNotEmpty
        ? widget.drama.episodes[_currentEpisodeIndex]
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Video Player Area
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
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),

                  // Tap gesture for controls
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
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
                            GestureDetector(
                              onTap: () {
                                setState(() => _subtitlesEnabled = !_subtitlesEnabled);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 1),
                                    content: Text(_subtitlesEnabled ? 'Sulih Suara / Hardsub ID Aktif' : 'Subtitle Dinonaktifkan'),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: SvgPicture.asset(
                                  AppAssets.icSubtitle,
                                  width: 20,
                                  height: 20,
                                  colorFilter: ColorFilter.mode(
                                    _subtitlesEnabled ? AppColors.primary : Colors.white60,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                            // Quality Picker Pill
                            GestureDetector(
                              onTap: _showQualityPicker,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                margin: const EdgeInsets.only(left: 4, right: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.surface.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.primary, width: 0.8),
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

                    // Center Play/Pause button
                    Center(
                      child: IconButton(
                        iconSize: 56,
                        icon: Icon(
                          _controller?.value.isPlaying == true
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_filled_rounded,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        onPressed: () {
                          setState(() {
                            if (_controller?.value.isPlaying == true) {
                              _controller?.pause();
                            } else {
                              _controller?.play();
                            }
                          });
                        },
                      ),
                    ),

                    // Bottom Progress Slider
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'EP ${_currentEpisodeIndex + 1}',
                              style: const TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                              onPressed: () {
                                if (_currentEpisodeIndex < widget.drama.totalEpisodes - 1) {
                                  _selectEpisode(_currentEpisodeIndex + 1);
                                }
                              },
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
                              const Icon(Icons.star_rounded, color: AppColors.gold, size: 18),
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
                                '${widget.drama.totalEpisodes} Episodes • ${widget.drama.viewCount} views',
                                style: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
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
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.divider, width: 0.8),
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

                    // Episode Selector Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Episodes (1-${widget.drama.totalEpisodes})',
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
                                  totalEpisodes: _episodes.isNotEmpty ? _episodes.length : widget.drama.totalEpisodes,
                                ),
                                currentEpisodeIndex: _currentEpisodeIndex,
                                onEpisodeSelected: _selectEpisode,
                              );
                            },
                            child: const Row(
                              children: [
                                Text(
                                  'All',
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quick Episode Horizontal Pills
                    SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: widget.drama.totalEpisodes.clamp(1, 20),
                        itemBuilder: (context, idx) {
                          final isSelected = idx == _currentEpisodeIndex;
                          return GestureDetector(
                            onTap: () => _selectEpisode(idx),
                            child: Container(
                              width: 48,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : AppColors.divider,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: isSelected ? Colors.white : AppColors.textPrimary,
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
                            'Synopsis',
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
                          'More Like This',
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
                                      builder: (context) => PlayerScreen(drama: item),
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

  void _showQualityPicker() {
    if (_episodes.isEmpty) return;
    final ep = _episodes[_currentEpisodeIndex.clamp(0, _episodes.length - 1)];
    final available = ep.resolutions.keys.toList();
    if (available.isEmpty) available.add('720p');

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
                  style: TextStyle(fontFamily: 'Urbanist', fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              ...available.map((q) {
                final isSelected = q == _selectedQuality;
                return ListTile(
                  title: Text(
                    q,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected ? AppColors.primary : Colors.white,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
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
