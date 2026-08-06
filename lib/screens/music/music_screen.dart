import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/portal_models.dart';
import '../../services/firebase_service.dart';
import '../../services/music_service.dart';
import '../../widgets/music_player_modal.dart';

/// 1:1 Telegram iOS Style Music Section Screen ("Музыка")
class MusicSectionScreen extends StatefulWidget {
  const MusicSectionScreen({super.key});

  @override
  State<MusicSectionScreen> createState() => _MusicSectionScreenState();
}

class _MusicSectionScreenState extends State<MusicSectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showTrackMenu(BuildContext context, MusicTrackModel track, UserModel user) {
    final musicService = PortalMusicService.instance;
    final isPlaying = musicService.isPlaying && musicService.currentTrack?.id == track.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle bar
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Track Info Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3390EC).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Color(0xFF3390EC), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              track.artist,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF8E8E93),
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

                const Divider(color: Colors.white10, height: 24),

                // Option 1: Play / Pause
                ListTile(
                  leading: Icon(
                    isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                    color: const Color(0xFF3390EC),
                    size: 26,
                  ),
                  title: Text(
                    isPlaying ? 'Пауза' : 'Воспроизвести',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    musicService.togglePlayPause(track);
                  },
                ),

                // Option 2: Add to Profile
                ListTile(
                  leading: const Icon(Icons.person_pin_rounded, color: Colors.white70, size: 24),
                  title: Text(
                    'Поставить в статус профиля',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final success = await musicService.addSongToProfile(track);
                    if (mounted && success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Песня "${track.title}" добавлена в ваш профиль!'),
                          backgroundColor: const Color(0xFF3390EC),
                        ),
                      );
                    }
                  },
                ),

                // Option 3: Delete from My Music
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF3B30), size: 24),
                  title: Text(
                    'Удалить из медиатеки',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: const Color(0xFFFF3B30)),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await musicService.removeSongFromMyMusic(track.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicService = PortalMusicService.instance;

    return ListenableBuilder(
      listenable: PortalBackendService.instance,
      builder: (context, _) {
        final currentUser = PortalBackendService.instance.currentUser;
        final rawTracks = (currentUser?.savedMusicTracks ?? [])
            .map((m) => MusicTrackModel.fromMap(m))
            .toList();

        final filteredTracks = rawTracks.where((t) {
          if (_searchQuery.isEmpty) return true;
          final query = _searchQuery.toLowerCase();
          return t.title.toLowerCase().contains(query) ||
              t.artist.toLowerCase().contains(query);
        }).toList();

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF007AFF), size: 20),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
            ),
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: GoogleFonts.inter(fontSize: 16, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Поиск музыки',
                      hintStyle: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF8E8E93)),
                      border: InputBorder.none,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  )
                : Text(
                    'Музыка',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
            actions: [
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close_rounded : Icons.search_rounded,
                  color: const Color(0xFF007AFF),
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    if (_isSearching) {
                      _isSearching = false;
                      _searchQuery = '';
                      _searchController.clear();
                    } else {
                      _isSearching = true;
                    }
                  });
                },
              ),
            ],
          ),
          body: ListenableBuilder(
            listenable: musicService,
            builder: (context, _) {
              if (rawTracks.isEmpty) {
                // Telegram iOS Empty State
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: Color(0xFF3390EC),
                            size: 42,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Нет музыки',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Отправленные и сохраненные аудиофайлы появятся здесь.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF8E8E93),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (filteredTracks.isEmpty) {
                return Center(
                  child: Text(
                    'Ничего не найдено',
                    style: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF8E8E93)),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filteredTracks.length,
                separatorBuilder: (context, index) => const Padding(
                  padding: EdgeInsets.only(left: 72),
                  child: Divider(color: Color(0xFF1C1C1E), height: 1),
                ),
                itemBuilder: (context, index) {
                  final track = filteredTracks[index];
                  final isPlaying = musicService.isPlaying && musicService.currentTrack?.id == track.id;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        musicService.togglePlayPause(track);
                      },
                      onLongPress: () {
                        if (currentUser != null) {
                          _showTrackMenu(context, track, currentUser);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            // Cover Artwork with Play/Pause button in 1:1 Telegram iOS Style
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isPlaying
                                    ? const Color(0xFF3390EC)
                                    : const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: isPlaying ? Colors.white : const Color(0xFF3390EC),
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Song Title & Artist info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
                                      color: isPlaying ? const Color(0xFF3390EC) : Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${track.artist} • ${_formatDuration(track.durationSeconds)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: const Color(0xFF8E8E93),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),

                            // Telegram iOS 3-dots Context Menu Button
                            IconButton(
                              icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF8E8E93), size: 22),
                              onPressed: () {
                                if (currentUser != null) {
                                  _showTrackMenu(context, track, currentUser);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
