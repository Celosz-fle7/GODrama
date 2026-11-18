import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_assets.dart';
import '../data/models/drama_model.dart';

class EpisodeDrawer extends StatefulWidget {
  final DramaModel drama;
  final int currentEpisodeIndex;
  final Function(int index) onEpisodeSelected;

  const EpisodeDrawer({
    super.key,
    required this.drama,
    required this.currentEpisodeIndex,
    required this.onEpisodeSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required DramaModel drama,
    required int currentEpisodeIndex,
    required Function(int index) onEpisodeSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => EpisodeDrawer(
        drama: drama,
        currentEpisodeIndex: currentEpisodeIndex,
        onEpisodeSelected: onEpisodeSelected,
      ),
    );
  }

  @override
  State<EpisodeDrawer> createState() => _EpisodeDrawerState();
}

class _EpisodeDrawerState extends State<EpisodeDrawer> {
  int _selectedRangeIndex = 0;
  static const int _rangeSize = 30;

  @override
  void initState() {
    super.initState();
    _selectedRangeIndex = widget.currentEpisodeIndex ~/ _rangeSize;
  }

  @override
  Widget build(BuildContext context) {
    final totalEpisodes = widget.drama.totalEpisodes;
    final totalRanges = (totalEpisodes / _rangeSize).ceil();

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'All Episodes',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Updated to Ep. $totalEpisodes',
                      style: const TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Range Tabs if > 30 episodes
          if (totalRanges > 1)
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: totalRanges,
                itemBuilder: (context, rangeIdx) {
                  final start = rangeIdx * _rangeSize + 1;
                  final end = ((rangeIdx + 1) * _rangeSize).clamp(
                    1,
                    totalEpisodes,
                  );
                  final isSelected = rangeIdx == _selectedRangeIndex;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRangeIndex = rangeIdx;
                      });
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
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          '$start-$end',
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 12,
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
          const SizedBox(height: 12),
          // Episodes Grid
          Expanded(
            child: Builder(
              builder: (context) {
                final startIndex = _selectedRangeIndex * _rangeSize;
                final endIndex = (startIndex + _rangeSize).clamp(
                  0,
                  totalEpisodes,
                );
                final rangeCount = endIndex - startIndex;

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: rangeCount,
                  itemBuilder: (context, idx) {
                    final episodeIndex = startIndex + idx;
                    final epNum = episodeIndex + 1;
                    final isPlaying =
                        episodeIndex == widget.currentEpisodeIndex;

                    return GestureDetector(
                      onTap: () {
                        widget.onEpisodeSelected(episodeIndex);
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isPlaying
                              ? AppColors.primary.withOpacity(0.15)
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isPlaying
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: isPlaying
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Lottie.asset(
                                    AppAssets.animSeriesPlaying,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                              Icons.equalizer,
                                              color: AppColors.primary,
                                              size: 18,
                                            ),
                                  ),
                                )
                              : Text(
                                  '$epNum',
                                  style: const TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
