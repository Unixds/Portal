import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../theme/portal_theme.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import 'chats_screen.dart';
import 'forward_message_screen.dart';
import 'channel_detail_screen.dart';

/// Helper to get official Apple Emoji CDN PNG URL
String getAppleEmojiUrl(String emoji) {
  final runes = emoji.runes
      .where((r) => r != 0xfe0f && r != 0x200d)
      .map((r) => r.toRadixString(16).toLowerCase())
      .join('-');
  return 'https://cdn.jsdelivr.net/npm/emoji-datasource-apple@15.0.1/img/apple/64/$runes.png';
}

/// HD Apple Emoji Widget (Renders authentic Apple iOS Emojis on all platforms!)
class AppleEmojiWidget extends StatelessWidget {
  final String emoji;
  final double size;

  const AppleEmojiWidget({
    super.key,
    required this.emoji,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final url = getAppleEmojiUrl(emoji);
    final provider = buildAvatarImageProvider(url);

    return Image(
      image: provider,
      width: size,
      height: size,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return Text(
          emoji,
          style: TextStyle(
            fontSize: size * 0.85,
          ),
        );
      },
    );
  }
}

final RegExp _tokenRegex = RegExp(
  r'(@[a-zA-Z0-9_]{3,30})|(https?:\/\/[^\s]+|www\.[^\s]+)|(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
);

/// Renders mixed text with inline HD Apple Emojis, clickable URLs, and clickable @usernames!
Widget buildRichTextWithAppleEmojis(
  String text, {
  double fontSize = 15,
  Color color = Colors.white,
  double emojiSize = 20,
  BuildContext? context,
}) {
  final List<InlineSpan> spans = [];
  final matches = _tokenRegex.allMatches(text);

  int lastIndex = 0;
  for (var match in matches) {
    if (match.start > lastIndex) {
      spans.add(TextSpan(
        text: text.substring(lastIndex, match.start),
        style: GoogleFonts.inter(fontSize: fontSize, color: color),
      ));
    }

    final matchStr = match.group(0)!;

    if (matchStr.startsWith('@')) {
      // Clickable @username span
      spans.add(
        TextSpan(
          text: matchStr,
          style: GoogleFonts.inter(
            fontSize: fontSize,
            color: const Color(0xFF3390EC),
            fontWeight: FontWeight.bold,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (context != null) {
                _handleUsernameClick(context, matchStr);
              }
            },
        ),
      );
    } else if (matchStr.startsWith('http://') || matchStr.startsWith('https://') || matchStr.startsWith('www.')) {
      // Clickable URL span
      spans.add(
        TextSpan(
          text: matchStr,
          style: GoogleFonts.inter(
            fontSize: fontSize,
            color: const Color(0xFF3390EC),
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF3390EC),
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (context != null) {
                _handleUrlClick(context, matchStr);
              }
            },
        ),
      );
    } else {
      // Emoji Span
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: AppleEmojiWidget(emoji: matchStr, size: emojiSize),
          ),
        ),
      );
    }

    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    spans.add(TextSpan(
      text: text.substring(lastIndex),
      style: GoogleFonts.inter(fontSize: fontSize, color: color),
    ));
  }

  return Text.rich(
    TextSpan(children: spans),
  );
}

void _handleUsernameClick(BuildContext context, String rawHandle) async {
  final cleanHandle = rawHandle.replaceAll('@', '').trim();
  if (cleanHandle.isEmpty) return;

  // 1. Instant 0ms Local Cache Check
  final cachedUser = PortalBackendService.instance.getCachedUserByUsername(cleanHandle);
  if (cachedUser != null) {
    showUserProfileDialog(context, cachedUser);
    return;
  }

  final cachedChannel = PortalBackendService.instance.getCachedChannelByHandle(cleanHandle);
  if (cachedChannel != null) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChannelDetailScreen(channel: cachedChannel)),
    );
    return;
  }

  // 2. Fast Parallel Network Search
  final results = await Future.wait([
    PortalBackendService.instance.searchUserByUsername(cleanHandle),
    PortalBackendService.instance.searchChannelByHandle(cleanHandle),
  ]);

  final user = results[0] as UserModel?;
  final channel = results[1] as ChannelModel?;

  if (user != null) {
    if (context.mounted) {
      showUserProfileDialog(context, user);
    }
    return;
  }

  if (channel != null) {
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChannelDetailScreen(channel: channel)),
      );
    }
    return;
  }

  // Not found banner!
  if (context.mounted) {
    showUserNotFoundToast(context, rawHandle);
  }
}

void _handleUrlClick(BuildContext context, String url) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      duration: const Duration(seconds: 2),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E).withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF3390EC).withOpacity(0.4), width: 1.2),
            ),
            child: Row(
              children: [
                const Icon(Icons.language_rounded, color: Color(0xFF3390EC), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ссылка: $url',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void showUserNotFoundToast(BuildContext context, String handle) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      duration: const Duration(seconds: 3),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E).withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_off_rounded, color: Colors.redAccent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Пользователь не найден',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Пользователь или канал $handle не существует в Portal',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void showUserProfileDialog(BuildContext context, UserModel peerUser) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.7),
    builder: (ctx) {
      final isOnline = peerUser.isOnline;
      final statusText = isOnline
          ? 'в сети'
          : (peerUser.lastSeen != null
              ? 'был(а) ${DateFormat('HH:mm').format(peerUser.lastSeen!)}'
              : 'не в сети');

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
                        backgroundImage: buildAvatarImageProvider(peerUser.avatarUrl),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        peerUser.name,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF1FDB92) : Colors.white38,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusText,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isOnline ? const Color(0xFF1FDB92) : Colors.white54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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
                              leading: const Icon(Icons.alternate_email_rounded, color: Color(0xFF3390EC), size: 20),
                              title: Text(
                                '@${peerUser.username}',
                                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              subtitle: Text(
                                'Имя пользователя',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                              ),
                            ),
                            if (peerUser.bio.isNotEmpty) ...[
                              const Divider(color: Colors.white10, height: 1),
                              ListTile(
                                leading: const Icon(Icons.info_outline_rounded, color: Color(0xFF3390EC), size: 20),
                                title: Text(
                                  peerUser.bio,
                                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
                                ),
                                subtitle: Text(
                                  'О себе',
                                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx); // Close dialog
                            final chat = await PortalBackendService.instance.getOrCreateChat(peerUser);
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatDetailScreen(chat: chat, peerUser: peerUser),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3390EC),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: Text(
                            'Написать сообщение',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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

/// Animated Telegram iOS 3-Dots Jumping Indicator
class TelegramTypingDots extends StatefulWidget {
  const TelegramTypingDots({super.key});

  @override
  State<TelegramTypingDots> createState() => _TelegramTypingDotsState();
}

class _TelegramTypingDotsState extends State<TelegramTypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = (sin((_controller.value * 2 * pi) - delay) + 1) / 2;
            final offsetY = -3.5 * value;

            return Transform.translate(
              offset: Offset(0, offsetY),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3.5,
                height: 3.5,
                decoration: const BoxDecoration(
                  color: Color(0xFF3390EC),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Interactive Playable Voice Message Bubble
class VoiceMessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  double _progress = 0.0;
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _stateSub;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _progress = 0.0;
          }
        });
      }
    });

    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted && widget.message.audioDuration > 0) {
        final totalMs = widget.message.audioDuration * 1000;
        setState(() {
          _progress = (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);
        });
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      _fallbackTimer?.cancel();
    } else {
      final url = widget.message.imageUrl;
      try {
        if (url.startsWith('data:audio')) {
          final base64Str = url.split(',').last;
          final bytes = base64Decode(base64Str);
          await _audioPlayer.play(BytesSource(bytes));
        } else if (url.startsWith('http://') || url.startsWith('https://')) {
          await _audioPlayer.play(UrlSource(url));
        } else if (url.isNotEmpty) {
          await _audioPlayer.play(DeviceFileSource(url));
        } else {
          // Simulated smooth playback
          setState(() {
            _isPlaying = true;
            _progress = 0.0;
          });
          final totalMs = max(widget.message.audioDuration, 1) * 1000;
          const intervalMs = 50;
          _fallbackTimer?.cancel();
          _fallbackTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (t) {
            if (!mounted) return;
            setState(() {
              _progress += intervalMs / totalMs;
              if (_progress >= 1.0) {
                _isPlaying = false;
                _progress = 0.0;
                t.cancel();
              }
            });
          });
        }
      } catch (e) {
        debugPrint('Audio playback error: $e');
      }
    }
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _fallbackTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(widget.message.timestamp);
    final durationStr = '0:${widget.message.audioDuration.toString().padLeft(2, '0')}';

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        decoration: BoxDecoration(
          color: widget.isMe ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _togglePlayback,
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFF3390EC),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(24, (index) {
                        final heights = [6, 12, 18, 10, 14, 20, 12, 8, 16, 14, 18, 10, 14, 20, 12, 8, 16, 10, 14, 18, 12, 8, 14, 10];
                        final isPassed = (index / 24) <= _progress;

                        return Container(
                          width: 2.5,
                          height: heights[index % heights.length].toDouble(),
                          decoration: BoxDecoration(
                            color: isPassed
                                ? const Color(0xFF3390EC)
                                : Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        durationStr,
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeStr,
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                          ),
                          if (widget.isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              widget.message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                              color: widget.message.isRead ? const Color(0xFF3390EC) : Colors.white54,
                              size: 15,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Telegram iOS Circular Video Note Message Bubble ("Кружок")
class VideoNoteBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final UserModel peerUser;

  const VideoNoteBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.peerUser,
  });

  @override
  State<VideoNoteBubble> createState() => _VideoNoteBubbleState();
}

class _VideoNoteBubbleState extends State<VideoNoteBubble> {
  bool _isPlaying = false;
  double _progress = 0.0;
  Timer? _playbackTimer;

  void _togglePlayback() {
    if (_isPlaying) {
      _stopPlayback();
    } else {
      setState(() {
        _isPlaying = true;
        _progress = 0.0;
      });

      final totalMs = max(widget.message.audioDuration, 1) * 1000;
      const intervalMs = 50;

      _playbackTimer?.cancel();
      _playbackTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
        if (!mounted) return;
        setState(() {
          _progress += intervalMs / totalMs;
          if (_progress >= 1.0) {
            _stopPlayback();
          }
        });
      });
    }
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _progress = 0.0;
      });
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(widget.message.timestamp);
    final avatar = widget.isMe
        ? (PortalBackendService.instance.currentUser?.avatarUrl ?? '')
        : widget.peerUser.avatarUrl;

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _togglePlayback,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 204,
                    height: 204,
                    child: CircularProgressIndicator(
                      value: _isPlaying ? _progress : 1.0,
                      strokeWidth: 3.5,
                      color: _isPlaying ? const Color(0xFF3390EC) : Colors.white.withOpacity(0.2),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  Container(
                    width: 192,
                    height: 192,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1C1C1E),
                      border: Border.all(color: Colors.white12, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(
                            image: buildAvatarImageProvider(avatar),
                            gaplessPlayback: true,
                            fit: BoxFit.cover,
                          ),
                          if (!_isPlaying)
                            Container(color: Colors.black.withOpacity(0.35)),
                          if (!_isPlaying)
                            Center(
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(timeStr, style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
                  if (widget.isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      widget.message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                      color: widget.message.isRead ? const Color(0xFF3390EC) : Colors.white54,
                      size: 15,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Direct Chat Screen with Telegram Circular Video Notes, Voice Notes & Finger Sliding Button Gesture.
class ChatDetailScreen extends StatefulWidget {
  final ChatModel chat;
  final UserModel peerUser;

  const ChatDetailScreen({
    super.key,
    required this.chat,
    required this.peerUser,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showEmojiPicker = false;
  Timer? _typingTimer;

  // Toggle Mode: Voice (false) vs Video Note Camera (true)
  bool _isCameraMode = false;

  // Recording State (Voice OR Circular Video Note)
  bool _isRecording = false;
  bool _isRecordingVideoNote = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  double _dragOffsetX = 0.0;

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
    PortalBackendService.instance.markMessagesAsRead(widget.chat.chatId, widget.peerUser.uid);
  }

  final AudioRecorder _audioRecorder = AudioRecorder();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    PortalBackendService.instance.setTypingStatus(widget.chat.chatId, false);
    super.dispose();
  }

  void _onTextChanged(String text) {
    setState(() {});
    if (text.trim().isNotEmpty) {
      PortalBackendService.instance.setTypingStatus(widget.chat.chatId, true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        PortalBackendService.instance.setTypingStatus(widget.chat.chatId, false);
      });
    } else {
      PortalBackendService.instance.setTypingStatus(widget.chat.chatId, false);
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    PortalBackendService.instance.setTypingStatus(widget.chat.chatId, false);
    _typingTimer?.cancel();

    PortalBackendService.instance.sendMessage(
      chatId: widget.chat.chatId,
      text: text,
      peerUid: widget.peerUser.uid,
    );

    _messageController.clear();
    setState(() {});
    _scrollToBottom();
  }

  // Start Voice or Video Note Recording (With Explicit iOS Permissions!)
  Future<void> _startRecording({required bool isVideo}) async {
    FocusScope.of(context).unfocus();

    if (isVideo) {
      // Request Camera & Microphone access on iOS
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isGranted && micStatus.isGranted) {
        try {
          final picker = ImagePicker();
          final video = await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 1),
          );

          if (video != null) {
            final bytes = await video.readAsBytes();
            final base64Video = 'data:video/mp4;base64,${base64Encode(bytes)}';

            PortalBackendService.instance.sendVideoNoteMessage(
              chatId: widget.chat.chatId,
              durationSeconds: 10,
              peerUid: widget.peerUser.uid,
              videoUrl: base64Video,
            );
            _scrollToBottom();
          }
        } catch (e) {
          debugPrint('Error picking video note: $e');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Разрешите доступ к Камере и Микрофону в настройках iPhone', style: GoogleFonts.inter(color: Colors.white)),
              backgroundColor: const Color(0xFF1C1C1E),
              action: SnackBarAction(
                label: 'Настройки',
                textColor: const Color(0xFF3390EC),
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }
      return;
    }

    // Voice Message Recording Mode
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Разрешите доступ к Микрофону в настройках iPhone', style: GoogleFonts.inter(color: Colors.white)),
            backgroundColor: const Color(0xFF1C1C1E),
            action: SnackBarAction(
              label: 'Настройки',
              textColor: const Color(0xFF3390EC),
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _isRecordingVideoNote = false;
      _recordSeconds = 0;
      _dragOffsetX = 0.0;
      _showEmojiPicker = false;
    });

    try {
      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: '',
        );
      }
    } catch (e) {
      debugPrint('Audio record start error: $e');
    }

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
    try {
      _audioRecorder.stop();
    } catch (_) {}
    setState(() {
      _isRecording = false;
      _isRecordingVideoNote = false;
      _recordSeconds = 0;
      _dragOffsetX = 0.0;
    });
  }

  Future<void> _finishAndSendRecording() async {
    if (!_isRecording) return;

    if (_dragOffsetX < -80) {
      _cancelRecording();
      return;
    }

    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (_) {}

    final duration = max(_recordSeconds, 1);
    _cancelRecording();

    String audioDataUrl = '';
    if (path != null && path.isNotEmpty) {
      try {
        final bytes = await XFile(path).readAsBytes();
        audioDataUrl = 'data:audio/m4a;base64,${base64Encode(bytes)}';
      } catch (_) {}
    }

    PortalBackendService.instance.sendVoiceMessage(
      chatId: widget.chat.chatId,
      durationSeconds: duration,
      peerUid: widget.peerUser.uid,
      audioUrl: audioDataUrl,
    );

    _scrollToBottom();
  }

  // Pick Photo & Caption Modal
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
                            PortalBackendService.instance.sendImageMessage(
                              chatId: widget.chat.chatId,
                              imageBase64OrUrl: base64Image,
                              caption: caption,
                              peerUid: widget.peerUser.uid,
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

  bool _isOnlyEmoji(String text) {
    if (text.trim().isEmpty) return false;
    final emojiRegExp = RegExp(
      r'^(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]|\s)+$',
    );
    return emojiRegExp.hasMatch(text.trim());
  }

  String _formatPresenceStatus(UserModel? user) {
    if (user == null) return 'был(а) недавно';
    if (user.isOnline) return 'в сети';
    if (user.lastSeen != null) {
      final now = DateTime.now();
      final diff = now.difference(user.lastSeen!);
      if (diff.inDays == 0 && now.day == user.lastSeen!.day) {
        return 'был(а) в ${DateFormat('HH:mm').format(user.lastSeen!)}';
      }
      return 'был(а) ${DateFormat('dd MMM в HH:mm').format(user.lastSeen!)}';
    }
    return 'был(а) недавно';
  }

  void _openFullscreenImage(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: Image(
                    image: buildAvatarImageProvider(imageUrl),
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 48,
                right: 20,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openPeerProfileDialog(UserModel peerUser) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) {
        final statusText = _formatPresenceStatus(peerUser);
        final isOnline = peerUser.isOnline;

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
                          backgroundImage: buildAvatarImageProvider(peerUser.avatarUrl),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          peerUser.name,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isOnline ? const Color(0xFF1FDB92) : Colors.white38,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: isOnline ? const Color(0xFF1FDB92) : Colors.white54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
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
                                  child: const Text('@', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                                title: Text('Имя пользователя', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
                                subtitle: Text('@${peerUser.username}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                              ),
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
                                title: Text('О себе', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
                                subtitle: Text(
                                  peerUser.bio.isNotEmpty ? peerUser.bio : 'Описание отсутствует',
                                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                                ),
                              ),
                              const Divider(color: Colors.white10, height: 1),
                              ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.phone_outlined, color: Colors.white, size: 18),
                                ),
                                title: Text('Номер телефона', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
                                subtitle: Text(peerUser.phone, style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        PortalTheme.liquidGlassWidget(
                          borderRadius: 18,
                          fillColor: Colors.white.withOpacity(0.06),
                          borderColor: Colors.white.withOpacity(0.12),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              TextButton.icon(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF3390EC), size: 18),
                                label: Text('Чат', style: GoogleFonts.inter(color: const Color(0xFF3390EC), fontSize: 13)),
                              ),
                              TextButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.phone_outlined, color: Color(0xFF1FDB92), size: 18),
                                label: Text('Звонок', style: GoogleFonts.inter(color: const Color(0xFF1FDB92), fontSize: 13)),
                              ),
                              TextButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.block_rounded, color: PortalTheme.roseAccent, size: 18),
                                label: Text('Блок', style: GoogleFonts.inter(color: PortalTheme.roseAccent, fontSize: 13)),
                              ),
                            ],
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

  void _showTelegramMessageContextMenu(BuildContext context, MessageModel message) {
    final isMe = message.senderId == PortalBackendService.instance.currentUser?.uid;
    final quickEmojis = ['👍', '❤️', '🔥', '😂', '😮', '😢', '👏', '🎉', '🚀', '💯', '💎', '🖤'];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ContextMenu',
      barrierColor: Colors.black.withOpacity(0.75),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) {
        return Material(
          color: Colors.transparent,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Emoji Reactions Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E).withOpacity(0.92),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.18)),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: quickEmojis.map((emoji) {
                                final myUid = PortalBackendService.instance.currentUser?.uid ?? '';
                                final isSelected = message.reactions[myUid] == emoji;

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    PortalBackendService.instance.toggleMessageReaction(
                                      chatId: widget.chat.chatId,
                                      messageId: message.id,
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
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Scaled Preview of Selected Message Bubble
                    Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFF6B55D3) : const Color(0xFF1D2333),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.14)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.type == 'image' && message.imageUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image(
                                image: buildAvatarImageProvider(message.imageUrl),
                                gaplessPlayback: true,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 180,
                              ),
                            ),
                          if (message.text.isNotEmpty)
                            buildRichTextWithAppleEmojis(message.text, fontSize: 16),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Liquid Glass Action Options Menu
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          width: 260,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E).withOpacity(0.92),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.14)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message.text.isNotEmpty) ...[
                                InkWell(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    Clipboard.setData(ClipboardData(text: message.text));
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
                                  _showForwardModalSheet(context, message);
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
                              const Divider(color: Colors.white10, height: 1),
                              InkWell(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  PortalBackendService.instance.deleteMessage(
                                    chatId: widget.chat.chatId,
                                    messageId: message.id,
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                      const SizedBox(width: 14),
                                      Text('Удалить сообщение', style: GoogleFonts.inter(fontSize: 15, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  void _showForwardModalSheet(BuildContext context, MessageModel message) {
    final originalAuthorName = message.forwardedSenderName.isNotEmpty
        ? message.forwardedSenderName
        : (message.senderId == PortalBackendService.instance.currentUser?.uid
            ? (PortalBackendService.instance.currentUser?.name ?? 'Пользователь')
            : widget.peerUser.name);

    final originalAuthorAvatar = message.forwardedSenderAvatar.isNotEmpty
        ? message.forwardedSenderAvatar
        : (message.senderId == PortalBackendService.instance.currentUser?.uid
            ? (PortalBackendService.instance.currentUser?.avatarUrl ?? '')
            : widget.peerUser.avatarUrl);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessageScreen(
          text: message.text,
          type: message.type,
          imageUrl: message.imageUrl,
          audioDuration: message.audioDuration,
          originalAuthorName: originalAuthorName,
          originalAuthorAvatar: originalAuthorAvatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserAvatar = PortalBackendService.instance.currentUser?.avatarUrl ?? '';

    return StreamBuilder<UserModel?>(
      stream: PortalBackendService.instance.getUserProfileStream(widget.peerUser.uid),
      builder: (context, snapshot) {
        final livePeerUser = snapshot.data ?? widget.peerUser;
        final statusText = _formatPresenceStatus(livePeerUser);

        return StreamBuilder<bool>(
          stream: PortalBackendService.instance.getTypingStatusStream(widget.chat.chatId, widget.peerUser.uid),
          builder: (context, typingSnapshot) {
            final isPeerTyping = typingSnapshot.data ?? false;

            return Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Stack(
                  children: [
                    // Main Chat Messages Stream Layer
                    Positioned.fill(
                      child: Column(
                        children: [
                          Expanded(
                            child: StreamBuilder<List<MessageModel>>(
                              stream: PortalBackendService.instance.getMessagesStream(widget.chat.chatId),
                              builder: (context, msgSnapshot) {
                                final messages = msgSnapshot.data ?? [];
                                PortalBackendService.instance.markMessagesAsRead(widget.chat.chatId, widget.peerUser.uid);

                                if (messages.isEmpty) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Text(
                                        'Нет сообщений. Напишите первыми!',
                                        style: PortalTheme.subText(color: Colors.white38),
                                      ),
                                    ),
                                  );
                                }

                                return ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.fromLTRB(16, 76, 16, 80),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) {
                                    final msg = messages[index];
                                    final isMe = msg.senderId == PortalBackendService.instance.currentUser?.uid;
                                    return KeyedSubtree(
                                      key: ValueKey(msg.id),
                                      child: _buildMessageBubble(msg, isMe, livePeerUser),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          if (_showEmojiPicker) _buildEmojiPickerPanel(),
                          const SizedBox(height: 64),
                        ],
                      ),
                    ),

                    // Translucent Floating Liquid Glass Top Header Bar with Soft Gradient Blur Fade
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTopBar(livePeerUser, statusText, isPeerTyping),
                    ),

                    // Fullscreen Blurred Overlay when Recording Circular Video Note ("Кружок")
                    if (_isRecording && _isRecordingVideoNote)
                      Positioned.fill(
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              color: Colors.black.withOpacity(0.75),
                              padding: const EdgeInsets.only(bottom: 80),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 250,
                                    height: 250,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.redAccent, width: 4),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.redAccent.withOpacity(0.5),
                                          blurRadius: 30,
                                          spreadRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image(
                                            image: buildAvatarImageProvider(currentUserAvatar),
                                            gaplessPlayback: true,
                                            fit: BoxFit.cover,
                                          ),
                                          Positioned(
                                            bottom: 12,
                                            left: 0,
                                            right: 0,
                                            child: Center(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.65),
                                                  borderRadius: BorderRadius.circular(14),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: const BoxDecoration(
                                                        color: Colors.redAccent,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '0:${_recordSeconds.toString().padLeft(2, '0')}',
                                                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.arrow_back_ios_rounded, color: Colors.white54, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Проведите влево для отмены',
                                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Bottom Message Input Bar (ALWAYS ON TOP of Stack!)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildMessageInput(),
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

  // Floating Translucent Liquid Glass Top Bar Header with Soft Gradient Fade Edge
  Widget _buildTopBar(UserModel peerUser, String statusText, bool isPeerTyping) {
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
                  onTap: () => _openPeerProfileDialog(peerUser),
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
                          backgroundImage: buildAvatarImageProvider(peerUser.avatarUrl),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peerUser.name,
                              style: PortalTheme.titleHeader(fontSize: 15, color: Colors.white),
                            ),
                            const SizedBox(height: 1),
                            if (isPeerTyping)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'печатает',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF3390EC), fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 4),
                                  const TelegramTypingDots(),
                                ],
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: peerUser.isOnline ? const Color(0xFF1FDB92) : Colors.white38,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: peerUser.isOnline ? const Color(0xFF1FDB92) : Colors.white54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
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
                  onPressed: () => _openPeerProfileDialog(peerUser),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Emoji Panel with Authentic Apple HD Emojis
  Widget _buildEmojiPickerPanel() {
    return Container(
      height: 270,
      color: Colors.black,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('Apple эмодзи', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
                Text('${_appleEmojis.length} эмодзи', style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    _messageController.text += emoji;
                    _onTextChanged(_messageController.text);
                    _messageController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _messageController.text.length),
                    );
                  },
                  child: Center(
                    child: AppleEmojiWidget(emoji: emoji, size: 36),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: 220,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Text('Стикеры', style: GoogleFonts.inter(fontSize: 13, color: Colors.white54)),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: Center(
                        child: Text('Эмодзи', style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForwardHeader(String authorName, String authorAvatar) {
    if (authorName.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF3390EC), width: 2.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundImage: buildAvatarImageProvider(authorAvatar),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Переслано от $authorName',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3390EC),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionsBadge(MessageModel msg) {
    if (msg.reactions.isEmpty) return const SizedBox.shrink();

    final Map<String, int> counts = {};
    msg.reactions.forEach((uid, emoji) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    });

    final myUid = PortalBackendService.instance.currentUser?.uid ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: counts.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value;
          final isMyReaction = msg.reactions[myUid] == emoji;

          return GestureDetector(
            onTap: () {
              PortalBackendService.instance.toggleMessageReaction(
                chatId: widget.chat.chatId,
                messageId: msg.id,
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

  Widget _buildReadReceiptIcon(bool isRead) {
    if (isRead) {
      return const Icon(Icons.done_all_rounded, color: Color(0xFF3390EC), size: 15);
    }
    return const Icon(Icons.done_rounded, color: Colors.white54, size: 15);
  }

  // Message Bubble Dispatcher
  Widget _buildMessageBubble(MessageModel msg, bool isMe, UserModel peerUser) {
    Widget childWidget;

    if (msg.type == 'video_note') {
      childWidget = VideoNoteBubble(message: msg, isMe: isMe, peerUser: peerUser);
    } else if (msg.type == 'voice') {
      childWidget = VoiceMessageBubble(message: msg, isMe: isMe);
    } else {
      final timeStr = DateFormat('HH:mm').format(msg.timestamp);
      final isEmojiOnly = _isOnlyEmoji(msg.text);

      if (msg.type == 'text' && isEmojiOnly) {
        final chars = msg.text.characters.toList();
        childWidget = Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chars.map((ch) {
                    return AppleEmojiWidget(emoji: ch, size: 48);
                  }).toList(),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(timeStr, style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildReadReceiptIcon(msg.isRead),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      } else if (msg.type == 'image') {
        childWidget = Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => _openFullscreenImage(msg.imageUrl),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.74,
              ),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (msg.forwardedSenderName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: _buildForwardHeader(msg.forwardedSenderName, msg.forwardedSenderAvatar),
                    ),
                  ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(msg.forwardedSenderName.isNotEmpty ? 4 : 20),
                      bottom: Radius.circular(msg.text.isNotEmpty ? 4 : 20),
                    ),
                    child: Image(
                      image: buildAvatarImageProvider(msg.imageUrl),
                      gaplessPlayback: true,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 220,
                    ),
                  ),
                  if (msg.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: buildRichTextWithAppleEmojis(msg.text, fontSize: 14, emojiSize: 18, context: context),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 10, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Text(timeStr, style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          _buildReadReceiptIcon(msg.isRead),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        childWidget = Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 6),
                bottomRight: Radius.circular(isMe ? 6 : 18),
              ),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.forwardedSenderName.isNotEmpty)
                  _buildForwardHeader(msg.forwardedSenderName, msg.forwardedSenderAvatar),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: buildRichTextWithAppleEmojis(msg.text, fontSize: 15, emojiSize: 20, context: context),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          _buildReadReceiptIcon(msg.isRead),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }

    return GestureDetector(
      onLongPress: () => _showTelegramMessageContextMenu(context, msg),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          childWidget,
          if (msg.reactions.isNotEmpty)
            _buildReactionsBadge(msg),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // Dual-mode Input Bar (ALWAYS ON TOP of Stack, with Soft Backdrop Blur & Finger Sliding Recording Button!)
  Widget _buildMessageInput() {
    final hasText = _messageController.text.trim().isNotEmpty;

    // Active Recording Input Bar View
    if (_isRecording) {
      final recSecStr = '0:${_recordSeconds.toString().padLeft(2, '0')}';
      final isCancelling = _dragOffsetX < -80;

      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.40),
                  Colors.black.withOpacity(0.85),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isCancelling ? Colors.red : Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: isCancelling ? Colors.white : Colors.redAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          recSecStr,
                          style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Icon(Icons.arrow_back_ios_rounded, color: Colors.white38, size: 12),
                              const SizedBox(width: 2),
                              Text(
                                isCancelling ? 'Отмена!' : 'Проведите для отмены',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: isCancelling ? Colors.redAccent : Colors.white38,
                                  fontWeight: isCancelling ? FontWeight.bold : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
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
                  onPanEnd: (details) {
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
                        color: isCancelling
                            ? Colors.red
                            : (_isRecordingVideoNote ? Colors.redAccent : const Color(0xFF3390EC)),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecordingVideoNote ? Colors.redAccent : const Color(0xFF3390EC)).withOpacity(0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecordingVideoNote ? Icons.videocam_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal Input Bar View with Soft Top Gradient Blur Fade
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.40),
                Colors.black.withOpacity(0.85),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Row(
            children: [
              // Photo Attachment Button
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
                      controller: _messageController,
                      onChanged: _onTextChanged,
                      onTap: () {
                        if (_showEmojiPicker) {
                          setState(() => _showEmojiPicker = false);
                        }
                      },
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Сообщение',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                      ),
                      onSubmitted: (_) => _sendMessage(),
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
                    _sendMessage();
                  } else {
                    setState(() {
                      _isCameraMode = !_isCameraMode;
                    });
                  }
                },
                onLongPressStart: (_) {
                  if (!hasText) {
                    _startRecording(isVideo: _isCameraMode);
                  }
                },
                onLongPressMoveUpdate: (details) {
                  if (!hasText && _isRecording) {
                    setState(() {
                      _dragOffsetX += details.offsetFromOrigin.dx;
                      if (_dragOffsetX > 0) _dragOffsetX = 0;
                    });
                  }
                },
                onLongPressEnd: (_) {
                  if (_isRecording) {
                    _finishAndSendRecording();
                  }
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
}
