import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../data/services/app_settings_service.dart';
import '../player/player_screen.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    AppSettingsService.instance.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Koleksi Saya'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(text: 'Riwayat Tontonan'),
            Tab(text: 'Favorit Saya'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildHistoryList(), _buildFavoritesList()],
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Urbanist',
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    final entries = AppSettingsService.instance.historyEntries;

    // Riwayat kosong = tampilkan empty state jujur, bukan drama acak
    // dari server yang menyamar jadi riwayat.
    if (entries.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_rounded,
        text: 'Belum ada riwayat tontonan',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final drama = entry.drama;
        final progress = entry.progress;
        final watchedEp = progress.episodeIndex + 1;
        // Progres nyata: episode yang dicapai + posisi di dalam episode itu.
        final fraction = drama.totalEpisodes > 0
            ? ((progress.episodeIndex + progress.episodeFraction) /
                    drama.totalEpisodes)
                .clamp(0.05, 1.0)
            : progress.episodeFraction.clamp(0.05, 1.0);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PlayerScreen(
                  drama: drama,
                  initialEpisodeIndex: progress.episodeIndex,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider, width: 0.8),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: drama.coverUrl,
                    width: 70,
                    height: 95,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: AppColors.shimmerBase),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey.shade900,
                      width: 70,
                      height: 95,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        drama.totalEpisodes > 0
                            ? 'Menonton Ep. $watchedEp / ${drama.totalEpisodes}'
                            : 'Menonton Ep. $watchedEp',
                        style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fraction,
                          backgroundColor: AppColors.surfaceLight,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        drama.category,
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
                  Icons.play_circle_fill_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavoritesList() {
    // Favorit tersimpan sebagai objek drama lengkap — tampilkan langsung,
    // bukan dicocokkan ke 10 item feed dan bukan drama acak saat kosong.
    final displayItems = AppSettingsService.instance.favoriteDramas;

    if (displayItems.isEmpty) {
      return _buildEmptyState(
        icon: Icons.favorite_border_rounded,
        text:
            'Belum ada drama favorit.\nKetuk ikon hati di video untuk menyimpan.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final drama = displayItems[index];

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
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: CachedNetworkImage(
                          imageUrl: drama.coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: AppColors.shimmerBase),
                          errorWidget: (_, __, ___) =>
                              Container(color: Colors.grey.shade900),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () {
                            AppSettingsService.instance.toggleFavorite(drama);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF3366),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drama.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (drama.rating != null) ...[
                            const Icon(
                              Icons.star_rounded,
                              color: AppColors.gold,
                              size: 14,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${drama.rating}',
                              style: const TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gold,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (drama.totalEpisodes > 0)
                            Text(
                              '${drama.totalEpisodes} Ep',
                              style: const TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
