import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/error_log_service.dart';
import '../../data/services/update_service.dart';
import '../../widgets/tag_preference_dialog.dart';
import '../player/player_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _cacheSizeText = 'Menghitung...';
  String _versionLabel = 'Memuat...';
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _calculateRealCacheSize();
    AppSettingsService.instance.addListener(_onSettingsChanged);
    // Muat versi terpasang asli (bukan hardcoded) untuk label versi.
    UpdateService.instance.ensureVersionLoaded().then((_) {
      if (mounted) {
        setState(() {
          final label = UpdateService.instance.currentVersionLabel;
          _versionLabel = label.isEmpty ? 'tidak diketahui' : label;
        });
      }
    });
  }

  @override
  void dispose() {
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// Ukuran cache NYATA: cache gambar (CachedNetworkImage) + sisa folder
  /// cache video lama (godrama_video_cache, ditinggal proxy yang dihapus).
  Future<void> _calculateRealCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      var bytes = 0;
      for (final name in ['libCachedImageData', 'godrama_video_cache']) {
        final dir = Directory('${tempDir.path}/$name');
        if (await dir.exists()) {
          await for (final e in dir.list(recursive: true)) {
            if (e is File) bytes += await e.length();
          }
        }
      }
      if (mounted) {
        setState(() {
          if (bytes < 1024) {
            _cacheSizeText = '$bytes B';
          } else if (bytes < 1024 * 1024) {
            _cacheSizeText = '${(bytes / 1024).toStringAsFixed(1)} KB';
          } else {
            _cacheSizeText = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          }
        });
      }
    } catch (e) {
      debugPrint('[ProfileScreen] Gagal hitung cache: $e');
      if (mounted) setState(() => _cacheSizeText = '0.0 KB');
    }
  }

  /// Bersihkan cache gambar + folder cache video lama (bila masih ada).
  Future<void> _clearCache() async {
    setState(() => _isClearingCache = true);
    try {
      await DefaultCacheManager().emptyCache();
      final tempDir = await getTemporaryDirectory();
      final legacy = Directory('${tempDir.path}/godrama_video_cache');
      if (await legacy.exists()) {
        await legacy.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[ProfileScreen] Gagal bersihkan cache: $e');
    }
    await _calculateRealCacheSize();
    if (mounted) {
      setState(() => _isClearingCache = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1E232E),
          content: Text('Cache gambar berhasil dibersihkan!'),
        ),
      );
    }
  }

  /// Sheet log error lokal (20 entri terakhir, terbaru dulu).
  Future<void> _showErrorLogSheet() async {
    final entries = await ErrorLogService.entries();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Log Error',
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await ErrorLogService.clear();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text(
                          'Hapus Log',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(
                            child: Text(
                              'Tidak ada error tercatat.',
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const Divider(
                              color: AppColors.divider,
                              height: 1,
                            ),
                            itemBuilder: (_, i) {
                              final e = entries[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '[${e['tag'] ?? '?'}] ${e['message'] ?? ''}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                subtitle: Text(
                                  (e['ts'] ?? '').toString(),
                                  style: const TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsService.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 12),
            // Header profil — ketuk di mana saja untuk ubah nama.
            GestureDetector(
              onTap: _showEditProfileDialog,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        AppAssets.icAvatar,
                        width: 40,
                        height: 40,
                        colorFilter: const ColorFilter.mode(
                          AppColors.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                settings.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.edit_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'User ID: ${settings.userId}',
                          style: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Statistik — ketuk untuk membuka daftarnya.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider, width: 0.8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    count: '${settings.watchHistory.length}',
                    label: 'Riwayat Nonton',
                    onTap: _showWatchHistorySheet,
                  ),
                  _StatItem(
                    count: '${settings.favoriteIds.length}',
                    label: 'Favorit Saya',
                    onTap: _showFavoritesSheet,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Pemutaran
            const Text(
              'Pemutaran',
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider, width: 0.8),
              ),
              child: Column(
                children: [
                  // Preferensi Tema Drama (Untukmu & For You)
                  _buildMenuItem(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Preferensi Tema Drama',
                    subtitle: settings.preferredTags.isEmpty
                        ? 'Semua Tema (Default)'
                        : '${settings.preferredTags.length} Tema Dipilih',
                    onTap: () async {
                      await TagPreferenceDialog.show(context);
                      setState(() {});
                    },
                  ),
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Kualitas video — satu-satunya pengatur resolusi
                  // (pilih 480p bila ingin hemat kuota).
                  _buildMenuItem(
                    icon: Icons.hd_rounded,
                    title: 'Kualitas Video',
                    subtitle: settings.defaultQuality,
                    onTap: _showQualitySettingsSheet,
                  ),
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Auto Play Next Switch
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.playlist_play_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    activeColor: AppColors.primary,
                    title: const Text(
                      'Putar Otomatis',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: const Text(
                      'Lanjut otomatis ke episode berikutnya',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    value: settings.autoPlayNext,
                    onChanged: (val) {
                      settings.toggleAutoPlayNext(val);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Aplikasi
            const Text(
              'Aplikasi',
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider, width: 0.8),
              ),
              child: Column(
                children: [
                  // Bersihkan Cache (cache gambar + sisa cache lama)
                  _buildMenuItem(
                    icon: Icons.cleaning_services_rounded,
                    title: 'Bersihkan Cache',
                    subtitle: _isClearingCache
                        ? 'Sedang membersihkan...'
                        : _cacheSizeText,
                    onTap: _isClearingCache ? () {} : _clearCache,
                  ),
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Periksa Pembaruan
                  _buildMenuItem(
                    icon: Icons.system_update_rounded,
                    title: 'Periksa Pembaruan',
                    subtitle: _versionLabel,
                    onTap: () {
                      UpdateService.instance.checkForUpdate(
                        context,
                        silent: false,
                      );
                    },
                  ),
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Bantuan & Umpan Balik
                  _buildMenuItem(
                    icon: Icons.feedback_outlined,
                    title: 'Bantuan & Masukan',
                    subtitle: 'Laporkan masalah atau kirim saran',
                    onTap: _showFeedbackDialog,
                  ),
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Tentang GoDrama (info aplikasi + Log Error tersembunyi)
                  _buildMenuItem(
                    icon: Icons.info_outline_rounded,
                    title: 'Tentang GoDrama',
                    subtitle: 'Tentang aplikasi ini',
                    onTap: _showAboutDialog,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog() {
    final controller = TextEditingController(
      text: AppSettingsService.instance.userName,
    );
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E232E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Ubah Nama Profil',
            style: TextStyle(color: Colors.white, fontFamily: 'Urbanist'),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Masukkan nama pengguna...',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Batal',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  AppSettingsService.instance.updateProfileName(
                    controller.text.trim(),
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _showQualitySettingsSheet() {
    final qualities = ['1080p', '720p', '480p'];
    final current = AppSettingsService.instance.defaultQuality;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Kualitas Video',
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ...qualities.map((q) {
                  final isSelected = q == current;
                  return ListTile(
                    leading: Icon(
                      Icons.hd_rounded,
                      color: isSelected ? AppColors.primary : Colors.white60,
                    ),
                    title: Text(
                      q == '1080p'
                          ? '1080p · Full HD'
                          : q == '720p'
                          ? '720p · HD'
                          : '480p · Hemat kuota',
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      AppSettingsService.instance.setDefaultQuality(q);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showWatchHistorySheet() {
    final history = AppSettingsService.instance.historyEntries;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Riwayat Tontonan',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Urbanist',
                        ),
                      ),
                      if (history.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            AppSettingsService.instance.clearWatchHistory();
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            'Hapus Semua',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  if (history.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Belum ada riwayat tontonan',
                          style: TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Urbanist',
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: history.length,
                        itemBuilder: (context, idx) {
                          final entry = history[idx];
                          final drama = entry.drama;
                          final epLabel = drama.totalEpisodes > 0
                              ? 'Ep. ${entry.progress.episodeIndex + 1} / ${drama.totalEpisodes}'
                              : 'Ep. ${entry.progress.episodeIndex + 1}';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                drama.coverUrl,
                                width: 44,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade900,
                                  width: 44,
                                  height: 56,
                                ),
                              ),
                            ),
                            title: Text(
                              drama.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '$epLabel • ${drama.category}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.play_circle_fill_rounded,
                              color: AppColors.primary,
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlayerScreen(
                                    drama: drama,
                                    initialEpisodeIndex:
                                        entry.progress.episodeIndex,
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
          },
        );
      },
    );
  }

  void _showFavoritesSheet() {
    // Favorit tersimpan sebagai objek drama lengkap — tidak perlu lagi
    // dicocokkan dengan riwayat, dan tidak ada lagi baris "Drama ID: xxx".
    final favDramas = AppSettingsService.instance.favoriteDramas;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Drama Favorit Saya (${favDramas.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Urbanist',
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  if (favDramas.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Belum ada drama favorit tersimpan.\nKlik ikon hati di video untuk menyimpan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Urbanist',
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: favDramas.length,
                        itemBuilder: (context, idx) {
                          final drama = favDramas[idx];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                drama.coverUrl,
                                width: 44,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade900,
                                  width: 44,
                                  height: 56,
                                ),
                              ),
                            ),
                            title: Text(
                              drama.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              drama.totalEpisodes > 0
                                  ? '${drama.totalEpisodes} Episode'
                                  : drama.category,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.play_circle_fill_rounded,
                              color: AppColors.primary,
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlayerScreen(drama: drama),
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
          },
        );
      },
    );
  }

  void _showFeedbackDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E232E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Bantuan & Masukan',
            style: TextStyle(color: Colors.white, fontFamily: 'Urbanist'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ada video error atau punya saran fitur? Tulis pesan Anda — '
                'tombol Kirim membukanya sebagai issue GitHub repo GoDrama:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Tulis kendala Anda...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF12141C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Batal',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final message = textController.text.trim();
                Navigator.pop(ctx);
                if (message.isEmpty) return;
                // Masukan dikirim betulan: dibuka sebagai issue GitHub
                // (perlu login GitHub di browser untuk submit).
                final uri = Uri.https(
                  'github.com',
                  '/Celosz-fle7/GODrama/issues/new',
                  {
                    'title': 'Masukan dari aplikasi GoDrama',
                    'body': '$message\n\n---\nVersi aplikasi: $_versionLabel',
                  },
                );
                final launched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!launched && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(0xFF1E232E),
                      content: Text(
                        'Gagal membuka browser untuk mengirim masukan.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E232E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Tentang GoDrama',
            style: TextStyle(color: Colors.white, fontFamily: 'Urbanist'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Streaming drama pendek — tanpa iklan, tanpa ribet.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Versi $_versionLabel',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12),
              // Log Error disembunyikan di sini: alat debugging, bukan
              // menu user — tetap terjangkau bila dibutuhkan.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.bug_report_outlined,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                title: const Text(
                  'Log Error',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  '20 error terakhir, untuk debugging',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showErrorLogSheet();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Tutup',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Urbanist',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontFamily: 'Urbanist',
          fontSize: 11,
          color: AppColors.textMuted,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

class _StatItem extends StatelessWidget {
  final String count;
  final String label;
  final VoidCallback? onTap;

  const _StatItem({required this.count, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(
            count,
            style: const TextStyle(
              fontFamily: 'Urbanist',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Urbanist',
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
