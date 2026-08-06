import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';

/// Helper to render image memory or network provider
ImageProvider buildCallAvatarProvider(String url) {
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

/// Fullscreen Modern Telegram Liquid Glass Call Screen
class CallScreen extends StatefulWidget {
  final CallModel call;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.call,
    required this.isIncoming,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  StreamSubscription<CallModel?>? _callStateSubscription;
  StreamSubscription<String>? _audioChunkSubscription;
  Timer? _durationTimer;

  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isAccepted = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isRecordingLoopActive = false;
  int _durationSeconds = 0;

  @override
  void initState() {
    super.initState();
    _requestMicrophonePermission();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.call.status == 'accepted') {
      _onCallAccepted();
    }

    _listenToCallState();
  }

  Future<void> _requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        debugPrint('Microphone permission not granted');
      }
    } catch (_) {}
  }

  void _listenToCallState() {
    _callStateSubscription = PortalBackendService.instance
        .listenToCallState(widget.call.callId)
        .listen((callData) {
      if (callData == null) return;

      if (callData.status == 'accepted' && !_isAccepted) {
        _onCallAccepted();
      } else if (callData.status == 'ended' || callData.status == 'rejected') {
        _closeCallScreen();
      }
    });
  }

  void _onCallAccepted() {
    if (!mounted) return;
    setState(() {
      _isAccepted = true;
    });

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _durationSeconds++;
        });
      }
    });

    _startAudioStreamEngine();
  }

  final AudioPlayer _callAudioPlayer = AudioPlayer();
  final List<Uint8List> _incomingAudioQueue = [];
  bool _isQueueProcessing = false;
  StreamSubscription<void>? _playerCompleteSub;

  void _startAudioStreamEngine() {
    final currentUid = PortalBackendService.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    // Listen for player completion to automatically trigger next audio chunk in queue
    _playerCompleteSub?.cancel();
    _playerCompleteSub = _callAudioPlayer.onPlayerComplete.listen((_) {
      _processNextAudioInQueue();
    });

    // 1. Listen to incoming audio voice chunks from peer and push into Queue
    _audioChunkSubscription?.cancel();
    _audioChunkSubscription = PortalBackendService.instance
        .listenToCallAudioChunks(widget.call.callId, currentUid)
        .listen((base64Chunk) {
      if (!_isSpeakerOn || base64Chunk.isEmpty) return;

      try {
        final bytes = base64Decode(base64Chunk);
        if (bytes.isNotEmpty) {
          _incomingAudioQueue.add(bytes);
          if (!_isQueueProcessing) {
            _processNextAudioInQueue();
          }
        }
      } catch (e) {
        debugPrint('Error decoding audio chunk: $e');
      }
    });

    // 2. Start continuous audio recording loop for current user
    if (!_isRecordingLoopActive) {
      _isRecordingLoopActive = true;
      _runAudioRecordLoop();
    }
  }

  Future<void> _processNextAudioInQueue() async {
    if (!mounted || _incomingAudioQueue.isEmpty || !_isSpeakerOn) {
      _isQueueProcessing = false;
      return;
    }

    _isQueueProcessing = true;
    final bytes = _incomingAudioQueue.removeAt(0);

    try {
      await _callAudioPlayer.play(BytesSource(bytes));
    } catch (e) {
      debugPrint('Error playing queued audio: $e');
      _processNextAudioInQueue();
    }
  }

  Future<void> _runAudioRecordLoop() async {
    while (mounted && _isAccepted && _isRecordingLoopActive) {
      if (_isMuted) {
        await Future.delayed(const Duration(milliseconds: 400));
        continue;
      }

      try {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/call_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        final hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 24000,
            sampleRate: 22050,
            numChannels: 1,
          ),
          path: filePath,
        );

        await Future.delayed(const Duration(milliseconds: 1800));

        final recordedPath = await _audioRecorder.stop();
        if (recordedPath != null && File(recordedPath).existsSync()) {
          final file = File(recordedPath);
          final bytes = await file.readAsBytes();
          await file.delete();

          if (bytes.isNotEmpty && !_isMuted && _isAccepted) {
            final base64Data = base64Encode(bytes);
            await PortalBackendService.instance.sendCallAudioChunk(
              callId: widget.call.callId,
              base64Data: base64Data,
            );
          }
        }
      } catch (e) {
        debugPrint('Call audio record error: $e');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }


  void _acceptCall() async {
    await PortalBackendService.instance.acceptCall(widget.call.callId);
    _onCallAccepted();
  }

  void _endCall() async {
    await PortalBackendService.instance.endCall(widget.call.callId);
    _closeCallScreen();
  }

  void _closeCallScreen() {
    _isRecordingLoopActive = false;
    _audioChunkSubscription?.cancel();
    _playerCompleteSub?.cancel();
    _durationTimer?.cancel();
    _callStateSubscription?.cancel();
    _audioRecorder.dispose();
    _callAudioPlayer.dispose();
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }



  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
  }


  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callStateSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = PortalBackendService.instance.currentUser;
    final isMeCaller = widget.call.callerId == currentUser?.uid;

    final peerName = isMeCaller ? widget.call.receiverName : widget.call.callerName;
    final peerAvatar = isMeCaller ? widget.call.receiverAvatar : widget.call.callerAvatar;
    final avatarProvider = buildCallAvatarProvider(peerAvatar);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Blurred Avatar Wallpaper Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: avatarProvider,
                  fit: BoxFit.cover,
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: Colors.black.withOpacity(0.75),
                ),
              ),
            ),
          ),

          // 2. Main Call Content Area
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Centered Pulsing Large Avatar
                Center(
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      final scale = _isAccepted ? 1.0 : _pulseAnimation.value;
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 140,
                          height: 140,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isAccepted
                                  ? const Color(0xFF3390EC).withOpacity(0.6)
                                  : Colors.white.withOpacity(0.25),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isAccepted ? const Color(0xFF3390EC) : Colors.white)
                                    .withOpacity(0.25),
                                blurRadius: 30,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 65,
                            backgroundColor: Colors.white10,
                            backgroundImage: avatarProvider,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // Contact Name
                Text(
                  peerName.isNotEmpty ? peerName : 'Собеседник',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // Call Status Subtitle
                if (_isAccepted)
                  Text(
                    _formatDuration(_durationSeconds),
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF34C759),
                    ),
                  )
                else if (widget.isIncoming)
                  Text(
                    'Входящий звонок',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF3390EC),
                    ),
                  )
                else
                  Text(
                    'Звонок...',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    ),
                  ),

                const Spacer(),

                // 3. Liquid Glass Bottom Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                  child: (_isAccepted || !widget.isIncoming)
                      ? _buildConnectedCallControls()
                      : _buildIncomingCallControls(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Active or Outgoing Call Control Buttons (Speaker, Mic, End)
  Widget _buildConnectedCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Loudspeaker Button (Liquid Glass)
        _buildLiquidControlButton(
          icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          label: 'Громкая',
          isActive: _isSpeakerOn,
          onTap: _toggleSpeaker,
        ),

        // Microphone Mute Button (Liquid Glass)
        _buildLiquidControlButton(
          icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _isMuted ? 'Выкл' : 'Микрофон',
          isActive: !_isMuted,
          isMuted: _isMuted,
          onTap: _toggleMute,
        ),

        // End Call Red Button
        _buildLiquidControlButton(
          icon: Icons.call_end_rounded,
          label: 'Сбросить',
          isEndCall: true,
          onTap: _endCall,
        ),
      ],
    );
  }

  /// Incoming Call Control Buttons (Reject, Answer)
  Widget _buildIncomingCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Reject Call (Red Button)
        _buildLiquidControlButton(
          icon: Icons.call_end_rounded,
          label: 'Сбросить',
          isEndCall: true,
          onTap: _endCall,
        ),

        // Answer Call (Green Button)
        _buildLiquidControlButton(
          icon: Icons.call_rounded,
          label: 'Ответить',
          isAnswer: true,
          onTap: _acceptCall,
        ),
      ],
    );
  }

  Widget _buildLiquidControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool isMuted = false,
    bool isEndCall = false,
    bool isAnswer = false,
  }) {
    Color containerColor;
    Color iconColor = Colors.white;

    if (isEndCall) {
      containerColor = const Color(0xFFFF3B30);
    } else if (isAnswer) {
      containerColor = const Color(0xFF34C759);
    } else if (isMuted) {
      containerColor = Colors.redAccent.withOpacity(0.35);
    } else if (isActive) {
      containerColor = Colors.white.withOpacity(0.25);
    } else {
      containerColor = Colors.white.withOpacity(0.10);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: containerColor,
              border: Border.all(
                color: isEndCall || isAnswer
                    ? Colors.white.withOpacity(0.3)
                    : Colors.white.withOpacity(0.2),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isEndCall
                      ? const Color(0xFFFF3B30).withOpacity(0.4)
                      : (isAnswer
                          ? const Color(0xFF34C759).withOpacity(0.4)
                          : Colors.black.withOpacity(0.3)),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
