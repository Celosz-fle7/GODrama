import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/drama_model.dart';
import '../../widgets/drama_card.dart';
import '../player/player_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DramaModel> _results = [];
  bool _isSearching = false;

  final List<String> _trendingTags = [
    'Billionaire',
    'Revenge',
    'Secret Heir',
    'CEO Wife',
    'Contract Marriage',
    'Martial Arts',
    'Strong Female',
  ];

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _results = [];
      });
      return;
    }

    final filtered = MockData.allDramas.where((drama) {
      final titleMatch = drama.title.toLowerCase().contains(query.toLowerCase());
      final tagMatch = drama.tags.any((t) => t.toLowerCase().contains(query.toLowerCase()));
      return titleMatch || tagMatch;
    }).toList();

    setState(() {
      _isSearching = true;
      _results = filtered;
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
                        border: Border.all(color: AppColors.divider, width: 0.8),
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
                              colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn),
                            ),
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearch('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
              child: _isSearching ? _buildSearchResults() : _buildTrendingList(),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        ...MockData.allDramas.take(5).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final drama = entry.value;

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PlayerScreen(drama: drama)),
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
                          '${drama.tags.join(' • ')} • ${drama.viewCount} views',
                          style: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: AppColors.textMuted, size: 48),
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
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.58,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final drama = _results[index];
        return DramaCard(
          drama: drama,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => PlayerScreen(drama: drama)),
            );
          },
        );
      },
    );
  }
}
