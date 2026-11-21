import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/app_colors.dart';
import '../data/models/drama_model.dart';

class DramaCard extends StatelessWidget {
  final DramaModel drama;
  final VoidCallback onTap;
  final double? width;
  final double aspectRatio;

  const DramaCard({
    super.key,
    required this.drama,
    required this.onTap,
    this.width,
    this.aspectRatio = 0.68,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: drama.coverUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (context, url) =>
                          Container(color: AppColors.shimmerBase),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.surfaceLight,
                        child: const Icon(
                          Icons.broken_image,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  // Dark bottom gradient for text readability
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Color(0xBB000000),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Badge status di kanan atas poster
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            drama.providerBadge != null &&
                                drama.providerBadge!.isNotEmpty
                            ? _getBadgeColor(drama.providerBadge!)
                            : Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        drama.totalEpisodes > 0
                            ? '${drama.totalEpisodes} Eps'
                            : (drama.providerBadge ?? 'HD'),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),

                  // Jumlah view di kanan bawah poster
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            drama.viewCount.isNotEmpty
                                ? drama.viewCount
                                : '10K+',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              drama.tags.isNotEmpty
                  ? drama.tags.take(2).join(' • ')
                  : (drama.providerBadge ?? 'Drama'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBadgeColor(String badge) {
    switch (badge.toLowerCase()) {
      case 'dramabox':
        return const Color(0xFFE50914);
      case 'shortmax':
        return const Color(0xFFFF8C00);
      case 'goodshort':
        return const Color(0xFF007AFF);
      case 'reelshort':
        return const Color(0xFF8A2BE2);
      case 'netshort':
        return const Color(0xFF00B0FF);
      case 'vision+':
      case 'lokal id':
        return const Color(0xFF0A84FF);
      case 'sulih suara':
        return const Color(0xFF7B1FA2);
      case 'dubbing':
        return const Color(0xFF00897B);
      case 'versi dub':
        return const Color(0xFFD81B60);
      case 'trending':
        return const Color(0xFFFF3B30);
      case 'terbaru':
        return const Color(0xFF34C759);
      case 'top rating':
        return const Color(0xFFFF9500);
      case 'western':
        return const Color(0xFF5856D6);
      case 'asian':
        return const Color(0xFFFF2D55);
      default:
        return AppColors.primary;
    }
  }
}
