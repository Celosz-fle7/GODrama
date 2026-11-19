import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/app_colors.dart';
import '../data/models/drama_model.dart';

class HeroBanner extends StatefulWidget {
  final List<DramaModel> dramas;
  final Function(DramaModel drama) onDramaTap;

  const HeroBanner({super.key, required this.dramas, required this.onDramaTap});

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.dramas.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        CarouselSlider.builder(
          itemCount: widget.dramas.length,
          itemBuilder: (context, index, realIndex) {
            final drama = widget.dramas[index];
            return GestureDetector(
              onTap: () => widget.onDramaTap(drama),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: drama.bannerUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: AppColors.shimmerBase),
                        errorWidget: (context, url, err) =>
                            Container(color: AppColors.surface),
                      ),
                      // Gradient overlay
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.2),
                              Colors.black.withOpacity(0.9),
                            ],
                            stops: const [0.4, 0.7, 1.0],
                          ),
                        ),
                      ),
                      // Bottom text info
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Tags
                            Wrap(
                              spacing: 6,
                              children: drama.tags.take(3).map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceLight.withOpacity(
                                      0.85,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                      fontFamily: 'Urbanist',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.gold,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 6),
                            // Title
                            Text(
                              drama.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Watch Now Button
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.primaryGradientStart,
                                        AppColors.primaryGradientEnd,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Watch Now',
                                        style: TextStyle(
                                          fontFamily: 'Urbanist',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (drama.totalEpisodes > 0 ||
                                    drama.viewCount.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    [
                                      if (drama.totalEpisodes > 0)
                                        '${drama.totalEpisodes} Episodes',
                                      if (drama.viewCount.isNotEmpty)
                                        '${drama.viewCount} views',
                                    ].join(' • '),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          options: CarouselOptions(
            height: 220,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 4),
            enlargeCenterPage: true,
            viewportFraction: 0.92,
            onPageChanged: (index, reason) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSmoothIndicator(
          activeIndex: _currentIndex,
          count: widget.dramas.length,
          effect: const ExpandingDotsEffect(
            dotHeight: 4,
            dotWidth: 6,
            expansionFactor: 3,
            activeDotColor: AppColors.primary,
            dotColor: AppColors.divider,
          ),
        ),
      ],
    );
  }
}
