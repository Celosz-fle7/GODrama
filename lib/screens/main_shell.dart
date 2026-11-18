import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_assets.dart';
import '../data/services/update_service.dart';
import 'home/home_screen.dart';
import 'for_you/for_you_screen.dart';
import 'my_list/my_list_screen.dart';
import 'profile/profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // Buka pertama kali langsung ke tab For You (feed vertikal reel)
  int _currentIndex = 1;

  @override
  void initState() {
    super.initState();
    // Auto check update di awal saat aplikasi dibuka
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.instance.checkForUpdate(context, silent: true);
    });
  }

  final List<Widget> _pages = const [
    HomeScreen(),
    ForYouScreen(),
    MyListScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  label: 'Discover',
                  activeIcon: AppAssets.navDiscoverActive,
                  inactiveIcon: AppAssets.navDiscoverInactive,
                ),
                _buildNavItem(
                  index: 1,
                  label: 'For You',
                  activeIcon: AppAssets.navForYouActive,
                  inactiveIcon: AppAssets.navForYouInactive,
                ),
                _buildNavItem(
                  index: 2,
                  label: 'My List',
                  activeIcon: AppAssets.navMyListActive,
                  inactiveIcon: AppAssets.navMyListInactive,
                ),
                _buildNavItem(
                  index: 3,
                  label: 'Profile',
                  activeIcon: AppAssets.navProfileActive,
                  inactiveIcon: AppAssets.navProfileInactive,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required String activeIcon,
    required String inactiveIcon,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            isSelected ? activeIcon : inactiveIcon,
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
