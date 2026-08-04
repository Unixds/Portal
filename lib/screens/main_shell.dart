import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/portal_theme.dart';
import '../services/firebase_service.dart';
import 'chats/chats_screen.dart';
import 'settings/settings_screen.dart';

/// Main Shell hosting the iOS Telegram Liquid Glass Floating Bottom Navigation Bar.
class MainShell extends StatefulWidget {
  final VoidCallback onSignOut;
  const MainShell({super.key, required this.onSignOut});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PortalBackendService.instance.updateUserPresence(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PortalBackendService.instance.updateUserPresence(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PortalBackendService.instance.updateUserPresence(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      PortalBackendService.instance.updateUserPresence(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const ChatsScreen(),
      SettingsScreen(onSignOut: widget.onSignOut),
    ];

    return Scaffold(
      backgroundColor: PortalTheme.bgCanvas,
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),

      // Floating iOS Liquid Glass Bottom Navigation Bar
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.09),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: Colors.white.withOpacity(0.16), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    index: 0,
                    icon: Icons.chat_bubble_outline_rounded,
                    activeIcon: Icons.chat_bubble_rounded,
                    label: 'Чаты',
                  ),
                  _buildNavItem(
                    index: 1,
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_rounded,
                    label: 'Настройки',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.white.withOpacity(0.25) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? Colors.white : Colors.white54,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
