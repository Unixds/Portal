import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/portal_models.dart';
import '../services/music_service.dart';

/// Interactive Music Player Modal Sheet matching the Telegram/Apple Music aesthetics.
class MusicPlayerModalSheet extends StatefulWidget {
  final MusicTrackModel track;
  final UserModel targetUser;
  final bool isOwnProfile;

  const MusicPlayerModalSheet({
    super.key,
    required this.track,
    required this.targetUser,
    required this.isOwnProfile,
  });

  static void show(BuildContext context, {
    required MusicTrackModel track,
    required UserModel targetUser,
    required bool isOwnProfile,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => MusicPlayerModalSheet(
        track: track,
        targetUser: targetUser,
        isOwnProfile: isOwnProfile,
      ),
    );
  }

  @override
  State<MusicPlayerModalSheet> createState() => _MusicPlayerModalSheetState();
}

class _MusicPlayerModalSheetState extends State<MusicPlayerModalSheet> {
  bool _isShuffle = false;
  bool _isRepeat = false;

  @override
  void initState() {
    super.initState();
    // Auto-start audio if not playing this track
    final musicService = PortalMusicService.instance;
    if (musicService.currentTrack?.id != widget.track.id || !musicService.isPlaying) {
      musicService.playTrack(widget.track);
    }
  }

  String _formatDuration(Duration dur) {
    final minutes = dur.inMinutes.remainder(60).toString();
    final seconds = dur.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final musicService = PortalMusicService.instance;

    return ListenableBuilder(
      listenable: musicService,
      builder: (context, _) {
        final isPlaying = musicService.isPlaying && musicService.currentTrack?.id == widget.track.id;
        final position = musicService.position;
        final duration = musicService.duration.inSeconds > 0
            ? musicService.duration
            : Duration(seconds: widget.track.durationSeconds);

        final currentPosSec = position.inSeconds.toDouble();
        final maxDurSec = duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Bar Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Header: [X] - Playlist Title - [+]
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close Button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ),

                  // Center Title: "Плейлист {Имя}" or "Ваш плейлист"
                  Flexible(
                    child: Text(
                      widget.isOwnProfile ? 'Ваш плейлист' : 'Плейлист ${widget.targetUser.name}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Right Plus / Share Button
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Track Cover + Title + Share Row
              Row(
                children: [
                  // Album Cover Box
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8E2DE2).withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.music_note_rounded, color: Colors.white, size: 22),
                          Text(
                            'MUSIC',
                            style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Track Title & Artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.track.artist} - ${widget.track.title}',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.track.artist,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white60,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  const Icon(Icons.ios_share_rounded, color: Colors.white70, size: 22),
                ],
              ),

              const SizedBox(height: 24),

              // Slider / Progress Timeline Bar
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: currentPosSec.clamp(0.0, maxDurSec),
                  min: 0.0,
                  max: maxDurSec,
                  onChanged: (val) {
                    musicService.seek(Duration(seconds: val.toInt()));
                  },
                ),
              ),

              // Elapsed & Remaining Time Labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Playback Controls Row: [Shuffle] [Prev] [Play/Pause] [Next] [Repeat]
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(Icons.shuffle_rounded, color: _isShuffle ? const Color(0xFF3390EC) : Colors.white54, size: 24),
                    onPressed: () => setState(() => _isShuffle = !_isShuffle),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                    onPressed: () {},
                  ),
                  GestureDetector(
                    onTap: () {
                      musicService.togglePlayPause(widget.track);
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 38,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: Icon(Icons.repeat_rounded, color: _isRepeat ? const Color(0xFF3390EC) : Colors.white54, size: 24),
                    onPressed: () => setState(() => _isRepeat = !_isRepeat),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Bottom Action Button:
              // Own Profile -> "Удалить из профиля"
              // Other User's Profile -> "🎵 Добавить в профиль"
              if (widget.isOwnProfile)
                GestureDetector(
                  onTap: () async {
                    await PortalMusicService.instance.removeSongFromProfile();
                    if (mounted) Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Center(
                      child: Text(
                        'Удалить из профиля',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: () async {
                    await PortalMusicService.instance.addSongToProfile(widget.track);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Песня добавлена в ваш профиль!'),
                          backgroundColor: Color(0xFF3390EC),
                        ),
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3390EC),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3390EC).withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Добавить в профиль',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
