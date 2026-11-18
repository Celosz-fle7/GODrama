import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
import '../../widgets/drama_card.dart';
import '../../widgets/hero_banner.dart';
import '../player/player_screen.dart';
import '../search/search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedCategoryId = 'trending';
  List<DramaModel> _dramas = [];
  bool _isLoading = true;

  final List<CategoryModel> _categories = const [
    CategoryModel(id: 'trending', name: 'Sedang Trending 🔥'),
    CategoryModel(id: 'dubbing', name: 'Sulih Suara ID 🇮🇩'),
    CategoryModel(id: 'terbaru', name: 'Terbaru ✨'),
  ];

  @override
  void initState() {
    super.initState();
    _loadDramas();
  }

  Future<void> _loadDramas() async {
    setState(() => _isLoading = true);
    List<DramaModel> liveDramas = [];
    if (_selectedCategoryId == 'dubbing') {
      liveDramas = await ShortTvService.instance.fetchShortTvDramas(
        page: 1,
        perPage: 20,
        classify: 'Sulih suara Indonesia',
        sort: 'Hot',
      );
    } else if (_selectedCategoryId == 'terbaru') {
      liveDramas = await ShortTvService.instance.fetchShortTvDramas(
        page: 1,
        perPage: 20,
        sort: 'Latest',
      );
    } else {
      liveDramas = await ShortTvService.instance.fetchForYouAlgorithm();
    }

    if (mounted) {
      setState(() {
        _dramas = liveDramas;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dramas = _dramas;
    final featured = dramas.take(4).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            await _loadDramas();
          },
          child: CustomScrollView(
            slivers: [
              // Top App Bar / Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // App Title / Logo
                      RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'Go',
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                            TextSpan(
                              text: 'Drama',
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Search Button
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SearchScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: SvgPicture.asset(
                            AppAssets.icSearch,
                            width: 20,
                            height: 20,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Hero Banner Carousel
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  child: HeroBanner(
                    dramas: featured,
                    onDramaTap: (drama) => _openPlayer(drama),
                  ),
                ),
              ),

              // Category Tabs (Horizontal Scroll)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = category.id == _selectedCategoryId;

                      return GestureDetector(
                        onTap: () {
                          if (_selectedCategoryId != category.id) {
                            setState(() {
                              _selectedCategoryId = category.id;
                            });
                            _loadDramas();
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.divider,
                              width: 0.8,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              category.name,
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Section Title: "Must-Watch Dramas"
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Trending Dramas',
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'See All',
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2-Column Responsive Drama Grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.58,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final drama = dramas[index % dramas.length];
                      return DramaCard(
                        drama: drama,
                        onTap: () => _openPlayer(drama),
                      );
                    },
                    childCount: dramas.length * 2, // repeat for realistic scroll
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlayer(DramaModel drama) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          drama: drama,
          initialEpisodeIndex: 0,
        ),
      ),
    );
  }
}
