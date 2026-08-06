import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/portal_theme.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import 'chats_screen.dart';
import 'chat_detail_screen.dart'; // Reuses AppleEmojiWidget & buildRichTextWithAppleEmojis
import 'forward_message_screen.dart';

/// Public Channel Detail Screen for Telegram-style Channels ("Каналы")
class ChannelDetailScreen extends StatefulWidget {
  final ChannelModel channel;

  const ChannelDetailScreen({
    super.key,
    required this.channel,
  });

  @override
  State<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends State<ChannelDetailScreen> {
  final TextEditingController _postController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showEmojiPicker = false;

  // Toggle Mode: Voice (false) vs Video Note Camera (true) for Owner Posting
  bool _isCameraMode = false;

  // Recording State (Voice OR Circular Video Note)
  bool _isRecording = false;
  bool _isRecordingVideoNote = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  double _dragOffsetX = 0.0;

  late ChannelModel _currentChannel;

  final List<String> _appleEmojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🥹', '😊',
    '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙',
    '😚', '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎',
    '🥸', '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁',
    '☹️', '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😮‍💨', '😤',
    '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱', '📁', '🔥',
    '❤️', '💖', '✨', '⭐', '🎉', '👍', '🙌', '👏', '🙏', '💎',
    '🚀', '👑', '⚡', '💯', '🥳', '🤩', '🎁', '🎨', '🎵', '🏆',
    '💡', '📌', '🍀', '🌟', '🎂', '🍷', '🚀', '🖤', '🤍', '🧡',
  ];

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.channel;
  }

  @override
  void dispose() {
    _postController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  bool get _isOwner =>
      PortalBackendService.instance.currentUser?.uid == _currentChannel.ownerId;

  bool get _isSubscribed {
    final myUid = PortalBackendService.instance.currentUser?.uid ?? '';
    return _currentChannel.subscribers.contains(myUid);
  }

  void _sendPost() {
    final text = _postController.text.trim();
    if (text.isEmpty) return;

    PortalBackendService.instance.postToChannel(
      channelId: _currentChannel.channelId,
      text: text,
    );

    _postController.clear();
    setState(() {});
    _scrollToBottom();
  }

  void _startRecording({required bool isVideo}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _isRecording = true;
      _isRecordingVideoNote = isVideo;
      _recordSeconds = 0;
      _dragOffsetX = 0.0;
      _showEmojiPicker = false;
    });

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _isRecording) {
        setState(() {
          _recordSeconds++;
        });
      }
    });
  }

  void _cancelRecording() {
    _recordTimer?.cancel();
    setState(() {
      _isRecording = false;
      _isRecordingVideoNote = false;
      _recordSeconds = 0;
      _dragOffsetX = 0.0;
    });
  }

  void _finishAndSendRecording() {
    if (!_isRecording) return;

    if (_dragOffsetX < -80) {
      _cancelRecording();
      return;
    }

    final duration = max(_recordSeconds, 1);
    final isVideo = _isRecordingVideoNote;
    _cancelRecording();

    if (isVideo) {
      PortalBackendService.instance.postToChannel(
        channelId: _currentChannel.channelId,
        text: 'Видеосообщение',
        type: 'video_note',
        audioDuration: duration,
      );
    } else {
      PortalBackendService.instance.postToChannel(
        channelId: _currentChannel.channelId,
        text: 'Голосовое сообщение',
        type: 'voice',
        audioDuration: duration,
      );
    }

    _scrollToBottom();
  }

  Future<void> _pickAndSendPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

        if (!mounted) return;
        _openPhotoCaptionModal(base64Image);
      }
    } catch (e) {
      debugPrint('Error picking photo: $e');
    }
  }

  void _openPhotoCaptionModal(String base64Image) {
    final captionController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF161618).withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
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
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 240),
                        width: double.infinity,
                        color: Colors.black,
                        child: Image(
                          image: buildAvatarImageProvider(base64Image),
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2E),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Center(
                              child: TextField(
                                controller: captionController,
                                style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: 'Добавить подпись...',
                                  hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            final caption = captionController.text.trim();
                            Navigator.pop(ctx);
                            PortalBackendService.instance.postToChannel(
                              channelId: _currentChannel.channelId,
                              text: caption,
                              type: 'image',
                              imageUrl: base64Image,
                            );
                            _scrollToBottom();
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: Color(0xFF3390EC),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                          ),
                        ),
                      ],
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

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatSubscriberCount(int count) {
    if (count == 1) return '1 подписчик';
    if (count >= 2 && count <= 4) return '$count подписчика';
    return '$count подписчиков';
  }

  Future<void> _toggleSubscription() async {
    if (_isSubscribed) {
      await PortalBackendService.instance.leaveChannel(_currentChannel.channelId);
      final myUid = PortalBackendService.instance.currentUser?.uid ?? '';
      final updatedSubs = List<String>.from(_currentChannel.subscribers)..remove(myUid);
      setState(() {
        _currentChannel = ChannelModel(
          channelId: _currentChannel.channelId,
          ownerId: _currentChannel.ownerId,
          title: _currentChannel.title,
          description: _currentChannel.description,
          handle: _currentChannel.handle,
          avatarUrl: _currentChannel.avatarUrl,
          subscribers: updatedSubs,
          subscribersCount: max(_currentChannel.subscribersCount - 1, 0),
          lastPost: _currentChannel.lastPost,
          lastPostTime: _currentChannel.lastPostTime,
          createdAt: _currentChannel.createdAt,
        );
      });
    } else {
      await PortalBackendService.instance.joinChannel(_currentChannel.channelId);
      final myUid = PortalBackendService.instance.currentUser?.uid ?? '';
      final updatedSubs = List<String>.from(_currentChannel.subscribers)..add(myUid);
      setState(() {
        _currentChannel = ChannelModel(
          channelId: _currentChannel.channelId,
          ownerId: _currentChannel.ownerId,
          title: _currentChannel.title,
          description: _currentChannel.description,
          handle: _currentChannel.handle,
          avatarUrl: _currentChannel.avatarUrl,
          subscribers: updatedSubs,
          subscribersCount: _currentChannel.subscribersCount + 1,
          lastPost: _currentChannel.lastPost,
          lastPostTime: _currentChannel.lastPostTime,
          createdAt: _currentChannel.createdAt,
        );
      });
    }
  }

  void _openChannelInfoDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (ctx) {
        return Center(
          child: SingleChildScrollView(
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161618).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withOpacity(0.14), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 54,
                          backgroundColor: const Color(0xFF1C1C1E),
                          backgroundImage: buildAvatarImageProvider(_currentChannel.avatarUrl),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _currentChannel.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatSubscriberCount(_currentChannel.subscribersCount),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF3390EC),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        PortalTheme.liquidGlassWidget(
                          borderRadius: 20,
                          fillColor: Colors.white.withOpacity(0.06),
                          borderColor: Colors.white.withOpacity(0.12),
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.link_rounded, color: Colors.white, size: 18),
                                ),
                                title: Text('Ссылка канала', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
                                subtitle: Text('@${_currentChannel.handle}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF3390EC))),
                              ),
                              if (_currentChannel.description.isNotEmpty) ...[
                                const Divider(color: Colors.white10, height: 1),
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                                  ),
                                  title: Text('Описание', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
                                  subtitle: Text(_currentChannel.description, style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (!_isOwner)
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _toggleSubscription();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSubscribed ? Colors.redAccent.withOpacity(0.2) : const Color(0xFF3390EC),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  side: BorderSide(
                                    color: _isSubscribed ? Colors.redAccent.withOpacity(0.4) : Colors.transparent,
                                  ),
                                ),
                              ),
                              child: Text(
                                _isSubscribed ? 'Покинуть канал' : 'Присоединиться',
                                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
        child: Stack(
          children: [
            // Channel Posts Feed Stream
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(
                    child: StreamBuilder<List<ChannelPostModel>>(
                      stream: PortalBackendService.instance.getChannelPostsStream(_currentChannel.channelId),
                      builder: (context, snapshot) {
                        final posts = snapshot.data ?? [];

                        if (posts.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'Пока нет публикаций в канале.',
                                style: PortalTheme.subText(color: Colors.white38),
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 80, 16, 90),
                          itemCount: posts.length,
                          itemBuilder: (context, index) {
                            final post = posts[index];
                            return _buildPostCard(post);
                          },
                        );
                      },
                    ),
                  ),
                  if (_showEmojiPicker && _isOwner) _buildEmojiPickerPanel(),
                  const SizedBox(height: 64),
                ],
              ),
            ),

            // Floating Translucent Top Header Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),

            // Bottom Action / Broadcast Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  // Floating Header Bar with Liquid Glass Blur
  Widget _buildTopBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.85),
                Colors.black.withOpacity(0.60),
                Colors.black.withOpacity(0.25),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Center(
                child: GestureDetector(
                  onTap: _openChannelInfoDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white.withOpacity(0.16), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundImage: buildAvatarImageProvider(_currentChannel.avatarUrl),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('📢 ', style: TextStyle(fontSize: 12)),
                                Text(
                                  _currentChannel.title,
                                  style: PortalTheme.titleHeader(fontSize: 15, color: Colors.white),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _formatSubscriberCount(_currentChannel.subscribersCount),
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 22),
                  onPressed: _openChannelInfoDialog,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTelegramPostContextMenu(BuildContext context, ChannelPostModel post) {
    HapticFeedback.mediumImpact();
    final quickEmojis = ['👍', '❤️', '🔥', '😂', '😮', '😢', '👏', '🎉', '🚀', '💯', '💎', '🖤'];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PostContextMenu',
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
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Emoji Reactions Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withOpacity(0.16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: quickEmojis.map((emoji) {
                            final myUid = PortalBackendService.instance.currentUser?.uid ?? '';
                            final isSelected = post.reactions[myUid] == emoji;

                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(ctx);
                                PortalBackendService.instance.toggleChannelPostReaction(
                                  channelId: post.channelId,
                                  postId: post.id,
                                  emoji: emoji,
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF3390EC).withOpacity(0.35) : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: isSelected ? Border.all(color: const Color(0xFF3390EC), width: 1.5) : null,
                                ),
                                child: AppleEmojiWidget(emoji: emoji, size: 28),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Scaled Preview of Selected Channel Post Card
                    Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.14)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (post.type == 'image' && post.imageUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image(
                                image: buildAvatarImageProvider(post.imageUrl),
                                gaplessPlayback: true,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 180,
                              ),
                            ),
                          if (post.text.isNotEmpty)
                            buildRichTextWithAppleEmojis(post.text, fontSize: 15),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Liquid Glass Actions Options Menu
                    Container(
                      width: 260,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.14)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (post.text.isNotEmpty) ...[
                            InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                Clipboard.setData(ClipboardData(text: post.text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Текст скопирован', style: GoogleFonts.inter(color: Colors.white)),
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    const Icon(Icons.copy_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 14),
                                    Text('Скопировать', style: GoogleFonts.inter(fontSize: 15, color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(color: Colors.white10, height: 1),
                          ],
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _showForwardModalSheet(context, post);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  const Icon(Icons.shortcut_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 14),
                                  Text('Переслать', style: GoogleFonts.inter(fontSize: 15, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                          if (_isOwner) ...[
                            const Divider(color: Colors.white10, height: 1),
                            InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                PortalBackendService.instance.deleteChannelPost(
                                  channelId: post.channelId,
                                  postId: post.id,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                    const SizedBox(width: 14),
                                    Text(
                                      'Удалить пост',
                                      style: GoogleFonts.inter(fontSize: 15, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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

  void _showForwardModalSheet(BuildContext context, ChannelPostModel post) {
    final originalAuthorName = _currentChannel.title;
    final originalAuthorAvatar = _currentChannel.avatarUrl;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessageScreen(
          text: post.text,
          type: post.type,
          imageUrl: post.imageUrl,
          audioDuration: post.audioDuration,
          originalAuthorName: originalAuthorName,
          originalAuthorAvatar: originalAuthorAvatar,
        ),
      ),
    );
  }

  Widget _buildPostReactionsBadge(ChannelPostModel post) {
    if (post.reactions.isEmpty) return const SizedBox.shrink();

    final Map<String, int> counts = {};
    post.reactions.forEach((uid, emoji) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    });

    final myUid = PortalBackendService.instance.currentUser?.uid ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: counts.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value;
          final isMyReaction = post.reactions[myUid] == emoji;

          return GestureDetector(
            onTap: () {
              PortalBackendService.instance.toggleChannelPostReaction(
                channelId: post.channelId,
                postId: post.id,
                emoji: emoji,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isMyReaction ? const Color(0xFF3390EC).withOpacity(0.35) : Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMyReaction ? const Color(0xFF3390EC) : Colors.white.withOpacity(0.20),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppleEmojiWidget(emoji: emoji, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Channel Broadcast Post Card
  Widget _buildPostCard(ChannelPostModel post) {
    final myUid = PortalBackendService.instance.currentUser?.uid ?? '';
    if (myUid.isNotEmpty && !post.viewers.contains(myUid)) {
      Future.microtask(() {
        PortalBackendService.instance.registerPostView(
          channelId: post.channelId,
          postId: post.id,
        );
      });
    }

    final timeStr = DateFormat('HH:mm').format(post.timestamp);

    return GestureDetector(
      onLongPress: () => _showTelegramPostContextMenu(context, post),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Post Author Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: buildAvatarImageProvider(_currentChannel.avatarUrl),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentChannel.title,
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        Text(
                          '@${_currentChannel.handle}',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF3390EC)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Post Content
            if (post.type == 'image' && post.imageUrl.isNotEmpty)
              ClipRRect(
                child: Image(
                  image: buildAvatarImageProvider(post.imageUrl),
                  gaplessPlayback: true,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 240,
                ),
              ),

            if (post.type == 'voice')
              Padding(
                padding: const EdgeInsets.all(12),
                child: VoiceMessageBubble(
                  message: MessageModel(
                    id: post.id,
                    senderId: post.authorId,
                    receiverId: '',
                    text: post.text,
                    type: 'voice',
                    audioDuration: post.audioDuration,
                    timestamp: post.timestamp,
                  ),
                  isMe: false,
                ),
              ),

            if (post.type == 'video_note')
              Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: VideoNoteBubble(
                    message: MessageModel(
                      id: post.id,
                      senderId: post.authorId,
                      receiverId: '',
                      text: post.text,
                      type: 'video_note',
                      audioDuration: post.audioDuration,
                      timestamp: post.timestamp,
                    ),
                    isMe: false,
                    peerUser: UserModel(
                      uid: post.authorId,
                      phone: '',
                      username: _currentChannel.handle,
                      name: _currentChannel.title,
                      avatarUrl: _currentChannel.avatarUrl,
                      bio: '',
                    ),
                  ),
                ),
              ),

            if (post.text.isNotEmpty && post.type != 'voice' && post.type != 'video_note')
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: buildRichTextWithAppleEmojis(post.text, fontSize: 15, emojiSize: 20, context: context),
              ),

            // Reaction Badges
            if (post.reactions.isNotEmpty)
              _buildPostReactionsBadge(post),

            // Post Footer: View Counter & Timestamp
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.remove_red_eye_outlined, color: Colors.white38, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${post.viewsCount}',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      ),
                    ],
                  ),
                  Text(
                    timeStr,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Bottom Control Bar
  Widget _buildBottomBar() {
    // If current user is channel owner -> Show full broadcasting input bar!
    if (_isOwner) {
      final hasText = _postController.text.trim().isNotEmpty;

      if (_isRecording) {
        final recSecStr = '0:${_recordSeconds.toString().padLeft(2, '0')}';
        final isCancelling = _dragOffsetX < -80;

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              color: Colors.black.withOpacity(0.8),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isCancelling ? Colors.red : Colors.red.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: Row(
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(recSecStr, style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(isCancelling ? 'Отмена!' : 'Проведите для отмены', style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _dragOffsetX += details.delta.dx;
                        if (_dragOffsetX > 0) _dragOffsetX = 0;
                      });
                    },
                    onPanEnd: (_) {
                      if (_dragOffsetX < -80) {
                        _cancelRecording();
                      } else {
                        _finishAndSendRecording();
                      }
                    },
                    child: Transform.translate(
                      offset: Offset(_dragOffsetX, 0),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _isRecordingVideoNote ? Colors.redAccent : const Color(0xFF3390EC),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_isRecordingVideoNote ? Icons.videocam_rounded : Icons.mic_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.50),
                  Colors.black.withOpacity(0.90),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickAndSendPhoto,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Center(
                      child: TextField(
                        controller: _postController,
                        onChanged: (_) => setState(() {}),
                        onTap: () {
                          if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
                        },
                        style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Опубликовать в канал...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                        ),
                        onSubmitted: (_) => _sendPost(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _showEmojiPicker = !_showEmojiPicker);
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _showEmojiPicker ? Colors.white.withOpacity(0.2) : const Color(0xFF1C1C1E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: const Icon(Icons.sentiment_satisfied_alt_rounded, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (hasText) {
                      _sendPost();
                    } else {
                      setState(() => _isCameraMode = !_isCameraMode);
                    }
                  },
                  onLongPressStart: (_) {
                    if (!hasText) _startRecording(isVideo: _isCameraMode);
                  },
                  onLongPressEnd: (_) {
                    if (_isRecording) _finishAndSendRecording();
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: hasText ? const Color(0xFF3390EC) : const Color(0xFF1C1C1E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Icon(
                      hasText
                          ? Icons.arrow_upward_rounded
                          : (_isCameraMode ? Icons.videocam_rounded : Icons.mic_none_rounded),
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Non-owner Subscriber / Guest View -> Liquid Glass Join / Leave Button!
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.60),
                Colors.black.withOpacity(0.95),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _toggleSubscription,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSubscribed
                    ? Colors.redAccent.withOpacity(0.2)
                    : const Color(0xFF3390EC),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: _isSubscribed ? Colors.redAccent.withOpacity(0.4) : Colors.transparent,
                  ),
                ),
              ),
              child: Text(
                _isSubscribed ? 'Покинуть канал' : 'Присоединиться',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Apple HD Emoji Picker Panel for Owner Broadcasting
  Widget _buildEmojiPickerPanel() {
    return Container(
      height: 250,
      color: Colors.black,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: _appleEmojis.length,
        itemBuilder: (context, index) {
          final emoji = _appleEmojis[index];
          return GestureDetector(
            onTap: () {
              _postController.text += emoji;
              _postController.selection = TextSelection.fromPosition(
                TextPosition(offset: _postController.text.length),
              );
            },
            child: Center(
              child: AppleEmojiWidget(emoji: emoji, size: 36),
            ),
          );
        },
      ),
    );
  }
}
