import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../data/services/app_settings_service.dart';

class TagPreferenceDialog extends StatefulWidget {
  final bool isFirstLaunch;

  const TagPreferenceDialog({super.key, this.isFirstLaunch = false});

  static Future<void> show(
    BuildContext context, {
    bool isFirstLaunch = false,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: !isFirstLaunch,
      builder: (context) => TagPreferenceDialog(isFirstLaunch: isFirstLaunch),
    );
  }

  @override
  State<TagPreferenceDialog> createState() => _TagPreferenceDialogState();
}

class _TagPreferenceDialogState extends State<TagPreferenceDialog> {
  late final Set<String> _selectedTags;

  @override
  void initState() {
    super.initState();
    final existing = AppSettingsService.instance.preferredTags;
    if (existing.isEmpty && widget.isFirstLaunch) {
      // Pada saat pertama install, default pilih semua tema agar penonton
      // mendapatkan seluruh variasi konten berkualitas
      _selectedTags = AppSettingsService.availableThemeTags
          .map((t) => t['id']!)
          .toSet();
    } else {
      _selectedTags = Set.from(existing);
    }
  }

  void _toggleAll() {
    setState(() {
      if (_selectedTags.length ==
          AppSettingsService.availableThemeTags.length) {
        _selectedTags.clear();
      } else {
        _selectedTags
          ..clear()
          ..addAll(AppSettingsService.availableThemeTags.map((t) => t['id']!));
      }
    });
  }

  Future<void> _save() async {
    await AppSettingsService.instance.savePreferredTags(
      _selectedTags,
      markOnboarding: true,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _selectedTags.length == AppSettingsService.availableThemeTags.length;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isFirstLaunch
                            ? 'Pilih Tema Favoritmu'
                            : 'Ubah Preferensi Tema',
                        style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pilihanmu mengatur rekomendasi di tab Untukmu & For You',
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 12,
                          color: AppColors.textSecondary.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isFirstLaunch)
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Tombol Shortcut Pilih Semua / Kosongkan
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedTags.length} tema dipilih',
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                GestureDetector(
                  onTap: _toggleAll,
                  child: Text(
                    allSelected ? 'Kosongkan Semua' : 'Pilih Semua',
                    style: const TextStyle(
                      fontFamily: 'Urbanist',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Grid Tag Pilihan Tema
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: AppSettingsService.availableThemeTags.map((t) {
                    final id = t['id']!;
                    final label = t['label']!;
                    final icon = t['icon']!;
                    final isChecked = _selectedTags.contains(id);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isChecked) {
                            _selectedTags.remove(id);
                          } else {
                            _selectedTags.add(id);
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isChecked
                              ? AppColors.primary
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isChecked
                                ? AppColors.primary
                                : AppColors.divider,
                            width: 1,
                          ),
                          boxShadow: isChecked
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(icon, style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 13,
                                fontWeight: isChecked
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isChecked
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Tombol Simpan
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  widget.isFirstLaunch
                      ? 'Mulai Nonton Drama'
                      : 'Simpan Preferensi',
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
