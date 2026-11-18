import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import '../../core/player/smart_stream_proxy.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/update_service.dart';
import '../player/player_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _cacheSizeText = 'Menghitung...';
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _calculateRealCacheSize();
    AppSettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _calculateRealCacheSize() async {
    try {
      final bytes = await SmartStreamProxy.instance.getCacheSize();
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
    } catch (_) {
      if (mounted) setState(() => _cacheSizeText = '0.0 KB');
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isClearingCache = true);
    await SmartStreamProxy.instance.clearCache();
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        _isClearingCache = false;
        _cacheSizeText = '0.0 KB';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1E232E),
          content: Text(
            'Seluruh video cache dan temporary data berhasil dibersihkan!',
          ),
        ),
      );
    }
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
            // User Header
            Row(
              children: [
                GestureDetector(
                  onTap: _showEditProfileDialog,
                  child: Container(
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
                          GestureDetector(
                            onTap: _showEditProfileDialog,
                            child: const Icon(
                              Icons.edit_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
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

            const SizedBox(height: 24),

            // Real Stats Card (Interaktif)
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
                  _StatItem(
                    count: 'VIP',
                    label: 'Status Akses',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF1E232E),
                          content: Text(
                            'Akses VIP Seumur Hidup: Bebas Iklan & Pure Protocol.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Pengaturan Streaming & Media
            const Text(
              'Pengaturan Streaming & Media',
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
                  // Default Quality Selector
                  _buildMenuItem(
                    icon: Icons.hd_rounded,
                    title: 'Kualitas Streaming Default',
                    subtitle: 'Resolusi aktif: ${settings.defaultQuality}',
                    onTap: _showQualitySettingsSheet,
                  ),
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Data Saver Mode Switch
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
                        Icons.data_saver_on_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    activeColor: AppColors.primary,
                    title: const Text(
                      'Mode Hemat Kuota',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: const Text(
                      'Otomatis batasi resolusi ke 480p saat streaming',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    value: settings.dataSaverMode,
                    onChanged: (val) {
                      settings.toggleDataSaver(val);
                    },
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
                      'Putar Otomatis Episode Berikutnya',
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: const Text(
                      'Lanjut ke episode selanjutnya tanpa jeda di pemutar',
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
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Bahasa & Sulih Suara
                  _buildMenuItem(
                    icon: Icons.translate_rounded,
                    title: 'Bahasa & Sulih Suara',
                    subtitle: settings.selectedLanguage,
                    onTap: _showLanguageSettingsSheet,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Pengaturan Aplikasi & Sistem
            const Text(
              'Pengaturan Sistem & Penyimpanan',
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
                  // Riwayat Tontonan
                  _buildMenuItem(
                    icon: Icons.history_rounded,
                    title: 'Riwayat Tontonan',
                    subtitle:
                        '${settings.watchHistory.length} drama telah ditonton',
                    onTap: _showWatchHistorySheet,
                  ),
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Pembersihan Cache Nyata
                  _buildMenuItem(
                    icon: Icons.cleaning_services_rounded,
                    title: 'Bersihkan Cache Video',
                    subtitle: _isClearingCache
                        ? 'Sedang membersihkan...'
                        : 'Ukuran cache saat ini: $_cacheSizeText',
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
                    subtitle: 'GoDrama v1.0.1 (Cek rilis terbaru)',
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
                    title: 'Bantuan & Laporkan Masalah',
                    subtitle: 'Kirim masukan atau laporkan masalah video',
                    onTap: _showFeedbackDialog,
                  ),
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 52,
                  ),

                  // Tentang GoDrama
                  _buildMenuItem(
                    icon: Icons.info_outline_rounded,
                    title: 'Tentang GoDrama',
                    subtitle: 'v1.0.1 (Clean Architecture & Pure Protocol)',
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
                  'Kualitas Pemutaran Default',
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
                          ? '1080p Full HD (Kualitas Tinggi)'
                          : q == '720p'
                          ? '720p HD Standard (Direkomendasikan)'
                          : '480p Hemat Kuota (Streaming Cepat)',
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

  void _showLanguageSettingsSheet() {
    final languages = ['Bahasa Indonesia', 'English'];
    final current = AppSettingsService.instance.selectedLanguage;

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
                  'Pilihan Bahasa & Sulih Suara',
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ...languages.map((lang) {
                  final isSelected = lang == current;
                  return ListTile(
                    leading: Icon(
                      Icons.language_rounded,
                      color: isSelected ? AppColors.primary : Colors.white60,
                    ),
                    title: Text(
                      lang == 'Bahasa Indonesia'
                          ? 'Bahasa Indonesia (Sulih Suara Resmi)'
                          : 'English (Original Audio)',
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
                      AppSettingsService.instance.setSelectedLanguage(lang);
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
    final history = AppSettingsService.instance.watchHistory;

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
                          final drama = history[idx];
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
                              '${drama.totalEpisodes} Episode • ${drama.category}',
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

  void _showFavoritesSheet() {
    final favIds = AppSettingsService.instance.favoriteIds;
    final history = AppSettingsService.instance.watchHistory;
    final favDramas = history.where((d) => favIds.contains(d.id)).toList();

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
                        'Drama Favorit Saya (${favIds.length})',
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
                  if (favIds.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Belum ada drama favorit tersimpan.\nKlik ikon bookmark di video untuk menyimpan.',
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
                        itemCount: favDramas.isNotEmpty
                            ? favDramas.length
                            : favIds.length,
                        itemBuilder: (context, idx) {
                          if (favDramas.isNotEmpty) {
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
                                '${drama.totalEpisodes} Episode',
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
                          } else {
                            final dramaId = favIds.elementAt(idx);
                            return ListTile(
                              leading: const Icon(
                                Icons.bookmark_rounded,
                                color: Color(0xFFFF3366),
                              ),
                              title: Text(
                                'Drama ID: $dramaId',
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: const Text(
                                'Tersimpan di daftar favorit',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }
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
                'Ada video error atau punya saran fitur? Tulis pesan Anda di bawah:',
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
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF1E232E),
                    content: Text(
                      'Terima kasih! Laporan masukan Anda telah kami terima.',
                    ),
                  ),
                );
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
          title: const Row(
            children: [
              Icon(
                Icons.movie_filter_rounded,
                color: Color(0xFFFF3366),
                size: 28,
              ),
              SizedBox(width: 10),
              Text(
                'Tentang GoDrama',
                style: TextStyle(color: Colors.white, fontFamily: 'Urbanist'),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GoDrama - Pure Protocol Edition',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Aplikasi streaming drama pendek berperforma tinggi dengan arsitektur bersih tanpa bloatware iklan.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 12),
              Divider(color: Colors.white12),
              SizedBox(height: 6),
              Text(
                '• Versi: v1.0.1 (Release Universal)',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              SizedBox(height: 4),
              Text(
                '• Gateway: Transsion Istio-Envoy CDN',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              SizedBox(height: 4),
              Text(
                '• Decoder: HTTP 206 Multi-Resolution Range',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              SizedBox(height: 4),
              Text(
                '• Status: Bebas Iklan & Bebas Izin Mencurigakan',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Tutup'),
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
