class DramaModel {
  final String id;
  final String title;
  final String coverUrl;
  final String bannerUrl;
  final String description;
  final List<String> tags;
  final int totalEpisodes;
  // Kosong bila server tidak memberi angka penonton — jangan diisi angka acak.
  final String viewCount;
  // null bila server tidak memberi rating — jangan diisi angka acak.
  final double? rating;
  final bool isTrending;
  final List<EpisodeModel> episodes;

  String get category => tags.isNotEmpty ? tags.first : 'Drama';

  const DramaModel({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.bannerUrl,
    required this.description,
    required this.tags,
    required this.totalEpisodes,
    required this.viewCount,
    this.rating,
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

  /// Serialisasi untuk penyimpanan lokal (riwayat/favorit).
  /// Daftar episode tidak disimpan — URL stream bisa basi, selalu fetch ulang.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'coverUrl': coverUrl,
      'bannerUrl': bannerUrl,
      'description': description,
      'tags': tags,
      'totalEpisodes': totalEpisodes,
      'viewCount': viewCount,
      'rating': rating,
      'isTrending': isTrending,
    };
  }

  factory DramaModel.fromJson(Map<String, dynamic> json) {
    return DramaModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Short Drama',
      coverUrl: json['coverUrl']?.toString() ?? '',
      bannerUrl: json['bannerUrl']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      tags: (json['tags'] as List?)?.map((t) => t.toString()).toList() ??
          const [],
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt() ?? 0,
      viewCount: json['viewCount']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toDouble(),
      isTrending: json['isTrending'] == true,
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

  const EpisodeModel({
    required this.id,
    required this.episodeNumber,
    required this.title,
    required this.videoUrl,
    this.durationSeconds = 90,
    this.isUnlocked = true,
    this.resolutions = const {},
  });

  String getUrlForQuality(String quality) {
    if (resolutions.containsKey(quality)) {
      return resolutions[quality]!;
    }
    return videoUrl;
  }

  /// Resolusi yang benar-benar tersedia untuk episode ini (dari peta
  /// resolutions server), dari tertinggi ke terendah. Picker kualitas
  /// memakai ini — jangan tampilkan resolusi yang tidak ada URL-nya.
  List<String> get availableQualities {
    final keys = resolutions.keys.toList();
    keys.sort(
      (a, b) => _resolutionValue(b).compareTo(_resolutionValue(a)),
    );
    return keys;
  }

  static int _resolutionValue(String label) {
    final digits = label.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }
}

class CategoryModel {
  final String id;
  final String name;

  const CategoryModel({required this.id, required this.name});
}
