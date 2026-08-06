import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/portal_theme.dart';
import '../models/portal_models.dart';
import '../services/firebase_service.dart';
import 'chats/chat_detail_screen.dart';
import 'chats/channel_detail_screen.dart';
import 'chats/chats_screen.dart';
import 'profile/user_profile_detail_screen.dart';
import '../widgets/verified_badge.dart';


/// Fullscreen Glassmorphic Search Screen for finding Channels & Users
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoading = false;
  int _selectedCategoryIndex = 0; // 0: Все, 1: Каналы, 2: Пользователи

  List<UserModel> _foundUsers = [];
  List<ChannelModel> _foundChannels = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() {
        _foundUsers = [];
        _foundChannels = [];
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final users = await PortalBackendService.instance.searchUsers(cleanQuery);
    final channels = await PortalBackendService.instance.searchChannels(cleanQuery);

    // Also fallback check single search endpoints if search lists were empty
    if (users.isEmpty) {
      final singleUser = await PortalBackendService.instance.searchUserByUsername(cleanQuery);
      if (singleUser != null) {
        users.add(singleUser);
      }
    }
    if (channels.isEmpty) {
      final singleChannel = await PortalBackendService.instance.searchChannelByHandle(cleanQuery);
      if (singleChannel != null) {
        channels.add(singleChannel);
      }
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _foundUsers = users;
      _foundChannels = channels;
      if (users.isEmpty && channels.isEmpty) {
        _errorMessage = 'Ничего не найдено по запросу "$cleanQuery"';
      }
    });
  }

  Future<void> _openChatWithUser(UserModel user) async {
    final chat = await PortalBackendService.instance.getOrCreateChat(user);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(chat: chat, peerUser: user),
      ),
    );
  }

  void _openChannel(ChannelModel channel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelDetailScreen(channel: channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalTheme.bgCanvas,
      body: SafeArea(
        child: Column(
          children: [
            // Top Search Bar Header
            _buildSearchHeader(),

            const SizedBox(height: 12),

            // Category Filter Pills
            _buildCategoryFilterRow(),

            const SizedBox(height: 12),

            // Results List / Loading / Empty State
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: PortalTheme.primary,
                        strokeWidth: 2.5,
                      ),
                    )
                  : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // Expanded Liquid Glass Search Bar Field
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Colors.white60,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Поиск каналов, пользователей...',
                            hintStyle: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: _performSearch,
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _performSearch('');
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Cancel / Close Button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.12),
                  width: 1,
                ),
              ),
              child: Text(
                'Отмена',
                style: GoogleFonts.inter(
                  color: PortalTheme.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterRow() {
    final categories = ['Все', 'Каналы', 'Пользователи'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(categories.length, (index) {
          final isSelected = _selectedCategoryIndex == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategoryIndex = index;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? PortalTheme.primary.withOpacity(0.25)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected
                        ? PortalTheme.primary.withOpacity(0.6)
                        : Colors.white.withOpacity(0.12),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  categories[index],
                  style: GoogleFonts.inter(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(
                Icons.search_rounded,
                color: Colors.white30,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Начните вводить текст',
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Вы можете искать публичные каналы и пользователей',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_off_rounded,
              color: Colors.white30,
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              _errorMessage!,
              style: GoogleFonts.inter(
                color: Colors.white60,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final showChannels = _selectedCategoryIndex == 0 || _selectedCategoryIndex == 1;
    final showUsers = _selectedCategoryIndex == 0 || _selectedCategoryIndex == 2;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Channels Section
        if (showChannels && _foundChannels.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Text(
              'КАНАЛЫ (${_foundChannels.length})',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ..._foundChannels.map((channel) => _buildChannelTile(channel)),
          const SizedBox(height: 16),
        ],

        // Users Section
        if (showUsers && _foundUsers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Text(
              'ПОЛЬЗОВАТЕЛИ (${_foundUsers.length})',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ..._foundUsers.map((user) => _buildUserTile(user)),
        ],
      ],
    );
  }

  Widget _buildChannelTile(ChannelModel channel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openChannel(channel),
          borderRadius: BorderRadius.circular(18),
          child: PortalTheme.liquidGlassWidget(
            borderRadius: 18,
            fillColor: Colors.white.withOpacity(0.06),
            borderColor: Colors.white.withOpacity(0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Avatar with Megaphone Badge
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white.withOpacity(0.12),
                      backgroundImage: buildAvatarImageProvider(channel.avatarUrl),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: PortalTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Channel Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.title,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '@${channel.handle} • ${channel.subscribersCount} подписчиков',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white30,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openUserProfile(UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileDetailScreen(user: user),
      ),
    );
  }

  Widget _buildUserTile(UserModel user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openUserProfile(user),
          borderRadius: BorderRadius.circular(18),
          child: PortalTheme.liquidGlassWidget(
            borderRadius: 18,
            fillColor: Colors.white.withOpacity(0.06),
            borderColor: Colors.white.withOpacity(0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // User Avatar with Online Dot
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white.withOpacity(0.12),
                      backgroundImage: buildAvatarImageProvider(user.avatarUrl),
                    ),
                    if (user.isOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),

                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.name,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user.isVerified) buildVerifiedBadge(size: 16),
                        ],
                      ),

                      const SizedBox(height: 3),
                      Text(
                        user.username.isNotEmpty ? '@${user.username}' : (user.phone.isNotEmpty ? user.phone : 'Пользователь'),
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                // Send Message Action Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PortalTheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: PortalTheme.primary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
