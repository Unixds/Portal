import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/portal_theme.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import 'chats_screen.dart'; // For buildAvatarImageProvider

/// Full-screen Message & Post Forwarding Screen for Portal Messenger
class ForwardMessageScreen extends StatefulWidget {
  final String text;
  final String type;
  final String imageUrl;
  final int audioDuration;
  final String originalAuthorName;
  final String originalAuthorAvatar;

  const ForwardMessageScreen({
    super.key,
    required this.text,
    required this.type,
    this.imageUrl = '',
    this.audioDuration = 0,
    required this.originalAuthorName,
    required this.originalAuthorAvatar,
  });

  @override
  State<ForwardMessageScreen> createState() => _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends State<ForwardMessageScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewText = widget.type == 'image'
        ? '📷 Фотография'
        : (widget.type == 'voice' ? '🎤 Голосовое сообщение' : widget.text);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Translucent Liquid Glass Top Bar
            ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161618).withOpacity(0.85),
                    border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.12))),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Переслать сообщение',
                            style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            'Выберите получателя',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: PortalTheme.liquidGlassWidget(
                borderRadius: 16,
                fillColor: Colors.white.withOpacity(0.06),
                borderColor: Colors.white.withOpacity(0.12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    icon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                    hintText: 'Поиск чатов...',
                    hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 15),
                  ),
                ),
              ),
            ),

            // Preview of the message being forwarded
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF3390EC).withOpacity(0.4), width: 1),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: buildAvatarImageProvider(widget.originalAuthorAvatar),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Переслать от ${widget.originalAuthorName}',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF3390EC)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Full-screen Chat List
            Expanded(
              child: StreamBuilder<List<ChatModel>>(
                stream: PortalBackendService.instance.getChatsStream(),
                builder: (context, snapshot) {
                  var chats = snapshot.data ?? [];

                  if (_searchQuery.isNotEmpty) {
                    chats = chats.where((c) {
                      final name = c.peerUser?.name.toLowerCase() ?? '';
                      final username = c.peerUser?.username.toLowerCase() ?? '';
                      return name.contains(_searchQuery) || username.contains(_searchQuery);
                    }).toList();
                  }

                  if (chats.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _searchQuery.isNotEmpty ? 'Ничего не найдено' : 'Нет активных чатов',
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 15),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: chats.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final chatItem = chats[index];
                      final peer = chatItem.peerUser;
                      final peerName = peer?.name ?? 'Пользователь';
                      final peerAvatar = peer?.avatarUrl ?? '';
                      final peerUsername = peer != null ? '@${peer.username}' : '';

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundImage: buildAvatarImageProvider(peerAvatar),
                        ),
                        title: Text(
                          peerName,
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        subtitle: Text(
                          peerUsername,
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF3390EC)),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3390EC),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Отправить',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.send_rounded, color: Colors.white, size: 14),
                            ],
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close ForwardMessageScreen
                          PortalBackendService.instance.forwardMessage(
                            targetChatId: chatItem.chatId,
                            text: widget.text,
                            type: widget.type,
                            imageUrl: widget.imageUrl,
                            audioDuration: widget.audioDuration,
                            originalAuthorName: widget.originalAuthorName,
                            originalAuthorAvatar: widget.originalAuthorAvatar,
                            peerUid: peer?.uid,
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Сообщение переслано $peerName', style: GoogleFonts.inter(color: Colors.white)),
                              backgroundColor: const Color(0xFF1C1C1E),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
