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
  String _selectedCategoryId = 'sulih_suara';
  List<DramaModel> _dramas = [];
  bool _isLoading = true;
  // Pagination: halaman 1 dulu, halaman berikut saat scroll mendekati bawah.
  final ScrollController _scrollController = ScrollController();
  final Set<String> _seenIds = {};
  int _currentPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;

  // Tab Beranda Berbasis Kategori Otentik Server MovieBox:
  // 1. Sulih Suara 🎧: 100% Drama Dubbing Bahasa Indonesia (classify: 'Indonesian dub')
  // 2. Sedang Tren 🔥: Drama viral paling banyak ditonton (sort: 'Hottest')
  // 3. Terbaru 🎉: Drama rilis paling baru (sort: 'Latest')
  // 4. Lokal Indo 🇮🇩: Drama buatan kreator Indonesia & Vision+ (country: 'Indonesia')
  // 5. Cerita Barat 🐺: Drama werewolf & barat ReelShort (country: 'United States')
  // 6. Drama Asia 👑: Drama CEO & miliarder ShortMax/Asia (country: 'China')
  // 7. Rating Top ⭐: Drama skor kepuasan tertinggi (sort: 'Rating')
  final List<CategoryModel> _categories = const [
    CategoryModel(id: 'sulih_suara', name: 'Sulih Suara 🎧'),
    CategoryModel(id: 'trending', name: 'Sedang Tren 🔥'),
    CategoryModel(id: 'terbaru', name: 'Terbaru 🎉'),
    CategoryModel(id: 'lokal_indo', name: 'Lokal Indo 🇮🇩'),
    CategoryModel(id: 'western', name: 'Cerita Barat 🐺'),
    CategoryModel(id: 'asian', name: 'Drama Asia 👑'),
    CategoryModel(id: 'top_rating', name: 'Rating Top ⭐'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDramas();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final nearBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400;
    if (nearBottom && _hasMore && !_isLoadingMore && !_isLoading) {
      _loadMore();
    }
  }

  Future<void> _loadDramas({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    final list = await ShortTvService.instance.getBerandaDramasPage(
      tab: _selectedCategoryId,
      page: 1,
      forceRefresh: forceRefresh,
    );

    if (mounted) {
      _seenIds
        ..clear()
        ..addAll(list.map((d) => d.id));
      setState(() {
        _dramas = list;
        _currentPage = 1;
        _hasMore = _pageHasMore(_selectedCategoryId, 1, list);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _currentPage + 1;
    final tab = _selectedCategoryId;
    final list = await ShortTvService.instance.getBerandaDramasPage(
      tab: tab,
      page: nextPage,
    );
    if (!mounted) return;
    // Abaikan bila user sudah pindah tab selama request berjalan.
    if (tab != _selectedCategoryId) {
      setState(() => _isLoadingMore = false);
      return;
    }
    final fresh = list.where((d) => _seenIds.add(d.id)).toList();
    setState(() {
      _dramas.addAll(fresh);
      _currentPage = nextPage;
      _hasMore = _pageHasMore(tab, nextPage, list);
      _isLoadingMore = false;
    });
  }

  // Paginasi kontinu tanpa batasan artifisial
  bool _pageHasMore(String tab, int page, List<DramaModel> results) {
    return results.isNotEmpty && results.length >= 10;
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
            await _loadDramas(forceRefresh: true);
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Top App Bar / Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                            MaterialPageRoute(
                              builder: (context) => const SearchScreen(),
                            ),
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
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.divider,
                              width: 0.8,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              category.name,
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Section Title
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _categories
                            .firstWhere(
                              (c) => c.id == _selectedCategoryId,
                              orElse: () => _categories.first,
                            )
                            .name,
                        style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${dramas.length} Judul',
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

              // 2-Column Responsive Drama Grid / Loading / Gagal+Retry
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (dramas.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          color: AppColors.textMuted,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Gagal memuat drama',
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _loadDramas(forceRefresh: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.58,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final drama = dramas[index];
                        return DramaCard(
                          drama: drama,
                          onTap: () => _openPlayer(drama),
                        );
                      },
                      childCount: dramas.length,
                    ),
                  ),
                ),

              if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
        builder: (context) =>
            PlayerScreen(drama: drama, initialEpisodeIndex: 0),
      ),
    );
  }
}
