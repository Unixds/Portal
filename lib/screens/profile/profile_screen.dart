import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../theme/portal_theme.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import '../settings/edit_profile_screen.dart';
import '../../widgets/verified_badge.dart';
import '../../services/music_service.dart';
import '../../widgets/music_player_modal.dart';


/// Modern Telegram Liquid Glass User Profile Screen.
/// Features centered avatar, status, liquid glass info card with phone & username,
/// section pills, and interactive received gifts grid.
class ProfileScreen extends StatefulWidget {
  final VoidCallback onSignOut;
  const ProfileScreen({super.key, required this.onSignOut});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

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

  void _copyToClipboard(String text, String message) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF2C2C2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showQRCodeModal(String username) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'QR-код профиля',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '@$username',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF3390EC),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                size: 160,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3390EC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Закрыть',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGiftDetailModal(UserGiftModel gift) {
    final formattedDate = DateFormat('dd.MM.yyyy в HH:mm').format(gift.timestamp);

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
              _buildGiftGraphic(gift, size: 100),
              const SizedBox(height: 14),
              Text(
                gift.giftName,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Text('От', style: GoogleFonts.inter(color: Colors.white60, fontSize: 14)),
                          const Spacer(),
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: const Color(0xFF3390EC),
                            backgroundImage: gift.senderAvatar.isNotEmpty
                                ? _buildAvatarImageProvider(gift.senderAvatar)
                                : null,
                            child: gift.senderAvatar.isEmpty
                                ? Text(
                                    gift.senderName.isNotEmpty ? gift.senderName[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  )
                                : null,
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
                                  errorBuilder: (_, __, ___) => const Icon(Icons.stars, size: 14, color: Colors.amber),
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

  Widget _buildGiftGraphic(UserGiftModel gift, {double size = 56}) {
    switch (gift.giftId) {
      case 'box_gold':
      case 'red_gift_box':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.25),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF9500), Color(0xFFFF2D55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9500).withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text('🎁', style: TextStyle(fontSize: size * 0.55)),
          ),
        );
      case 'bear_builder':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.25),
            gradient: const LinearGradient(
              colors: [Color(0xFF8E54E9), Color(0xFF4776E6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8E54E9).withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text('🧸', style: TextStyle(fontSize: size * 0.55)),
          ),
        );
      case 'easter_bunny':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.25),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5E3A), Color(0xFFFF2A68)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5E3A).withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text('🐰', style: TextStyle(fontSize: size * 0.55)),
          ),
        );
      case 'clown_bear':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.25),
            gradient: const LinearGradient(
              colors: [Color(0xFF5AC8FA), Color(0xFF007AFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5AC8FA).withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text('🤡', style: TextStyle(fontSize: size * 0.55)),
          ),
        );
      case 'st_patrick_bear':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.25),
            gradient: const LinearGradient(
              colors: [Color(0xFF4CD964), Color(0xFF5AC8FA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4CD964).withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text('🍀', style: TextStyle(fontSize: size * 0.55)),
          ),
        );
      default:
        if (gift.giftIcon.isNotEmpty && gift.giftIcon.endsWith('.png')) {
          return Image.asset(
            gift.giftIcon,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text('🎁', style: TextStyle(fontSize: size * 0.55)),
          );
        }
        return Text('🎁', style: TextStyle(fontSize: size * 0.55));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = PortalBackendService.instance.currentUser;

    final phoneDisplay = (user?.phone.isNotEmpty == true) ? user!.phone : '+7 933 993 0882';
    final usernameDisplay = (user?.username.isNotEmpty == true) ? user!.username : 'unixds';

    return Scaffold(
      backgroundColor: PortalTheme.bgCanvas,
      appBar: AppBar(
        backgroundColor: PortalTheme.bgCanvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
            onPressed: () {
              // Account options or add account modal
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF1C1C1E),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (context) => Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_add_rounded, color: Color(0xFF3390EC)),
                        title: Text('Добавить аккаунт', style: GoogleFonts.inter(color: Colors.white)),
                        onTap: () => Navigator.pop(context),
                      ),
                      ListTile(
                        leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                        title: Text('Выйти из аккаунта', style: GoogleFonts.inter(color: Colors.redAccent)),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSignOut();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EditProfileScreen(),
                ),
              ).then((_) => setState(() {}));
            },
            child: Text(
              'Изм.',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: PortalBackendService.instance,
        builder: (context, _) {
          final liveUser = PortalBackendService.instance.currentUser;
          final liveAvatarProvider = _buildAvatarImageProvider(liveUser?.avatarUrl ?? '');

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 4),

                // 1. Centered Large Circular Avatar
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white10,
                          backgroundImage: liveAvatarProvider,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 2. Nickname
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        liveUser?.name.isNotEmpty == true ? liveUser!.name : 'Пользователь',
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (liveUser?.isVerified == true) buildVerifiedBadge(size: 22),
                  ],
                ),

                const SizedBox(height: 4),

                // 3. Status: "в сети"
                Text(
                  'в сети',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF3390EC),
                    fontWeight: FontWeight.w500,
                  ),
                ),

                if (liveUser?.profileSongTitle.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      MusicPlayerModalSheet.show(
                        context,
                        track: MusicTrackModel(
                          id: 'profile_track',
                          title: liveUser!.profileSongTitle,
                          artist: liveUser.profileSongArtist.isNotEmpty ? liveUser.profileSongArtist : 'Музыка',
                          audioUrl: liveUser.profileSongUrl.isNotEmpty ? liveUser.profileSongUrl : PortalMusicService.demoTracks[0].audioUrl,
                          durationSeconds: liveUser.profileSongDuration > 0 ? liveUser.profileSongDuration : 194,
                        ),
                        targetUser: liveUser,
                        isOwnProfile: true,
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
                              liveUser!.profileSongTitle,
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



            const SizedBox(height: 16),

            // 5. Liquid Glass Info Card (Mobile, Username, Birthday)
            PortalTheme.liquidGlassWidget(
              borderRadius: 24,
              fillColor: const Color(0xFF1C1C1E).withOpacity(0.7),
              borderColor: Colors.white.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item 1: Мобильный
                  InkWell(
                    onTap: () => _copyToClipboard(phoneDisplay, 'Номер телефона скопирован'),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'мобильный',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            phoneDisplay,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF3390EC),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Divider(height: 1, color: Colors.white.withOpacity(0.08)),

                  // Item 2: Имя пользователя
                  InkWell(
                    onTap: () => _copyToClipboard('@$usernameDisplay', 'Имя пользователя скопировано'),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'имя пользователя',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '@$usernameDisplay',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF3390EC),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.qr_code_2_rounded,
                              color: Color(0xFF3390EC),
                              size: 22,
                            ),
                            onPressed: () => _showQRCodeModal(usernameDisplay),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Divider(height: 1, color: Colors.white.withOpacity(0.08)),

                  // Item 3: День рождения
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'день рождения',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '14 фев',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 6. Gifts Section Title Header ("Подарки")
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.25),
                  ),
                ),
                child: Text(
                  'Подарки',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 7. Gifts Section Grid ("раздел с подарками")
            StreamBuilder<List<UserGiftModel>>(
              stream: PortalBackendService.instance.getUserGiftsStream(user?.uid ?? ''),
              builder: (context, snapshot) {
                final gifts = snapshot.data ?? [];

                if (gifts.isEmpty) {
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
                            Icons.card_giftcard_rounded,
                            color: Colors.white30,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Подарков нет',
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: gifts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.9,
                  ),
                  itemBuilder: (context, index) {
                    final gift = gifts[index];
                    return GestureDetector(
                      onTap: () => _showGiftDetailModal(gift),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                            width: 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Top Left Sender Avatar Badge
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF3390EC),
                                  border: Border.all(color: Colors.black, width: 1.5),
                                ),
                                child: Center(
                                  child: gift.senderAvatar.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image(
                                            image: _buildAvatarImageProvider(gift.senderAvatar),
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Text(
                                          gift.senderName.isNotEmpty ? gift.senderName[0].toLowerCase() : 'л',
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ),

                            // Centered Gift Visual
                            Center(
                              child: _buildGiftGraphic(gift, size: 54),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 100),
          ],
        ),
      );
    },
  ),
);
  }
}

