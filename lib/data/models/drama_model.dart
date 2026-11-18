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

  DramaModel copyWith({
    String? id,
    String? title,
    String? coverUrl,
    String? bannerUrl,
    String? description,
    List<String>? tags,
    int? totalEpisodes,
    String? viewCount,
    double? rating,
    bool? isTrending,
    List<EpisodeModel>? episodes,
  }) {
    return DramaModel(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      viewCount: viewCount ?? this.viewCount,
      rating: rating ?? this.rating,
      isTrending: isTrending ?? this.isTrending,
      episodes: episodes ?? this.episodes,
    );
  }
}

class EpisodeModel {
  final String id;
  final int episodeNumber;
  final String title;
  final String videoUrl;
  final int durationSeconds;
  final bool isUnlocked;
  final Map<String, String> resolutions;
  final String? subtitleUrl;

  const EpisodeModel({
    required this.id,
    required this.episodeNumber,
    required this.title,
    required this.videoUrl,
    this.durationSeconds = 90,
    this.isUnlocked = true,
    this.resolutions = const {},
    this.subtitleUrl,
  });

  String getUrlForQuality(String quality) {
    if (resolutions.containsKey(quality)) {
      return resolutions[quality]!;
    }
    return videoUrl;
  }
}

class CategoryModel {
  final String id;
  final String name;

  const CategoryModel({
    required this.id,
    required this.name,
  });
}
