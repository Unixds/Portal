import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/portal_theme.dart';
import '../../services/firebase_service.dart';
import 'edit_profile_screen.dart';
import 'sections_screen.dart';
import '../music/music_screen.dart';

/// Settings & User Profile Screen with Telegram iOS Expanding Sharp Cover Avatar Header
/// and Liquid Glass Cards.
class SettingsScreen extends StatefulWidget {
  final VoidCallback onSignOut;
  const SettingsScreen({super.key, required this.onSignOut});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isHeaderExpanded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final offset = _scrollController.offset;
      if (offset < -35 && !_isHeaderExpanded) {
        setState(() => _isHeaderExpanded = true);
      } else if (offset > 45 && _isHeaderExpanded) {
        setState(() => _isHeaderExpanded = false);
      }
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          final base64Str = base64Encode(file.bytes!);
          final ext = file.extension?.toLowerCase() ?? 'jpeg';
          final newAvatarUrl = 'data:image/$ext;base64,$base64Str';

          final currentUser = PortalBackendService.instance.currentUser;
          if (currentUser != null) {
            await PortalBackendService.instance.updateUserProfile(
              name: currentUser.name,
              username: currentUser.username,
              avatarUrl: newAvatarUrl,
              bio: currentUser.bio,
            );
            setState(() {});
          }
        }
      }
    } catch (e) {
      debugPrint('Pick photo error: $e');
    }
  }

  ImageProvider _buildAvatarImageProvider(String url) {
    if (url.startsWith('data:image')) {
      try {
        final base64Data = url.split(',').last;
        final bytes = base64Decode(base64Data);
        return MemoryImage(bytes);
      } catch (_) {}
    }
    return NetworkImage(url.isNotEmpty
        ? url
        : 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=800&q=80');
  }

  void _openAddAccountDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String? errorText;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Добавить аккаунт', style: PortalTheme.titleHeader(fontSize: 22, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('Введи @username и облачный пароль от второго аккаунта',
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white54)),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        Text('@', style: GoogleFonts.inter(fontSize: 18, color: Colors.white54)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: usernameController,
                            style: GoogleFonts.inter(fontSize: 16, color: Colors.white),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'username',
                              hintStyle: TextStyle(color: Colors.white30),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: GoogleFonts.inter(fontSize: 16, color: Colors.white),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Облачный пароль',
                        hintStyle: TextStyle(color: Colors.white30),
                      ),
                    ),
                  ),

                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(errorText!, style: GoogleFonts.inter(fontSize: 13, color: PortalTheme.roseAccent)),
                  ],

                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: isLoading
                        ? null
                        : () async {
                            final u = usernameController.text.trim();
                            final p = passwordController.text.trim();
                            if (u.isEmpty || p.isEmpty) return;

                            setModalState(() {
                              isLoading = true;
                              errorText = null;
                            });

                            final user = await PortalBackendService.instance.loginWithUsernameAndPassword(
                              username: u,
                              password: p,
                            );

                            setModalState(() => isLoading = false);

                            if (user != null) {
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) setState(() {});
                            } else {
                              setModalState(() {
                                errorText = 'Неверный @username или пароль';
                              });
                            }
                          },
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Center(
                        child: isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                            : Text(
                                'Добавить',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
                              ),
                      ),
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
    final user = PortalBackendService.instance.currentUser;
    final activeAccounts = PortalBackendService.instance.activeAccounts;
    final avatarProvider = _buildAvatarImageProvider(user?.avatarUrl ?? '');

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Interactive Profile Avatar Header:
              // Collapsed state: Clean round circle avatar with ample vertical space (no overflow!)
              // Expanded state: Full sharp avatar photo expanding far up & down with bottom gradient fade into black!
              GestureDetector(
                onTap: () {
                  setState(() => _isHeaderExpanded = !_isHeaderExpanded);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.fastOutSlowIn,
                  width: double.infinity,
                  height: _isHeaderExpanded ? 440 : 250,
                  margin: EdgeInsets.only(bottom: 12, top: _isHeaderExpanded ? 0 : 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_isHeaderExpanded ? 0 : 0),
                    child: Stack(
                      children: [
                        // Expanded Sharp Cover Avatar Photo (NOT blurred!)
                        if (_isHeaderExpanded) ...[
                          Positioned.fill(
                            child: Image(
                              image: avatarProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Top Black Overlay Bar for Status/Notch area
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 60,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.black87, Colors.transparent],
                                ),
                              ),
                            ),
                          ),
                          // Bottom Soft Gradient Fade (fading photo edges into black background)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 160,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black54,
                                    Colors.black.withOpacity(0.95),
                                    Colors.black,
                                  ],
                                  stops: const [0.0, 0.4, 0.8, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ],

                        // Header Profile Information Overlay (No Overflow!)
                        Align(
                          alignment: _isHeaderExpanded ? Alignment.bottomCenter : Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Circular Avatar only visible in collapsed mode
                                if (!_isHeaderExpanded)
                                  CircleAvatar(
                                    radius: 48,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    backgroundImage: avatarProvider,
                                  ),

                                const SizedBox(height: 12),

                                // User Name
                                Text(
                                  user?.name ?? 'Unix',
                                  style: GoogleFonts.outfit(
                                    fontSize: _isHeaderExpanded ? 30 : 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                // Status Dot & Text
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.white54,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'был(а) 1 д. назад',
                                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 4),
                                Text(
                                  '${user?.phone ?? '+7 9999999999'} • @${user?.username ?? 'unixtest'}',
                                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // SECTION 1: "Информация" in Full Liquid Glass Style
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Информация',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Card 1: Liquid Glass Container
                    PortalTheme.liquidGlassWidget(
                      borderRadius: 22,
                      fillColor: Colors.white.withOpacity(0.06),
                      borderColor: Colors.white.withOpacity(0.12),
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          // Item 1: @ Username
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                              ).then((_) => setState(() {}));
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Text(
                                        '@',
                                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Имя пользователя',
                                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '@${user?.username ?? 'unixtest'}',
                                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 22),
                                ],
                              ),
                            ),
                          ),

                          const Divider(color: Colors.white10, height: 1),

                          // Item 2: Media, links & documents
                          InkWell(
                            onTap: () {},
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'Медиа, ссылки и документы',
                                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 22),
                                ],
                              ),
                            ),
                          ),

                          const Divider(color: Colors.white10, height: 1),

                          // Item 3: Change photo from gallery
                          InkWell(
                            onTap: _pickAndUploadPhoto,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'Изменить фотографию',
                                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 22),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // SECTION 2: "Разделы"
                    Text(
                      'Разделы',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),

                    PortalTheme.liquidGlassWidget(
                      borderRadius: 22,
                      fillColor: Colors.white.withOpacity(0.06),
                      borderColor: Colors.white.withOpacity(0.12),
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SectionsSettingsScreen()),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3390EC).withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.grid_view_rounded, color: Color(0xFF3390EC), size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'Разделы',
                                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 22),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // SECTION 3: "Общие группы" in Full Liquid Glass Style
                    Text(
                      'Общие группы',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Card 2: Liquid Glass Container
                    PortalTheme.liquidGlassWidget(
                      borderRadius: 22,
                      fillColor: Colors.white.withOpacity(0.06),
                      borderColor: Colors.white.withOpacity(0.12),
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          ...activeAccounts.map((acc) {
                            final isCurrent = acc.uid == user?.uid;
                            return InkWell(
                              onTap: () {
                                PortalBackendService.instance.switchAccount(acc);
                                setState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundImage: _buildAvatarImageProvider(acc.avatarUrl),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        acc.name,
                                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                                      ),
                                    ),
                                    if (isCurrent)
                                      Text('220', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54))
                                    else
                                      Text('44', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54)),
                                  ],
                                ),
                              ),
                            );
                          }),

                          if (activeAccounts.isNotEmpty) const Divider(color: Colors.white10, height: 1),

                          // "Добавить аккаунт" Button
                          InkWell(
                            onTap: _openAddAccountDialog,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                                  const SizedBox(width: 14),
                                  Text(
                                    'Добавить аккаунт',
                                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // SECTION 3: "Portals" Balance Section at the Very Bottom
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Portals',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 18,
                              height: 18,
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Image.asset(
                                'assets/icon/portal_coin.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Custom Currency Logo Badge
                              Container(
                                width: 38,
                                height: 38,
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Image.asset(
                                  'assets/icon/portal_coin.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ваш Баланс',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.white54,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${user?.portalsBalance ?? 100} Portals',
                                      style: GoogleFonts.outfit(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Sign Out Button in Liquid Glass style
                    GestureDetector(
                      onTap: widget.onSignOut,
                      child: PortalTheme.liquidGlassWidget(
                        borderRadius: 20,
                        fillColor: PortalTheme.roseAccent.withOpacity(0.1),
                        borderColor: PortalTheme.roseAccent.withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: Text(
                            'Выйти из профиля',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: PortalTheme.roseAccent),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
