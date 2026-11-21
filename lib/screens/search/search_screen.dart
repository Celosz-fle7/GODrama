import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../data/models/drama_model.dart';
import '../../data/services/shorttv_service.dart';
import '../../widgets/drama_card.dart';
import '../player/player_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DramaModel> _results = [];
  bool _isSearching = false;
  bool _isLoadingResults = false;
  List<DramaModel> _trendingDramas = [];
  // Debounce: request hanya jalan 400 ms setelah ketikan berhenti.
  Timer? _debounceTimer;
  // Pagination hasil pencarian.
  final ScrollController _resultsController = ScrollController();
  final Set<String> _seenResultIds = {};
  String _currentQuery = '';
  int _currentPage = 1;
  bool _hasMoreResults = false;
  bool _isLoadingMoreResults = false;
  static const _resultsPageSize = 20;

  final List<String> _trendingTags = [
    'Sulih Suara',
    'CEO',
    'Presdir',
    'Pernikahan',
    'Dewa',
    'Balas Dendam',
    'Kiamat',
  ];

  @override
  void initState() {
    super.initState();
    _resultsController.addListener(_onResultsScroll);
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialQuery!.trim();
      _onSearch(widget.initialQuery!.trim());
    }
    _loadTrending();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _resultsController.removeListener(_onResultsScroll);
    _resultsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onResultsScroll() {
    if (!_resultsController.hasClients) return;
    final nearBottom =
        _resultsController.position.pixels >=
        _resultsController.position.maxScrollExtent - 400;
    if (nearBottom && _hasMoreResults && !_isLoadingMoreResults) {
      _loadMoreResults();
    }
  }

  /// Landing "Top Trending": dari seksi operasional saja (1 request,
  /// di-cache 10 menit) — bukan algoritma For You yang 13 request.
  Future<void> _loadTrending() async {
    final sections = await ShortTvService.instance.fetchOperatingSections(
      tabId: 13,
    );
    if (!mounted) return;
    final seen = <String>{};
    final merged = sections.values
        .expand((l) => l)
        .where((d) => d.id.isNotEmpty && seen.add(d.id))
        .toList();
    if (merged.isNotEmpty) {
      setState(() {
        _trendingDramas = merged;
      });
    }
  }

  void _onSearch(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _results = [];
        _isLoadingResults = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingResults = true;
    });
    // Tunggu ketikan berhenti 400 ms sebelum menembak server.
    _debounceTimer = Timer(
      const Duration(milliseconds: 400),
      () => _performSearch(query),
    );
  }

  Future<void> _performSearch(String query) async {
    if (!mounted || _searchController.text != query) return;
    final remoteResults = await ShortTvService.instance.searchShortTv(
      query,
      page: 1,
      perPage: _resultsPageSize,
    );
    if (!mounted || !_isSearching || _searchController.text != query) return;
    _seenResultIds
      ..clear()
      ..addAll(remoteResults.map((d) => d.id));
    setState(() {
      _results = remoteResults;
      _currentQuery = query;
      _currentPage = 1;
      _hasMoreResults = remoteResults.length >= _resultsPageSize;
      _isLoadingResults = false;
    });
  }

  Future<void> _loadMoreResults() async {
    if (_isLoadingMoreResults || !_hasMoreResults) return;
    setState(() => _isLoadingMoreResults = true);
    final nextPage = _currentPage + 1;
    final query = _currentQuery;
    final remoteResults = await ShortTvService.instance.searchShortTv(
      query,
      page: nextPage,
      perPage: _resultsPageSize,
    );
    if (!mounted) return;
    // Abaikan bila user sudah mengganti kueri selama request berjalan.
    if (query != _currentQuery || !_isSearching) {
      setState(() => _isLoadingMoreResults = false);
      return;
    }
    final fresh = remoteResults.where((d) => _seenResultIds.add(d.id)).toList();
    setState(() {
      _results.addAll(fresh);
      _currentPage = nextPage;
      _hasMoreResults = remoteResults.length >= _resultsPageSize;
      _isLoadingMoreResults = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppColors.divider,
                          width: 0.8,
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearch,
                        style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search short dramas, actors, genres...',
                          hintStyle: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SvgPicture.asset(
                              AppAssets.icSearch,
                              colorFilter: const ColorFilter.mode(
                                AppColors.textSecondary,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    color: AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearch('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: _isSearching
                  ? _buildSearchResults()
                  : _buildTrendingList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 8),
        const Text(
          'Popular Searches',
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _trendingTags.map((tag) {
            return GestureDetector(
              onTap: () {
                _searchController.text = tag;
                _onSearch(tag);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.divider, width: 0.8),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        const Text(
          'Top Trending Ranking',
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ..._trendingDramas.take(6).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final drama = entry.value;

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(drama: drama),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // Rank Number
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: index < 3 ? AppColors.gold : AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Title & Meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          drama.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (drama.tags.isNotEmpty) drama.tags.join(' • '),
                            if (drama.viewCount.isNotEmpty)
                              '${drama.viewCount} views',
                          ].join(' • '),
                          style: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSearchResults() {
    // Saat request masih jalan tampilkan loading — bukan "No results found".
    if (_isLoadingResults) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              color: AppColors.textMuted,
              size: 48,
            ),
            SizedBox(height: 12),
            Text(
              'No results found',
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _resultsController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.58,
      ),
      itemCount: _results.length + (_isLoadingMoreResults ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        final drama = _results[index];
        return DramaCard(
          drama: drama,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PlayerScreen(drama: drama),
              ),
            );
          },
        );
      },
    );
  }
}
