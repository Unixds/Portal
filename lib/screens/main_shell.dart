import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/portal_theme.dart';
import '../models/portal_models.dart';
import '../services/firebase_service.dart';
import 'chats/chats_screen.dart';
import 'profile/profile_screen.dart';
import 'settings/settings_screen.dart';
import 'global_search_screen.dart';
import 'calls/call_screen.dart';
import '../services/music_service.dart';
import 'music/music_screen.dart';
import 'contacts_screen.dart';
import '../widgets/double_chat_icon.dart';


/// Main Shell hosting the iOS Telegram Liquid Glass Floating Bottom Navigation Bar
/// with interactive unclipped expanding bubble indicator and zero overflow layout.
class MainShell extends StatefulWidget {
  final VoidCallback onSignOut;
  const MainShell({super.key, required this.onSignOut});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  StreamSubscription<CallModel?>? _incomingCallSub;
  String? _activeIncomingCallId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PortalBackendService.instance.updateUserPresence(true);
    _listenToIncomingCalls();
  }

  void _listenToIncomingCalls() {
    final currentUser = PortalBackendService.instance.currentUser;
    if (currentUser == null) return;

    _incomingCallSub = PortalBackendService.instance
        .listenToIncomingCall(currentUser.uid)
        .listen((incomingCall) {
      if (incomingCall != null &&
          incomingCall.status == 'calling' &&
          incomingCall.callId != _activeIncomingCallId) {
        _activeIncomingCallId = incomingCall.callId;

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CallScreen(
                call: incomingCall,
                isIncoming: true,
              ),
            ),
          ).then((_) {
            _activeIncomingCallId = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
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

  void _openSearchScreen() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const GlobalSearchScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PortalMusicService.instance,
      builder: (context, _) {
        final isMusicEnabled = PortalMusicService.instance.isMusicSectionEnabled;

        final screens = [
          const ChatsScreen(),
          if (isMusicEnabled) const MusicSectionScreen() else const ContactsScreen(),
          ProfileScreen(onSignOut: widget.onSignOut),
          SettingsScreen(onSignOut: widget.onSignOut),
        ];

        final maxIndex = screens.length - 1;
        final safeIndex = _currentIndex.clamp(0, maxIndex);

        return Scaffold(
          backgroundColor: PortalTheme.bgCanvas,
          extendBody: true,
          body: IndexedStack(
            index: safeIndex,
            children: screens,
          ),

          // Floating iOS Liquid Glass Bottom Navigation Bar
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
            child: PortalDraggableNavBar(
              selectedIndex: safeIndex,
              isMusicEnabled: isMusicEnabled,
              onTabSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              onSearchTap: _openSearchScreen,
            ),
          ),
        );
      },
    );
  }
}

/// Custom Draggable Liquid Bubble Navigation Bar Widget
class PortalDraggableNavBar extends StatefulWidget {
  final int selectedIndex;
  final bool isMusicEnabled;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSearchTap;

  const PortalDraggableNavBar({
    super.key,
    required this.selectedIndex,
    required this.isMusicEnabled,
    required this.onTabSelected,
    required this.onSearchTap,
  });

  @override
  State<PortalDraggableNavBar> createState() => _PortalDraggableNavBarState();
}

class _PortalDraggableNavBarState extends State<PortalDraggableNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  double _dragPosition = 0.0;
  bool _isDragging = false;
  bool _isSearchPressed = false;

  List<({IconData icon, IconData activeIcon, String label})> get items => [
        const (icon: Icons.forum_outlined, activeIcon: Icons.forum_rounded, label: 'Чаты'),
        if (widget.isMusicEnabled)
          const (icon: Icons.music_note_outlined, activeIcon: Icons.music_note_rounded, label: 'Музыка')
        else
          const (icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, label: 'Контакты'),
        const (icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Вы'),
        const (icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Настройки'),
      ];

  @override
  void initState() {
    super.initState();
    _dragPosition = widget.selectedIndex.toDouble();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = AlwaysStoppedAnimation(_dragPosition);
  }

  @override
  void didUpdateWidget(covariant PortalDraggableNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && !_isDragging) {
      _animateToPosition(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateToPosition(double target) {
    _animController.stop();
    _animation = Tween<double>(begin: _dragPosition, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _dragPosition = _animation.value;
        });
      });
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final tabCount = items.length;

    return Row(
      children: [
        // 1. Tab Capsule Container with Unclipped Expanding Fluid Glass Bubble
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final tabWidth = totalWidth / tabCount;

              return GestureDetector(
                onPanDown: (details) {
                  HapticFeedback.selectionClick();
                  _animController.stop();
                  setState(() {
                    _isDragging = true;
                  });
                  final x = details.localPosition.dx;
                  final pos = ((x - tabWidth / 2) / tabWidth).clamp(0.0, (tabCount - 1).toDouble());
                  setState(() {
                    _dragPosition = pos;
                  });
                },
                onPanUpdate: (details) {
                  final x = details.localPosition.dx;
                  final pos = ((x - tabWidth / 2) / tabWidth).clamp(0.0, (tabCount - 1).toDouble());
                  setState(() {
                    _dragPosition = pos;
                  });
                },
                onPanEnd: (details) {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _isDragging = false;
                  });
                  final target = _dragPosition.round().clamp(0, tabCount - 1);
                  _animateToPosition(target.toDouble());
                  widget.onTabSelected(target);
                },
                onPanCancel: () {
                  setState(() {
                    _isDragging = false;
                  });
                  _animateToPosition(widget.selectedIndex.toDouble());
                },
                child: SizedBox(
                  height: 64,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      // A. Capsule Glass Background (Clipped cleanly to rounded capsule shape)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(36),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E22).withOpacity(0.92),
                                borderRadius: BorderRadius.circular(36),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.12),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.55),
                                    blurRadius: 32,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // B. Draggable Translucent Expanding Glass Bubble
                      Positioned(
                        left: (_dragPosition * tabWidth) + 3,
                        width: tabWidth - 6,
                        top: 4,
                        bottom: 4,
                        child: AnimatedScale(
                          scale: _isDragging ? 1.22 : 1.0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: _isDragging
                                  ? Colors.white.withOpacity(0.24)
                                  : Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withOpacity(_isDragging ? 0.38 : 0.22),
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(_isDragging ? 0.35 : 0.15),
                                  blurRadius: _isDragging ? 18 : 10,
                                  spreadRadius: _isDragging ? 1 : 0,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // C. Row of Tabs
                      Positioned.fill(
                        child: Row(
                          children: List.generate(tabCount, (index) {
                            final dist = (_dragPosition - index).abs();
                            final isActive = dist < 0.5;

                            // Color interpolation towards Telegram vibrant blue (#3390EC)
                            const activeColor = Color(0xFF3390EC);
                            const inactiveColor = Color(0xFF8E8E93);
                            final color = Color.lerp(
                              activeColor,
                              inactiveColor,
                              dist.clamp(0.0, 1.0),
                            )!;

                            return Expanded(
                              child: InkWell(
                                onTapDown: (_) {
                                  HapticFeedback.selectionClick();
                                  _animController.stop();
                                  _animateToPosition(index.toDouble());
                                  widget.onTabSelected(index);
                                },
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (index == 0)
                                      DoubleChatBubbleIcon(color: color, size: 22)
                                    else
                                      Icon(
                                        isActive ? items[index].activeIcon : items[index].icon,
                                        color: color,
                                        size: 22,
                                      ),
                                    const SizedBox(height: 2),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        items[index].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(width: 10),

        // 2. Circular Search Button on the Right with Interactive iOS Press Scale Animation
        GestureDetector(
          onTapDown: (_) {
            HapticFeedback.lightImpact();
            setState(() {
              _isSearchPressed = true;
            });
          },
          onTapUp: (_) {
            setState(() {
              _isSearchPressed = false;
            });
            widget.onSearchTap();
          },
          onTapCancel: () {
            setState(() {
              _isSearchPressed = false;
            });
          },
          child: AnimatedScale(
            scale: _isSearchPressed ? 0.90 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _isSearchPressed
                        ? Colors.white.withOpacity(0.24)
                        : Colors.white.withOpacity(0.09),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(_isSearchPressed ? 0.32 : 0.16),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.search_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
