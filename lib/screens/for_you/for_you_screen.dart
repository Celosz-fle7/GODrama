import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../core/player/smart_stream_proxy.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
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
    // Memuat tangga algoritma ShortTV untuk Indonesia (Sedang Trending -> Sulih Suara Indonesia)
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
              const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 48),
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
          return _ReelItem(
            drama: drama,
            isActive: isCurrent,
          );
        },
      ),
    );
  }
}

class _ReelItem extends StatefulWidget {
  final DramaModel drama;
  final bool isActive;

  const _ReelItem({
    required this.drama,
    required this.isActive,
  });

  @override
  State<_ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<_ReelItem> {
  VideoPlayerController? _videoController;
  bool _isLiked = false;
  int _currentEpisode = 0;
  bool _isPlaying = true;
  List<EpisodeModel> _episodes = [];
  bool _isLoadingEpisodes = false;

  @override
  void initState() {
    super.initState();
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
      final liveEps = await ShortTvService.instance.fetchShortTvEpisodes(widget.drama.id);
      _isLoadingEpisodes = false;
      if (mounted && liveEps.isNotEmpty) {
        setState(() {
          _episodes = liveEps;
        });
      }
    }

    if (_episodes.isEmpty) return;
    final ep = _episodes[_currentEpisode.clamp(0, _episodes.length - 1)];
    final proxiedUrl = SmartStreamProxy.instance.getProxyUrl(ep.videoUrl);

    _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _videoController?.play();
          _videoController?.setLooping(true);

          // Smart Preloader: Otomatis preload episode berikutnya di background
          if (_currentEpisode + 1 < _episodes.length) {
            final nextEp = _episodes[_currentEpisode + 1];
            SmartStreamProxy.instance.preloadNextEpisode(nextEp.videoUrl);
          }
        }
      });
  }

  void _disposeVideo() {
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video or Background Poster Fallback
        GestureDetector(
          onTap: _togglePlayPause,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_videoController != null && _videoController!.value.isInitialized)
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

              // Gradient Overlay
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                    stops: const [0.0, 0.4, 0.9],
                  ),
                ),
              ),

              // Center Pause Icon
              if (!_isPlaying)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
                  ),
                ),
            ],
          ),
        ),

        // Bottom Left Info Overlay
        Positioned(
          left: 16,
          right: 80,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Episode Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
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
                ),
              ),
            ],
          ),
        ),

        // Right Action Bar (Buttons)
        Positioned(
          right: 12,
          bottom: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Like Button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isLiked = !_isLiked;
                  });
                },
                child: _buildActionItem(
                  icon: Icon(
                    _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isLiked ? AppColors.primary : Colors.white,
                    size: 32,
                  ),
                  label: _isLiked ? '12.5K' : '12.4K',
                ),
              ),
              const SizedBox(height: 18),

              // Episode Drawer Button
              GestureDetector(
                onTap: () {
                  EpisodeDrawer.show(
                    context,
                    drama: widget.drama.copyWith(
                      episodes: _episodes,
                      totalEpisodes: _episodes.isNotEmpty ? _episodes.length : widget.drama.totalEpisodes,
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
                    width: 28,
                    height: 28,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                  label: 'Series',
                ),
              ),
              const SizedBox(height: 18),

              // Full Player Expand Button
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
                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 32),
                  label: 'Player',
                ),
              ),
            ],
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
            color: Colors.black.withOpacity(0.4),
            shape: BoxShape.circle,
          ),
          child: Center(child: icon),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
