import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import '../../theme/portal_theme.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import 'chats_screen.dart';
import 'forward_message_screen.dart';
import 'channel_detail_screen.dart';
import '../../widgets/verified_badge.dart';
import '../../services/music_service.dart';
import '../../widgets/music_player_modal.dart';

import '../profile/user_profile_detail_screen.dart';
import '../calls/call_screen.dart';

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

  // 2. Fast Network Search
  final user = await PortalBackendService.instance.searchUserByUsername(cleanHandle);
  final channel = await PortalBackendService.instance.searchChannelByHandle(cleanHandle);

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
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => UserProfileDetailScreen(user: peerUser),
    ),
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

    // Ensure audio routing goes to device speaker at full volume
    try {
      AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.defaultToSpeaker},
          ),
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
    } catch (e) {
      debugPrint('AudioContext set error: $e');
    }

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
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/voice_${widget.message.id}.m4a');
          if (!await tempFile.exists()) {
            await tempFile.writeAsBytes(bytes);
          }
          await _audioPlayer.play(DeviceFileSource(tempFile.path));
        } else if (url.startsWith('http://') || url.startsWith('https://')) {
          await _audioPlayer.play(UrlSource(url));
        } else if (url.isNotEmpty && File(url).existsSync()) {
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
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final videoData = widget.message.imageUrl;
    if (videoData.isEmpty) return;

    try {
      if (videoData.startsWith('data:video')) {
        final base64Str = videoData.split(',').last;
        final bytes = base64Decode(base64Str);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/vn_${widget.message.id}.mp4');
        if (!await tempFile.exists()) {
          await tempFile.writeAsBytes(bytes);
        }
        _controller = VideoPlayerController.file(tempFile);
      } else if (videoData.startsWith('http://') || videoData.startsWith('https://')) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoData));
      } else if (File(videoData).existsSync()) {
        _controller = VideoPlayerController.file(File(videoData));
      }

      if (_controller != null) {
        await _controller!.initialize();
        await _controller!.setLooping(true);
        _controller!.addListener(_onControllerUpdate);
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('VideoNote initialize error: $e');
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    setState(() {
      _isPlaying = _controller!.value.isPlaying;
    });
  }

  void _togglePlayback() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(widget.message.timestamp);
    final avatar = widget.isMe
        ? (PortalBackendService.instance.currentUser?.avatarUrl ?? '')
        : widget.peerUser.avatarUrl;

    double progress = 0.0;
    if (_controller != null && _isInitialized && _controller!.value.duration.inMilliseconds > 0) {
      progress = (_controller!.value.position.inMilliseconds / _controller!.value.duration.inMilliseconds).clamp(0.0, 1.0);
    }

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
                      value: _isPlaying ? progress : 1.0,
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
                          if (_isInitialized && _controller != null)
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _controller!.value.size.width,
                                height: _controller!.value.size.height,
                                child: VideoPlayer(_controller!),
                              ),
                            )
                          else
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

/// Telegram Video Note ("Кружок") Live Camera Recorder Modal Sheet
class VideoNoteRecorderModal extends StatefulWidget {
  final String chatId;
  final String peerUid;
  final VoidCallback onSent;

  const VideoNoteRecorderModal({
    super.key,
    required this.chatId,
    required this.peerUid,
    required this.onSent,
  });

  @override
  State<VideoNoteRecorderModal> createState() => _VideoNoteRecorderModalState();
}

class _VideoNoteRecorderModalState extends State<VideoNoteRecorderModal> with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isInitializing = true;
  bool _isRecording = false;
  int _recordMs = 0;
  Timer? _timer;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      _selectedCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;

      await _setupController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _setupController(CameraDescription description) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        _startRecording();
      }
    } catch (e) {
      debugPrint('Camera controller init error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    setState(() => _isInitializing = true);
    await _setupController(_cameras[_selectedCameraIndex]);
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isRecording) return;

    try {
      await _cameraController!.startVideoRecording();
      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordMs = 0;
        });
      }

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
        if (mounted && _isRecording) {
          setState(() {
            _recordMs += 30;
          });
          if (_recordMs >= 60000) {
            _stopAndSendRecording();
          }
        }
      });
    } catch (e) {
      debugPrint('Start video recording error: $e');
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    if (_cameraController != null && _isRecording) {
      try {
        await _cameraController!.stopVideoRecording();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _stopAndSendRecording() async {
    if (_cameraController == null || !_isRecording) return;

    _timer?.cancel();
    try {
      final videoFile = await _cameraController!.stopVideoRecording();
      final appDir = await getApplicationDocumentsDirectory();
      final savedPath = '${appDir.path}/vnote_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(videoFile.path).copy(savedPath);

      final durationSeconds = max((_recordMs / 1000).ceil(), 1);

      await PortalBackendService.instance.sendVideoNoteMessage(
        chatId: widget.chatId,
        durationSeconds: durationSeconds,
        peerUid: widget.peerUid,
        videoUrl: savedPath,
      );

      widget.onSent();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Stop and send video error: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _recordMs ~/ 1000;
    final hundredths = (_recordMs % 1000) ~/ 10;
    final recordStr = '0:${seconds.toString().padLeft(2, '0')},${hundredths.toString().padLeft(2, '0')}';
    final progress = (_recordMs / 60000).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Semi-transparent blurred backdrop overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                color: Colors.black.withOpacity(0.70),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(),

                // Center Large Circular Camera Preview
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // White outer progress stroke ring
                      SizedBox(
                        width: 288,
                        height: 288,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3.5,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      // Circle Camera Preview
                      Container(
                        width: 276,
                        height: 276,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF1C1C1E),
                        ),
                        child: ClipOval(
                          child: _isInitializing ||
                                  _cameraController == null ||
                                  !_cameraController!.value.isInitialized
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF3390EC),
                                  ),
                                )
                              : FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _cameraController!.value.previewSize?.height ?? 276,
                                    height: _cameraController!.value.previewSize?.width ?? 276,
                                    child: CameraPreview(_cameraController!),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Bottom row with Camera Switch button & Bottom Rounded Floating Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Camera Switch Button (Bottom Left)
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _switchCamera,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E).withOpacity(0.9),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.12)),
                              ),
                              child: const Icon(
                                Icons.cameraswitch_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Bottom Floating Rounded Bar ("Скругленная плашка")
                      Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Left: Timer (0:09,82) with Red Pulsing Dot
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.4 + 0.6 * _pulseController.value),
                                    shape: BoxShape.circle,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: Text(
                                recordStr,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),

                            // Center: Cancel ("Отмена") Text Button
                            Expanded(
                              child: Center(
                                child: GestureDetector(
                                  onTap: _cancelRecording,
                                  child: Text(
                                    'Отмена',
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF3390EC),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Right: Prominent Blue Circular Send Button (↑)
                            GestureDetector(
                              onTap: _stopAndSendRecording,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF3390EC),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
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
          ),
        ],
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

class _ChatDetailScreenState extends State<ChatDetailScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showEmojiPicker = false;
  Timer? _typingTimer;

  // Toggle Mode: Voice (false) vs Video Note Camera (true)
  bool _isCameraMode = false;

  late AnimationController _recButtonAnimController;
  late Animation<double> _recButtonScaleAnim;

  // Replying message state & Highlight tracking
  MessageModel? _replyingToMessage;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _messageKeys = {};
  List<MessageModel> _currentMessages = [];

  void _onReplyToMessage(MessageModel msg) {
    HapticFeedback.lightImpact();
    setState(() {
      _replyingToMessage = msg;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  void _sendMusicTrack(MusicTrackModel track) {
    final now = DateTime.now();
    final msgId = 'msg_${now.millisecondsSinceEpoch}';

    final currentUser = PortalBackendService.instance.currentUser;
    final musicMessage = MessageModel(
      id: msgId,
      senderId: currentUser?.uid ?? '',
      receiverId: widget.peerUser.uid,
      text: '${track.artist} - ${track.title}',
      type: 'music',
      mediaUrl: track.audioUrl,
      audioDuration: track.durationSeconds,
      isRead: false,
      timestamp: now,
      forwardedSenderName: track.artist,
      forwardedSenderAvatar: currentUser?.avatarUrl ?? '',
    );

    final chatId = widget.chat.chatId;
    PortalBackendService.instance.sendCustomMessage(chatId: chatId, message: musicMessage);
  }

  Future<void> _pickAndSendMusicTrack() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'flac'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final cleanName = file.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        final track = MusicTrackModel(
          id: 'user_file_${DateTime.now().millisecondsSinceEpoch}',
          title: cleanName,
          artist: PortalBackendService.instance.currentUser?.name ?? 'Музыка',
          audioUrl: file.path ?? PortalMusicService.demoTracks[0].audioUrl,
          durationSeconds: 195,
        );
        _sendMusicTrack(track);
      }
    } catch (e) {
      debugPrint('pick music error: $e');
    }
  }

  Future<void> _pickAndSendPhoto() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Str = base64Encode(bytes);
        final imageUrl = 'data:image/jpeg;base64,$base64Str';

        final now = DateTime.now();
        final msgId = 'msg_${now.millisecondsSinceEpoch}';
        final currentUser = PortalBackendService.instance.currentUser;

        final imageMessage = MessageModel(
          id: msgId,
          senderId: currentUser?.uid ?? '',
          receiverId: widget.peerUser.uid,
          text: '',
          type: 'image',
          imageUrl: imageUrl,
          isRead: false,
          timestamp: now,
        );

        PortalBackendService.instance.sendCustomMessage(chatId: widget.chat.chatId, message: imageMessage);
      }
    } catch (e) {
      debugPrint('pick photo error: $e');
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
              Text(
                'Вложить файл',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8E2DE2).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.library_music_rounded, color: Color(0xFF8E2DE2), size: 22),
                ),
                title: Text(
                  'Музыка и MP3 файлы',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                subtitle: Text(
                  'Отправить MP3 трек или песню из библиотеки',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMusicPickerModal();
                },
              ),
              const Divider(color: Colors.white10),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3390EC).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.image_rounded, color: Color(0xFF3390EC), size: 22),
                ),
                title: Text(
                  'Фотогалерея',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                subtitle: Text(
                  'Выбрать фото из медиатеки',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendPhoto();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMusicPickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161618),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final currentUser = PortalBackendService.instance.currentUser;
        final savedTracks = (currentUser?.savedMusicTracks ?? []).map((m) => MusicTrackModel.fromMap(m)).toList();
        final allTracks = [...savedTracks, ...PortalMusicService.demoTracks];

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
              Text(
                'Выберите песню для отправки',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendMusicTrack();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3390EC).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF3390EC).withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.upload_file_rounded, color: Color(0xFF3390EC), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Загрузить MP3 файл с устройства...',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 300,
                child: ListView.builder(
                  itemCount: allTracks.length,
                  itemBuilder: (context, index) {
                    final track = allTracks[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8E2DE2).withOpacity(0.25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 22),
                        ),
                        title: Text(
                          track.title,
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Text(
                          track.artist,
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                        ),
                        trailing: const Icon(Icons.send_rounded, color: Color(0xFF3390EC), size: 20),
                        onTap: () {
                          Navigator.pop(ctx);
                          _sendMusicTrack(track);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _scrollToAndHighlightMessage(String targetId) {
    if (targetId.isEmpty) return;

    final key = _messageKeys[targetId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else if (_scrollController.hasClients && _currentMessages.isNotEmpty) {
      final index = _currentMessages.indexWhere((m) => m.id == targetId);
      if (index != -1) {
        final total = _currentMessages.length;
        final targetOffset = (index / total) * _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
        );
      }
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _highlightedMessageId = targetId;
    });

    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  String _getReplyPreviewText(MessageModel msg) {
    if (msg.type == 'voice') {
      return 'Голосовое сообщение';
    } else if (msg.type == 'video_note') {
      return 'Видеосообщение';
    } else if (msg.type == 'image') {
      return msg.text.isNotEmpty ? msg.text : '📷 Фотография';
    } else {
      return msg.text.isNotEmpty ? msg.text : 'Сообщение';
    }
  }

  // Recording State (Voice OR Circular Video Note)
  bool _isRecording = false;
  bool _isRecordingVideoNote = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  Timer? _holdTimer;
  bool _isPointerDown = false;
  bool _hasTriggeredHold = false;
  double _dragOffsetX = 0.0;
  DateTime? _touchDownTime;
  bool _isHoldingRecord = false;
  Offset _touchDownPosition = Offset.zero;

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

  ChatModel get _liveChat {
    return PortalBackendService.instance.chats.firstWhere(
      (c) => c.chatId == widget.chat.chatId,
      orElse: () => widget.chat,
    );
  }

  @override
  void initState() {
    super.initState();
    _recButtonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _recButtonScaleAnim = Tween<double>(begin: 1.0, end: 1.28).animate(
      CurvedAnimation(parent: _recButtonAnimController, curve: Curves.easeOutCubic),
    );
    PortalBackendService.instance.markMessagesAsRead(widget.chat.chatId, widget.peerUser.uid);
    PortalBackendService.instance.addListener(_onBackendUpdated);
  }

  final AudioRecorder _audioRecorder = AudioRecorder();

  @override
  void dispose() {
    _recButtonAnimController.dispose();
    PortalBackendService.instance.removeListener(_onBackendUpdated);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    PortalBackendService.instance.setTypingStatus(widget.chat.chatId, false);
    super.dispose();
  }

  void _onBackendUpdated() {
    if (mounted) setState(() {});
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

    final replyMsg = _replyingToMessage;
    final replySenderName = replyMsg == null
        ? ''
        : (replyMsg.senderId == PortalBackendService.instance.currentUser?.uid
            ? (PortalBackendService.instance.currentUser?.name ?? 'Вы')
            : widget.peerUser.name);
    final replyPreview = replyMsg != null ? _getReplyPreviewText(replyMsg) : '';

    PortalBackendService.instance.sendMessage(
      chatId: widget.chat.chatId,
      text: text,
      peerUid: widget.peerUser.uid,
      replyMessageId: replyMsg?.id ?? '',
      replySenderName: replySenderName,
      replyText: replyPreview,
      replyType: replyMsg?.type ?? '',
    );

    _messageController.clear();
    setState(() {
      _replyingToMessage = null;
    });
    _scrollToBottom();
  }

  // Start Voice or Video Note Recording (With Explicit Permissions!)
  Future<void> _startRecording({required bool isVideo}) async {
    FocusScope.of(context).unfocus();

    if (isVideo) {
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isGranted && micStatus.isGranted) {
        if (mounted) {
          showGeneralDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.transparent,
            pageBuilder: (ctx, anim1, anim2) {
              return VideoNoteRecorderModal(
                chatId: widget.chat.chatId,
                peerUid: widget.peerUser.uid,
                onSent: () => _scrollToBottom(),
              );
            },
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Разрешите доступ к Камере и Микрофону в настройках устройства', style: GoogleFonts.inter(color: Colors.white)),
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
            content: Text('Разрешите доступ к Микрофону в настройках устройства', style: GoogleFonts.inter(color: Colors.white)),
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
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileDetailScreen(user: peerUser),
      ),
    );
  }

  void _showTelegramMessageContextMenu(BuildContext context, MessageModel message) {
    HapticFeedback.mediumImpact();
    final isMe = message.senderId == PortalBackendService.instance.currentUser?.uid;
    final quickEmojis = ['👍', '❤️', '🔥', '😂', '😮', '😢', '👏', '🎉', '🚀', '💯', '💎', '🖤'];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ContextMenu',
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
                            final isSelected = message.reactions[myUid] == emoji;

                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
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
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _onReplyToMessage(message);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  const Icon(Icons.reply_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 14),
                                  Text('Ответить', style: GoogleFonts.inter(fontSize: 15, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 1),
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
                            onTap: () async {
                              Navigator.pop(ctx);
                              final track = MusicTrackModel(
                                id: message.id,
                                title: message.text.isNotEmpty ? message.text : 'Музыкальный трек',
                                artist: message.forwardedSenderName.isNotEmpty ? message.forwardedSenderName : 'Исполнитель',
                                audioUrl: message.mediaUrl.isNotEmpty ? message.mediaUrl : PortalMusicService.demoTracks[0].audioUrl,
                                durationSeconds: message.audioDuration > 0 ? message.audioDuration : 194,
                              );
                              await PortalMusicService.instance.addSongToProfile(track);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Песня добавлена в ваш профиль!'),
                                    backgroundColor: Color(0xFF3390EC),
                                  ),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  const Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 14),
                                  Text('Добавить в профиль', style: GoogleFonts.inter(fontSize: 15, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          InkWell(
                            onTap: () async {
                              Navigator.pop(ctx);
                              final track = MusicTrackModel(
                                id: message.id,
                                title: message.text.isNotEmpty ? message.text : 'Музыкальный трек',
                                artist: message.forwardedSenderName.isNotEmpty ? message.forwardedSenderName : 'Исполнитель',
                                audioUrl: message.mediaUrl.isNotEmpty ? message.mediaUrl : PortalMusicService.demoTracks[0].audioUrl,
                                durationSeconds: message.audioDuration > 0 ? message.audioDuration : 194,
                              );
                              await PortalMusicService.instance.addSongToMyMusic(track);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Трек добавлен в «Моя музыка»!'),
                                    backgroundColor: Color(0xFF3390EC),
                                  ),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  const Icon(Icons.library_music_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 14),
                                  Text('Добавить в музыку', style: GoogleFonts.inter(fontSize: 15, color: Colors.white)),
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
                                  Text(
                                    'Удалить',
                                    style: GoogleFonts.inter(fontSize: 15, color: Colors.redAccent, fontWeight: FontWeight.w600),
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
                    // 0. Background Wallpaper Layer
                    Positioned.fill(
                      child: Image.asset(
                        'lib/wallpaper/wallpaper.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.35),
                      ),
                    ),

                    // Main Chat Messages Stream Layer
                    Positioned.fill(
                      child: Column(

                        children: [
                          Expanded(
                            child: StreamBuilder<List<MessageModel>>(
                              stream: PortalBackendService.instance.getMessagesStream(widget.chat.chatId),
                              builder: (context, msgSnapshot) {
                                final messages = msgSnapshot.data ?? [];
                                _currentMessages = messages;
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
                                  padding: const EdgeInsets.fromLTRB(0, 76, 0, 80),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) {
                                    final msg = messages[index];
                                    final isMe = msg.senderId == PortalBackendService.instance.currentUser?.uid;
                                    final msgKey = _messageKeys.putIfAbsent(msg.id, () => GlobalKey());
                                    return KeyedSubtree(
                                      key: msgKey,
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

  void _initiateCall(UserModel peerUser) async {
    final call = await PortalBackendService.instance.startCall(receiver: peerUser);
    if (!mounted || call == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          call: call,
          isIncoming: false,
        ),
      ),
    );
  }

  // Floating Translucent Liquid Glass Top Bar Header with Soft Gradient Fade Edge
  Widget _buildTopBar(UserModel peerUser, String statusText, bool isPeerTyping) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [

              // 1. Left: Round Liquid Glass Back Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),

              // 2. Center: Rounded Capsule Liquid Glass Pill (Dynamic Width according to Nickname length)
              Flexible(
                fit: FlexFit.loose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () => _openPeerProfileDialog(peerUser),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.09),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white.withOpacity(0.16), width: 1),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  peerUser.name,
                                  style: PortalTheme.titleHeader(fontSize: 15, color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (peerUser.isVerified) buildVerifiedBadge(size: 15),
                            ],
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
                            Text(
                              statusText,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: peerUser.isOnline ? const Color(0xFF34C759) : Colors.white54,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),


              // 3. Right: Liquid Glass Call Button + Round Avatar
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Call Button
                  GestureDetector(
                    onTap: () => _initiateCall(peerUser),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.12),
                        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.phone_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Round Avatar
                  GestureDetector(
                    onTap: () => _openPeerProfileDialog(peerUser),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.22), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundImage: buildAvatarImageProvider(peerUser.avatarUrl),
                      ),
                    ),
                  ),
                ],
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

  Widget _buildReplyHeader(MessageModel msg) {
    if (msg.replyText.isEmpty && msg.replySenderName.isEmpty) return const SizedBox.shrink();

    final senderName = msg.replySenderName.isNotEmpty ? msg.replySenderName : 'Пользователь';
    final replyText = msg.replyText.isNotEmpty ? msg.replyText : 'Сообщение';

    return GestureDetector(
      onTap: () {
        if (msg.replyMessageId.isNotEmpty) {
          _scrollToAndHighlightMessage(msg.replyMessageId);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    senderName,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    replyText,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Message Bubble Dispatcher
  Widget _buildMessageBubble(MessageModel msg, bool isMe, UserModel peerUser) {
    Widget childWidget;

    if (msg.type == 'video_note') {
      childWidget = VideoNoteBubble(message: msg, isMe: isMe, peerUser: peerUser);
    } else if (msg.type == 'voice') {
      childWidget = VoiceMessageBubble(message: msg, isMe: isMe);
    } else if (msg.type == 'gift') {
      childWidget = GiftMessageBubble(message: msg, isMe: isMe, peerUser: peerUser);
    } else if (msg.type == 'audio' || msg.type == 'music') {
      childWidget = MusicMessageBubble(message: msg, isMe: isMe, peerUser: peerUser);
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
                if (msg.replyText.isNotEmpty) _buildReplyHeader(msg),
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
                  if (msg.replyText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _buildReplyHeader(msg),
                    ),
                  if (msg.forwardedSenderName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: _buildForwardHeader(msg.forwardedSenderName, msg.forwardedSenderAvatar),
                    ),
                  ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular((msg.forwardedSenderName.isNotEmpty || msg.replyText.isNotEmpty) ? 4 : 20),
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
        final hasHeader = msg.replyText.isNotEmpty || msg.forwardedSenderName.isNotEmpty;

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
                if (msg.replyText.isNotEmpty) _buildReplyHeader(msg),
                if (msg.forwardedSenderName.isNotEmpty)
                  _buildForwardHeader(msg.forwardedSenderName, msg.forwardedSenderAvatar),
                Row(
                  mainAxisSize: hasHeader ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: hasHeader ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
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

    final isHighlighted = msg.id == _highlightedMessageId;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFF3390EC).withOpacity(0.22) : Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Dismissible(
          key: ValueKey('reply_${msg.id}'),
          direction: DismissDirection.endToStart,
          dismissThresholds: const {DismissDirection.endToStart: 0.15},
          confirmDismiss: (direction) async {
            _onReplyToMessage(msg);
            return false;
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.reply_rounded, color: Colors.white, size: 22),
            ),
          ),
          child: GestureDetector(
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
          ),
        ),
      ),
    );
  }

  Widget _buildReplyInputBar() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final replyMsg = _replyingToMessage!;
    final replyAuthorName = replyMsg.senderId == PortalBackendService.instance.currentUser?.uid
        ? (PortalBackendService.instance.currentUser?.name ?? 'Вы')
        : widget.peerUser.name;
    final previewText = _getReplyPreviewText(replyMsg);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E).withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF7C66DC),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'В ответ $replyAuthorName',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF7C66DC),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cancelReply,
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
            ),
          ),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingToMessage != null) _buildReplyInputBar(),
              Row(
                children: [
              // Photo Attachment Button
              GestureDetector(
                onTap: _showAttachmentMenu,
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
              Listener(
                onPointerDown: (event) {
                  _isPointerDown = true;
                  _hasTriggeredHold = false;
                  _touchDownTime = DateTime.now();
                  _touchDownPosition = event.position;

                  if (hasText) {
                    _sendMessage();
                  } else {
                    _holdTimer?.cancel();
                    _holdTimer = Timer(const Duration(milliseconds: 200), () {
                      if (_isPointerDown && mounted) {
                        _hasTriggeredHold = true;
                        _recButtonAnimController.forward();
                        HapticFeedback.lightImpact();
                        if (!_isCameraMode) {
                          _isHoldingRecord = true;
                          _startRecording(isVideo: false);
                        } else {
                          _startRecording(isVideo: true);
                        }
                      }
                    });
                  }
                },
                onPointerMove: (event) {
                  if (!hasText && _hasTriggeredHold && _isHoldingRecord && _isRecording) {
                    final dx = event.position.dx - _touchDownPosition.dx;
                    setState(() {
                      _dragOffsetX = dx.clamp(-160.0, 0.0);
                    });
                    if (_dragOffsetX < -80) {
                      _cancelRecording();
                      _isHoldingRecord = false;
                    }
                  }
                },
                onPointerUp: (event) {
                  _isPointerDown = false;
                  _holdTimer?.cancel();
                  _recButtonAnimController.reverse();

                  if (hasText) return;

                  if (_hasTriggeredHold || _isHoldingRecord || _isRecording) {
                    _isHoldingRecord = false;
                    _hasTriggeredHold = false;
                    if (_isRecording) {
                      if (_dragOffsetX < -80) {
                        _cancelRecording();
                      } else {
                        _finishAndSendRecording();
                      }
                    }
                  } else {
                    // Quick tap (<200ms): toggle mode between Mic (Voice) and Camera (Video Note)
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isCameraMode = !_isCameraMode;
                    });
                  }
                },
                onPointerCancel: (_) {
                  _isPointerDown = false;
                  _holdTimer?.cancel();
                  _recButtonAnimController.reverse();
                  if ((_hasTriggeredHold || _isHoldingRecord) && _isRecording) {
                    _isHoldingRecord = false;
                    _hasTriggeredHold = false;
                    _finishAndSendRecording();
                  }
                },
                child: ScaleTransition(
                  scale: _recButtonScaleAnim,
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
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);
}
}

/// Telegram-style Glass Gift Message Bubble Card
class GiftMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final UserModel peerUser;

  const GiftMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.peerUser,
  });

  void _showGiftModal(BuildContext context) {
    final senderName = isMe
        ? (PortalBackendService.instance.currentUser?.name ?? 'Вы')
        : (message.forwardedSenderName.isNotEmpty ? message.forwardedSenderName : peerUser.name);

    final senderAvatar = isMe
        ? (PortalBackendService.instance.currentUser?.avatarUrl ?? '')
        : (message.forwardedSenderAvatar.isNotEmpty ? message.forwardedSenderAvatar : peerUser.avatarUrl);

    final formattedDate = DateFormat('dd.MM.yyyy в HH:mm').format(message.timestamp);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
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

              // Gift Graphic/Icon
              _buildGiftGraphic(message.imageUrl, size: 100),
              const SizedBox(height: 14),

              Text(
                'Подарок от $senderName',
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
                            backgroundImage: senderAvatar.isNotEmpty
                                ? buildAvatarImageProvider(senderAvatar)
                                : null,
                            child: senderAvatar.isEmpty
                                ? Text(
                                    senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            senderName,
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
                    if (message.text.isNotEmpty) ...[
                      Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Подпись', style: GoogleFonts.inter(color: Colors.white60, fontSize: 14)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                message.text,
                                textAlign: TextAlign.right,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3390EC),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Center(
                    child: Text(
                      'Закрыть',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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

  static Widget _buildGiftGraphic(String iconUrl, {double size = 90}) {
    if (iconUrl.startsWith('http')) {
      return Image.network(
        iconUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Text('🎁', style: TextStyle(fontSize: size * 0.7)),
      );
    }
    if (iconUrl.startsWith('assets/') || iconUrl.contains('.') || iconUrl.contains('/')) {
      return Image.asset(
        iconUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Text('🎁', style: TextStyle(fontSize: size * 0.7)),
      );
    }
    final giftIcons = {
      'rose': '🌹',
      'star': '⭐️',
      'diamond': '💎',
      'rocket': '🚀',
      'crown': '👑',
      'gift': '🎁',
      'cake': '🎂',
      'heart': '💖',
      'trophy': '🏆',
      'fire': '🔥',
      'mask': '🎭',
    };
    final emoji = giftIcons[iconUrl.toLowerCase()] ?? (iconUrl.isNotEmpty && iconUrl.length <= 4 ? iconUrl : '🎁');
    return Text(emoji, style: TextStyle(fontSize: size * 0.7));
  }

  @override
  Widget build(BuildContext context) {
    final senderName = isMe
        ? (PortalBackendService.instance.currentUser?.name ?? 'Вы')
        : (message.forwardedSenderName.isNotEmpty ? message.forwardedSenderName : peerUser.name);

    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () => _showGiftModal(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          width: 250,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF5A7840).withOpacity(0.85),
                      const Color(0xFF7B9B49).withOpacity(0.85),
                      const Color(0xFF90AC4C).withOpacity(0.80),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.30),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Center Gift Icon
                    _buildGiftGraphic(message.imageUrl, size: 105),
                    const SizedBox(height: 14),

                    // Title: "Подарок от {Имя}"
                    Text(
                      'Подарок от $senderName',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),

                    // Subtitle Note left by sender
                    if (message.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        message.text,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.92),
                          height: 1.3,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Rounded Pill Button: "Посмотреть"
                    GestureDetector(
                      onTap: () => _showGiftModal(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Посмотреть',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
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
  }
}

/// Music Message Bubble Card for Chats & Channels
class MusicMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final UserModel peerUser;

  const MusicMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.peerUser,
  });

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '3:14';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final musicService = PortalMusicService.instance;
    final track = MusicTrackModel(
      id: message.id,
      title: message.text.isNotEmpty ? message.text : 'all girls are the same',
      artist: message.forwardedSenderName.isNotEmpty ? message.forwardedSenderName : 'juice wrld',
      audioUrl: message.mediaUrl.isNotEmpty ? message.mediaUrl : PortalMusicService.demoTracks[0].audioUrl,
      durationSeconds: message.audioDuration > 0 ? message.audioDuration : 194,
    );

    return ListenableBuilder(
      listenable: musicService,
      builder: (context, _) {
        final isPlaying = musicService.isPlaying && musicService.currentTrack?.id == message.id;

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {
              MusicPlayerModalSheet.show(
                context,
                track: track,
                targetUser: peerUser,
                isOwnProfile: isMe,
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              constraints: const BoxConstraints(maxWidth: 275),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF6B55D3) : const Color(0xFF1D2333),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 20),
                ),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Circular Play / Pause Button
                  GestureDetector(
                    onTap: () {
                      musicService.togglePlayPause(track);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF3390EC),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Track Info (Title, Artist, Duration)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              track.artist,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Spacer(),
                            Text(
                              _formatDuration(track.durationSeconds),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
