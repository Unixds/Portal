import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/portal_theme.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import '../chats/chat_detail_screen.dart';
import '../../widgets/verified_badge.dart';
import '../../services/music_service.dart';
import '../../widgets/music_player_modal.dart';


/// Fullscreen Modernized User Profile Screen matching Portal Messenger dark glass aesthetics.
class UserProfileDetailScreen extends StatefulWidget {
  final UserModel user;
  const UserProfileDetailScreen({super.key, required this.user});

  @override
  State<UserProfileDetailScreen> createState() => _UserProfileDetailScreenState();
}

class _UserProfileDetailScreenState extends State<UserProfileDetailScreen> {
  int _selectedTab = 0; // 0: Подарки, 1: Медиа
  List<String> _mediaPhotos = [];
  bool _isLoadingMedia = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    final photos = await PortalBackendService.instance.getChatMediaImages(widget.user.uid);
    if (mounted) {
      setState(() {
        _mediaPhotos = photos;
        _isLoadingMedia = false;
      });
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
    return NetworkImage(
      url.isNotEmpty
          ? url
          : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=800&q=80',
    );
  }

  Future<void> _openChatWithUser() async {
    final chat = await PortalBackendService.instance.getOrCreateChat(widget.user);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(chat: chat, peerUser: widget.user),
      ),
    );
  }

  void _openFullPhoto(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (context) => Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image(
                image: _buildAvatarImageProvider(imageUrl),
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showGiftDetailModal(UserGiftModel gift) {
    final formattedDate = DateFormat('MM/dd/yy в h:mm a').format(gift.timestamp);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Drag Handle & Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),

              const SizedBox(height: 16),

              // Gift Image
              Image.asset(
                gift.giftIcon,
                width: 130,
                height: 130,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.card_giftcard_rounded,
                  color: Colors.white70,
                  size: 90,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                gift.giftName,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 20),

              // Details Table Box
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Column(
                  children: [
                    // От кого
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Text('От', style: GoogleFonts.inter(color: Colors.white60, fontSize: 14)),
                          const Spacer(),
                          CircleAvatar(
                            radius: 14,
                            backgroundImage: _buildAvatarImageProvider(gift.senderAvatar),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            gift.senderName,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.white.withOpacity(0.08)),

                    // Дата
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Text('Дата', style: GoogleFonts.inter(color: Colors.white60, fontSize: 14)),
                          const Spacer(),
                          Text(
                            formattedDate,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.white.withOpacity(0.08)),

                    // Стоимость
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Text('Стоимость', style: GoogleFonts.inter(color: Colors.white60, fontSize: 14)),
                          const Spacer(),
                          Row(
                            children: [
                              Text(
                                '${gift.price} ',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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
                        ],
                      ),
                    ),

                    if (gift.note.isNotEmpty) ...[
                      Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            gift.note,
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // OK Button (Translucent Dark Glass)
              SizedBox(
                width: double.infinity,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C222B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: Center(
                      child: Text(
                        'ОК',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSendGiftModal() {
    final noteController = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final currentUser = PortalBackendService.instance.currentUser;
        final currentBalance = currentUser?.portalsBalance ?? 0;
        const giftPrice = 15;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Drag Handle & Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                      Text(
                        'Отправить подарок',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 36),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Gift Item Preview Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.16),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/gifts/mask.png',
                          width: 110,
                          height: 110,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.card_giftcard_rounded,
                            color: Colors.white70,
                            size: 80,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Маска',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$giftPrice ',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Container(
                              width: 16,
                              height: 16,
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
                            Text(
                              ' Portals',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Note Text Field
                  TextField(
                    controller: noteController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Добавить подпись к подарку...',
                      hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Balance Info Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Ваш баланс: ',
                        style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
                      ),
                      Text(
                        '$currentBalance Portals',
                        style: GoogleFonts.inter(
                          color: currentBalance >= giftPrice ? Colors.white : Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Action Button (Translucent Dark Glass)
                  SizedBox(
                    width: double.infinity,
                    child: InkWell(
                      onTap: isSending
                          ? null
                          : () async {
                              if (currentBalance < giftPrice) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Недостаточно Portals на балансе! Пополните баланс в Настройках.',
                                      style: GoogleFonts.inter(color: Colors.white),
                                    ),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                                return;
                              }

                              setModalState(() => isSending = true);

                              final success = await PortalBackendService.instance.sendGift(
                                receiverId: widget.user.uid,
                                giftId: 'mask',
                                giftName: 'Маска',
                                giftIcon: 'assets/gifts/mask.png',
                                price: giftPrice,
                                note: noteController.text,
                              );

                              if (mounted) {
                                Navigator.pop(context);
                                if (success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Подарок успешно отправлен пользователю ${widget.user.name}!',
                                        style: GoogleFonts.inter(color: Colors.white),
                                      ),
                                      backgroundColor: const Color(0xFF34C759),
                                    ),
                                  );
                                  setState(() {});
                                }
                              }
                            },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C222B),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.14)),
                        ),
                        child: Center(
                          child: isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'Отправить за $giftPrice Portals',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
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
    final avatarProvider = _buildAvatarImageProvider(widget.user.avatarUrl);

    return Scaffold(
      backgroundColor: PortalTheme.bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Builder(builder: (context) {
            final service = PortalBackendService.instance;
            final currentUid = service.currentUser?.uid ?? '';
            final chatId = service.getChatId(currentUid, widget.user.uid);
            final streak = service.getStreakLocally(chatId);
            final hasStreak = streak != null && streak.status != 'none';

            return PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              color: const Color(0xFF1E1E22),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.12), width: 1.0),
              ),
              offset: const Offset(0, 42),
              onSelected: (value) async {
                if (value == 'streak') {
                  if (hasStreak) {
                    await service.deleteStreak(chatId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Серия удалена', style: GoogleFonts.inter(color: Colors.white)),
                          backgroundColor: const Color(0xFF222227),
                        ),
                      );
                    }
                  } else {
                    await service.proposeStreak(widget.user);
                    if (mounted) {
                      _openChatWithUser();
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'streak',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasStreak ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
                        color: hasStreak ? Colors.redAccent : const Color(0xFFFF9500),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        hasStreak ? 'Удалить серию' : 'Предложить серию',
                        style: GoogleFonts.inter(
                          color: hasStreak ? Colors.redAccent : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // 1. Center Large Circular Avatar
            Center(
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      backgroundImage: avatarProvider,
                    ),
                  ),
                  if (widget.user.isOnline)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 2. User Name
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    widget.user.name,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (widget.user.isVerified) buildVerifiedBadge(size: 22),
              ],
            ),


            const SizedBox(height: 4),

            // 3. Active Status
            Text(
              widget.user.isOnline ? 'в сети' : 'был(а) недавно',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: widget.user.isOnline ? const Color(0xFF34C759) : Colors.white54,
                fontWeight: widget.user.isOnline ? FontWeight.w600 : FontWeight.w400,
              ),
            ),

            if (widget.user.profileSongTitle.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  MusicPlayerModalSheet.show(
                    context,
                    track: MusicTrackModel(
                      id: 'user_profile_track',
                      title: widget.user.profileSongTitle,
                      artist: widget.user.profileSongArtist.isNotEmpty ? widget.user.profileSongArtist : 'Музыка',
                      audioUrl: widget.user.profileSongUrl.isNotEmpty ? widget.user.profileSongUrl : PortalMusicService.demoTracks[0].audioUrl,
                      durationSeconds: widget.user.profileSongDuration > 0 ? widget.user.profileSongDuration : 194,
                    ),
                    targetUser: widget.user,
                    isOwnProfile: false,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_note_rounded, color: Color(0xFF3390EC), size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.user.profileSongTitle,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            // 4. @username and Bio
            if (widget.user.username.isNotEmpty)
              Text(
                '@${widget.user.username}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white54,
                ),
              ),

            if (widget.user.bio.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.user.bio,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 16),

            // 5. Single Center Primary Action Button "Чат" (Matching Reference Image 3)
            Center(
              child: SizedBox(
                width: 140,
                child: InkWell(
                  onTap: _openChatWithUser,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C222B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Чат',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 6. Section Tabs: "Подарки" and "Медиа"
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedTab == 0
                              ? Colors.white.withOpacity(0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            'Подарки',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: _selectedTab == 0 ? FontWeight.w600 : FontWeight.w400,
                              color: _selectedTab == 0 ? Colors.white : Colors.white60,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedTab == 1
                              ? Colors.white.withOpacity(0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            'Медиа',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: _selectedTab == 1 ? FontWeight.w600 : FontWeight.w400,
                              color: _selectedTab == 1 ? Colors.white : Colors.white60,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 7. Selected Tab Content
            if (_selectedTab == 0) _buildGiftsSection() else _buildMediaSection(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildGiftsSection() {
    return StreamBuilder<List<UserGiftModel>>(
      stream: PortalBackendService.instance.getUserGiftsStream(widget.user.uid),
      builder: (context, snapshot) {
        final gifts = snapshot.data ?? [];

        return Column(
          children: [
            if (gifts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.card_giftcard_rounded,
                        color: Colors.white30,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Подарков пока нет',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Будьте первым, кто отправит подарок!',
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.0,
                ),
                itemCount: gifts.length,
                itemBuilder: (context, index) {
                  final gift = gifts[index];
                  return GestureDetector(
                    onTap: () => _showGiftDetailModal(gift),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Center Gift Image
                          Center(
                            child: Image.asset(
                              gift.giftIcon,
                              width: 60,
                              height: 60,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.card_giftcard_rounded,
                                color: Colors.white70,
                                size: 40,
                              ),
                            ),
                          ),

                          // Top-Left Sender Avatar
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 10,
                                backgroundImage: _buildAvatarImageProvider(gift.senderAvatar),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 20),

            // Button: "Отправить подарок" (Dark Translucent Glass)
            SizedBox(
              width: double.infinity,
              child: InkWell(
                onTap: _showSendGiftModal,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C222B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.14),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Отправить подарок',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMediaSection() {
    if (_isLoadingMedia) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5),
        ),
      );
    }

    if (_mediaPhotos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: Colors.white30,
                size: 40,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Медиа нет',
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Отправленные фото появятся здесь',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: _mediaPhotos.length,
      itemBuilder: (context, index) {
        final url = _mediaPhotos[index];
        return GestureDetector(
          onTap: () => _openFullPhoto(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image(
              image: _buildAvatarImageProvider(url),
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}
