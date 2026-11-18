class DramaModel {
  final String id;
  final String title;
  final String coverUrl;
  final String bannerUrl;
  final String description;
  final List<String> tags;
  final int totalEpisodes;
  final String viewCount;
  final double rating;
  final bool isTrending;
  final List<EpisodeModel> episodes;

  const DramaModel({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.bannerUrl,
    required this.description,
    required this.tags,
    required this.totalEpisodes,
    required this.viewCount,
    this.rating = 4.8,
    this.isTrending = false,
    this.episodes = const [],
  });
}

class EpisodeModel {
  final String id;
  final int episodeNumber;
  final String title;
  final String videoUrl;
  final int durationSeconds;
  final bool isUnlocked;

  const EpisodeModel({
    required this.id,
    required this.episodeNumber,
    required this.title,
    required this.videoUrl,
    this.durationSeconds = 90,
    this.isUnlocked = true,
  });
}

class CategoryModel {
  final String id;
  final String name;

  const CategoryModel({
    required this.id,
    required this.name,
  });
}
