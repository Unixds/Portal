import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/portal_theme.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import 'chat_detail_screen.dart';
import 'channel_detail_screen.dart';
import 'create_channel_screen.dart';
import '../../widgets/verified_badge.dart';
import '../../theme/telegram_page_route.dart';


final Map<String, ImageProvider> _imageProviderCache = {};

ImageProvider buildAvatarImageProvider(String url) {
  if (url.isEmpty) {
    url = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80';
  }

  final cacheKey = url.length > 200 ? '${url.length}_${url.hashCode}' : url;

  if (_imageProviderCache.containsKey(cacheKey)) {
    return _imageProviderCache[cacheKey]!;
  }

  ImageProvider provider;
  if (url.startsWith('data:image')) {
    try {
      final base64Data = url.split(',').last;
      final bytes = base64Decode(base64Data);
      provider = MemoryImage(bytes);
    } catch (_) {
      provider = const NetworkImage('https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80');
    }
  } else {
    provider = NetworkImage(url);
  }

  _imageProviderCache[cacheKey] = provider;
  return provider;
}

/// Chats Tab Screen matching Telegram iOS Liquid Glass style.
/// Dynamically updates when switching active accounts and managing channels.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isLoadingSearch = false;
  UserModel? _foundUser;
  ChannelModel? _foundChannel;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _foundUser = null;
        _foundChannel = null;
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingSearch = true;
      _searchError = null;
    });

    final userResult = await PortalBackendService.instance.searchUserByUsername(query);
    final channelResult = await PortalBackendService.instance.searchChannelByHandle(query);

    setState(() {
      _isLoadingSearch = false;
      _foundUser = userResult;
      _foundChannel = channelResult;

      if (userResult == null && channelResult == null) {
        _searchError = 'Ничего не найдено по запросу "@${query.replaceAll('@', '')}"';
      }
    });
  }

  Future<void> _openChatWithUser(UserModel user) async {
    final chat = await PortalBackendService.instance.getOrCreateChat(user);
    if (!mounted) return;

    _searchController.clear();
    setState(() {
      _isSearching = false;
      _foundUser = null;
      _foundChannel = null;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(chat: chat, peerUser: user),
      ),
    );
  }

  void _openChannel(ChannelModel channel) {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _foundUser = null;
      _foundChannel = null;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelDetailScreen(channel: channel),
      ),
    );
  }

  void _showCreateChannelModal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateChannelScreen(),
      ),
    );
  }

  void _showChatItemContextMenu(BuildContext context, dynamic item) {
    HapticFeedback.mediumImpact();
    final service = PortalBackendService.instance;
    final currentUid = service.currentUser?.uid ?? '';
    final isChat = item is ChatModel;
    final itemId = isChat ? item.chatId : (item as ChannelModel).channelId;

    final isPinned = isChat
        ? (item.isPinnedBy(currentUid) || service.isPinnedLocally(itemId))
        : ((item as ChannelModel).isPinnedBy(currentUid) || service.isPinnedLocally(itemId));

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ChatContextMenu',
      barrierColor: Colors.black.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 140),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final scale = 0.92 + 0.08 * Curves.easeOutCubic.transform(anim1.value);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: anim1.value,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim1, anim2) {
        return Material(
          color: Colors.transparent,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Highlighting Selected Chat Tile
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withOpacity(0.20), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: const Color(0xFF2C2C2E),
                            backgroundImage: buildAvatarImageProvider(
                              isChat ? (item.peerUser?.avatarUrl ?? '') : (item as ChannelModel).avatarUrl,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isChat ? (item.peerUser?.name ?? 'Чат') : (item as ChannelModel).title,
                                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isChat ? item.lastMessage : (item as ChannelModel).lastPost,
                                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isPinned)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.push_pin_rounded, color: Color(0xFF3390EC), size: 18),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Floating Liquid Glass Popup Menu
                    Container(
                      width: 220,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () async {
                              Navigator.pop(ctx);
                              if (isChat) {
                                await service.togglePinChat(itemId);
                              } else {
                                await service.togglePinChannel(itemId);
                              }
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isPinned ? 'Открепить' : 'Закрепить',
                                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                                  ),
                                  Icon(
                                    isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          InkWell(
                            onTap: () async {
                              Navigator.pop(ctx);
                              if (isChat) {
                                await service.deleteChat(itemId);
                              } else {
                                await service.leaveChannel(itemId);
                              }
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isChat ? 'Удалить чат' : 'Покинуть',
                                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.redAccent),
                                  ),
                                  const Icon(
                                    Icons.delete_forever_rounded,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),

            // Title Row: Centered "Чаты" Title + Liquid Glass [ + ] Channel Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(
                      'Чаты',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _showCreateChannelModal,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),


            const SizedBox(height: 8),

            // Search Bar Input Field in Telegram iOS Capsule Style
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PortalTheme.liquidGlassWidget(
                borderRadius: 28,
                blurSigma: 18,
                fillColor: Colors.white.withOpacity(0.10),
                borderColor: Colors.white.withOpacity(0.16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _performSearch,
                        style: PortalTheme.bodyText(fontSize: 16, color: Colors.white),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Поиск',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                        child: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                      ),
                  ],
                ),
              ),
            ),


            const SizedBox(height: 14),

            // Main Content View: Search Results Overlay OR Active Account's Chats & Channels Stream
            Expanded(
              child: AnimatedBuilder(
                animation: PortalBackendService.instance,
                builder: (context, _) {
                  final activeUid = PortalBackendService.instance.currentUser?.uid ?? 'guest';
                  return _isSearching
                      ? _buildSearchResultsView()
                      : _buildCombinedChatsAndChannelsView(key: ValueKey(activeUid));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Search Results View (Displays both users and public channels matching query)
  Widget _buildSearchResultsView() {
    if (_isLoadingSearch) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_foundUser == null && _foundChannel == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchError ?? 'Введите @username пользователя или ссылку канала для поиска',
            style: PortalTheme.subText(fontSize: 15, color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        if (_foundUser != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Найден пользователь:', style: PortalTheme.subText(fontSize: 13, color: Colors.white54)),
          ),
          GestureDetector(
            onTap: () => _openChatWithUser(_foundUser!),
            child: PortalTheme.liquidGlassWidget(
              borderRadius: 20,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: buildAvatarImageProvider(_foundUser!.avatarUrl),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_foundUser!.name, style: PortalTheme.titleHeader(fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('@${_foundUser!.username}', style: PortalTheme.subText(fontSize: 14, color: Colors.white60)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 22),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_foundChannel != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Найден публичный канал:', style: PortalTheme.subText(fontSize: 13, color: Colors.white54)),
          ),
          GestureDetector(
            onTap: () => _openChannel(_foundChannel!),
            child: PortalTheme.liquidGlassWidget(
              borderRadius: 20,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: buildAvatarImageProvider(_foundChannel!.avatarUrl),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('📢 ', style: TextStyle(fontSize: 14)),
                            Text(_foundChannel!.title, style: PortalTheme.titleHeader(fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('@${_foundChannel!.handle} • ${_foundChannel!.subscribersCount} подписчиков',
                            style: PortalTheme.subText(fontSize: 13, color: const Color(0xFF3390EC))),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 18),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Combined Active Chats & Subscribed Channels Stream View
  Widget _buildCombinedChatsAndChannelsView({required Key key}) {
    return StreamBuilder<List<ChatModel>>(
      key: key,
      stream: PortalBackendService.instance.getChatsStream(),
      builder: (context, chatSnapshot) {
        return StreamBuilder<List<ChannelModel>>(
          stream: PortalBackendService.instance.getSubscribedChannelsStream(),
          builder: (context, channelSnapshot) {
            final chats = chatSnapshot.data ?? [];
            final channels = channelSnapshot.data ?? [];

            if (chats.isEmpty && channels.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: PortalTheme.liquidGlassWidget(
                    borderRadius: 24,
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.forum_outlined, size: 48, color: Colors.white70),
                        const SizedBox(height: 16),
                        Text('У вас пока нет чатов и каналов', style: PortalTheme.titleHeader(fontSize: 18)),
                        const SizedBox(height: 8),
                        Text(
                          'Нажмите [+] сверху, чтобы создать канал, или найдите пользователя по @username.',
                          textAlign: TextAlign.center,
                          style: PortalTheme.subText(fontSize: 14, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final service = PortalBackendService.instance;
            final currentUid = service.currentUser?.uid ?? '';

            // Create unified items list sorted chronologically with Pinned items at top
            final List<dynamic> combinedItems = [];
            combinedItems.addAll(chats);
            combinedItems.addAll(channels);

            combinedItems.sort((a, b) {
              final idA = a is ChatModel ? a.chatId : (a as ChannelModel).channelId;
              final idB = b is ChatModel ? b.chatId : (b as ChannelModel).channelId;

              final isPinnedA = a is ChatModel
                  ? (a.isPinnedBy(currentUid) || service.isPinnedLocally(idA))
                  : ((a as ChannelModel).isPinnedBy(currentUid) || service.isPinnedLocally(idA));

              final isPinnedB = b is ChatModel
                  ? (b.isPinnedBy(currentUid) || service.isPinnedLocally(idB))
                  : ((b as ChannelModel).isPinnedBy(currentUid) || service.isPinnedLocally(idB));

              if (isPinnedA != isPinnedB) {
                return isPinnedA ? -1 : 1;
              }

              final dateA = a is ChatModel ? a.lastMessageTime : (a as ChannelModel).lastPostTime;
              final dateB = b is ChatModel ? b.lastMessageTime : (b as ChannelModel).lastPostTime;
              return dateB.compareTo(dateA);
            });

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: combinedItems.length,
              separatorBuilder: (context, index) => const Padding(
                padding: EdgeInsets.only(left: 68),
                child: Divider(color: Colors.white10, height: 1),
              ),
              itemBuilder: (context, index) {
                final item = combinedItems[index];

                if (item is ChannelModel) {
                  final timeStr = DateFormat('HH:mm').format(item.lastPostTime);
                  final isPinned = item.isPinnedBy(currentUid) || service.isPinnedLocally(item.channelId);

                  return InkWell(
                    onTap: () => _openChannel(item),
                    onLongPress: () => _showChatItemContextMenu(context, item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: const Color(0xFF1C1C1E),
                                backgroundImage: buildAvatarImageProvider(item.avatarUrl),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: isPinned ? const Color(0xFF3390EC) : const Color(0xFF3390EC),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPinned ? Icons.push_pin_rounded : Icons.campaign_rounded,
                                    color: Colors.white,
                                    size: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: PortalTheme.titleHeader(fontSize: 16, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Row(
                                      children: [
                                        if (isPinned) ...[
                                          const Icon(Icons.push_pin_rounded, color: Color(0xFF3390EC), size: 14),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          timeStr,
                                          style: PortalTheme.subText(fontSize: 12, color: Colors.white38),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.lastPost,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PortalTheme.subText(fontSize: 14, color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // ChatModel item
                final chat = item as ChatModel;
                final peer = chat.peerUser;
                final timeStr = DateFormat('HH:mm').format(chat.lastMessageTime);
                final peerName = peer?.name.isNotEmpty == true ? peer!.name : 'Пользователь';
                final isPinned = chat.isPinnedBy(currentUid) || service.isPinnedLocally(chat.chatId);

                return InkWell(
                  onTap: () {
                    if (peer != null) {
                      Navigator.push(
                        context,
                        TelegramPageRoute(
                          page: ChatDetailScreen(chat: chat, peerUser: peer),
                        ),
                      );
                    }
                  },
                  onLongPress: () => _showChatItemContextMenu(context, chat),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: const Color(0xFF7C66DC),
                              backgroundImage: buildAvatarImageProvider(peer?.avatarUrl ?? ''),
                            ),
                            if (isPinned)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF3390EC),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.push_pin_rounded,
                                    color: Colors.white,
                                    size: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            peerName,
                                            style: PortalTheme.titleHeader(fontSize: 16, color: Colors.white),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (peer?.isVerified == true) buildVerifiedBadge(size: 16),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    children: [
                                      if (isPinned) ...[
                                        const Icon(Icons.push_pin_rounded, color: Color(0xFF3390EC), size: 14),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        timeStr,
                                        style: PortalTheme.subText(fontSize: 12, color: Colors.white38),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                chat.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PortalTheme.subText(fontSize: 14, color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );

              },
            );
          },
        );
      },
    );
  }
}

