import '../models/drama_model.dart';

class MockData {
  MockData._();

  static const List<CategoryModel> categories = [
    CategoryModel(id: 'trending', name: 'Trending 🔥'),
    CategoryModel(id: 'billionaire', name: 'Billionaire 💎'),
    CategoryModel(id: 'revenge', name: 'Revenge ⚔️'),
    CategoryModel(id: 'romance', name: 'Romance ❤️'),
    CategoryModel(id: 'urban', name: 'Urban Life 🏙️'),
    CategoryModel(id: 'werewolf', name: 'Fantasy 🌙'),
  ];

  static List<EpisodeModel> _generateEpisodes(String dramaId, int count) {
    return List.generate(count, (index) {
      final epNum = index + 1;
      return EpisodeModel(
        id: '${dramaId}_ep_$epNum',
        episodeNumber: epNum,
        title: 'Episode $epNum: The Turning Point',
        videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
        durationSeconds: 85 + (index * 3) % 40,
        isUnlocked: true,
      );
    });
  }

  static final List<DramaModel> featuredDramas = [
    DramaModel(
      id: 'd1',
      title: "The Billionaire's Hidden Identity",
      coverUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=600&q=80',
      bannerUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=1200&q=80',
      description: 'Banished from his empire 5 years ago, Adrian returns disguised as a humble driver to protect the woman who once saved his life.',
      tags: ['Billionaire', 'Revenge', 'Romance'],
      totalEpisodes: 88,
      viewCount: '12.4M',
      rating: 4.9,
      isTrending: true,
      episodes: _generateEpisodes('d1', 88),
    ),
    DramaModel(
      id: 'd2',
      title: 'Queen of the Underground',
      coverUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=600&q=80',
      bannerUrl: 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?auto=format&fit=crop&w=1200&q=80',
      description: 'Betrayed by her fiancé, Elena unmasks her true identity as the most feared syndicate boss in the metropolis.',
      tags: ['Action', 'Revenge', 'Strong Female'],
      totalEpisodes: 72,
      viewCount: '8.9M',
      rating: 4.8,
      isTrending: true,
      episodes: _generateEpisodes('d2', 72),
    ),
    DramaModel(
      id: 'd3',
      title: 'Double Life of the CEO Wife',
      coverUrl: 'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=600&q=80',
      bannerUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=1200&q=80',
      description: 'A quiet secretary by day, a world-class venture capitalist by night. Her arrogant boss has no idea who really signs his paychecks.',
      tags: ['Romance', 'Secret Identity', 'Office'],
      totalEpisodes: 65,
      viewCount: '15.1M',
      rating: 4.9,
      isTrending: true,
      episodes: _generateEpisodes('d3', 65),
    ),
  ];

  static final List<DramaModel> allDramas = [
    ...featuredDramas,
    DramaModel(
      id: 'd4',
      title: 'Reborn for Vengeance',
      coverUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=600&q=80',
      bannerUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=1200&q=80',
      description: 'Given a second chance at life, he will reclaim his family fortune and expose the traitors who ruined his lineage.',
      tags: ['Reborn', 'Revenge', 'Urban'],
      totalEpisodes: 90,
      viewCount: '6.2M',
      rating: 4.7,
      episodes: _generateEpisodes('d4', 90),
    ),
    DramaModel(
      id: 'd5',
      title: 'Contract Marriage with the Tycoon',
      coverUrl: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=600&q=80',
      bannerUrl: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=1200&q=80',
      description: 'It was strictly business for one year, until real feelings and dangerous secrets began to unravel their deal.',
      tags: ['Contract Marriage', 'Romance'],
      totalEpisodes: 60,
      viewCount: '11.8M',
      rating: 4.8,
      episodes: _generateEpisodes('d5', 60),
    ),
    DramaModel(
      id: 'd6',
      title: 'The Dragon God Returns',
      coverUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=600&q=80',
      bannerUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=1200&q=80',
      description: 'The supreme commander walks among mortals, hiding his supreme martial arts to live in peace—until his sister is threatened.',
      tags: ['Martial Arts', 'Hero', 'Action'],
      totalEpisodes: 85,
      viewCount: '14.2M',
      rating: 4.9,
      episodes: _generateEpisodes('d6', 85),
    ),
  ];
}
