import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/portal_theme.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import 'chat_detail_screen.dart';

final Map<String, ImageProvider> _imageProviderCache = {};

ImageProvider buildAvatarImageProvider(String url) {
  if (url.isEmpty) {
    url = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80';
  }

  if (_imageProviderCache.containsKey(url)) {
    return _imageProviderCache[url]!;
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

  _imageProviderCache[url] = provider;
  return provider;
}

/// Chats Tab Screen matching Telegram iOS Liquid Glass style.
/// Dynamically updates when switching active accounts.
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
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingSearch = true;
      _searchError = null;
    });

    final result = await PortalBackendService.instance.searchUserByUsername(query);

    setState(() {
      _isLoadingSearch = false;
      _foundUser = result;
      if (result == null) {
        _searchError = 'Пользователь с @${query.replaceAll('@', '')} не найден';
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
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(chat: chat, peerUser: user),
      ),
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

            // Large Title: "Чаты"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                'Чаты',
                style: PortalTheme.displayHeader(fontSize: 34, color: Colors.white),
              ),
            ),

            const SizedBox(height: 8),

            // Search Bar Input Field in Telegram iOS Style
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PortalTheme.liquidGlassWidget(
                borderRadius: 16,
                blurSigma: 18,
                fillColor: Colors.white.withOpacity(0.08),
                borderColor: Colors.white.withOpacity(0.14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Colors.white54, size: 22),
                    const SizedBox(width: 10),
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
                      )
                    else
                      const Icon(Icons.mic_none_rounded, color: Colors.white54, size: 22),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Main Content View: Search Results Overlay OR Active Account's Chats Stream
            Expanded(
              child: AnimatedBuilder(
                animation: PortalBackendService.instance,
                builder: (context, _) {
                  final activeUid = PortalBackendService.instance.currentUser?.uid ?? 'guest';
                  return _isSearching
                      ? _buildSearchResultsView()
                      : _buildChatsListView(key: ValueKey(activeUid));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Search Results View Tile
  Widget _buildSearchResultsView() {
    if (_isLoadingSearch) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_foundUser == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchError ?? 'Введите @username пользователя для поиска',
            style: PortalTheme.subText(fontSize: 15, color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
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
      ],
    );
  }

  // Active Chats List View for Current Logged-In Account
  Widget _buildChatsListView({required Key key}) {
    return StreamBuilder<List<ChatModel>>(
      key: key,
      stream: PortalBackendService.instance.getChatsStream(),
      builder: (context, snapshot) {
        final chats = snapshot.data ?? [];

        if (chats.isEmpty) {
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
                    Text('У вас пока нет чатов', style: PortalTheme.titleHeader(fontSize: 18)),
                    const SizedBox(height: 8),
                    Text(
                      'Введите @username юзера в строке поиска выше, чтобы начать диалог.',
                      textAlign: TextAlign.center,
                      style: PortalTheme.subText(fontSize: 14, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          itemCount: chats.length,
          separatorBuilder: (context, index) => const Padding(
            padding: EdgeInsets.only(left: 68),
            child: Divider(color: Colors.white10, height: 1),
          ),
          itemBuilder: (context, index) {
            final chat = chats[index];
            final peer = chat.peerUser;
            final timeStr = DateFormat('HH:mm').format(chat.lastMessageTime);

            final peerName = peer?.name.isNotEmpty == true ? peer!.name : 'Пользователь';

            return InkWell(
              onTap: () {
                if (peer != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatDetailScreen(chat: chat, peerUser: peer),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF7C66DC),
                      backgroundImage: buildAvatarImageProvider(peer?.avatarUrl ?? ''),
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
                                  peerName,
                                  style: PortalTheme.titleHeader(fontSize: 16, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                timeStr,
                                style: PortalTheme.subText(fontSize: 12, color: Colors.white38),
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
  }
}
