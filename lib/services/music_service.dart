import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';
import '../models/portal_models.dart';

/// Representation of a Music Track in Portal Messenger
class MusicTrackModel {
  final String id;
  final String title;
  final String artist;
  final String audioUrl;
  final int durationSeconds;
  final String coverUrl;

  MusicTrackModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.audioUrl,
    required this.durationSeconds,
    this.coverUrl = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'audioUrl': audioUrl,
      'durationSeconds': durationSeconds,
      'coverUrl': coverUrl,
    };
  }

  factory MusicTrackModel.fromMap(Map<String, dynamic> map) {
    return MusicTrackModel(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Неизвестный трек',
      artist: map['artist'] ?? 'Неизвестный исполнитель',
      audioUrl: map['audioUrl'] ?? '',
      durationSeconds: map['durationSeconds'] ?? 0,
      coverUrl: map['coverUrl'] ?? '',
    );
  }
}

/// Singleton Service for Audio Playback and Music Library Management
class PortalMusicService extends ChangeNotifier {
  static final PortalMusicService instance = PortalMusicService._internal();
  PortalMusicService._internal() {
    _init();
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  MusicTrackModel? _currentTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isMusicSectionEnabled = true;

  // Preloaded High-Quality Demo Tracks for testing and immediate enjoyment!
  static final List<MusicTrackModel> demoTracks = [
    MusicTrackModel(
      id: 'demo_1',
      title: 'all girls are the same',
      artist: 'juice wrld',
      audioUrl: 'https://cdn.pixabay.com/download/audio/2022/05/27/audio_1808fbf07a.mp3?filename=lofi-study-112191.mp3',
      durationSeconds: 194,
    ),
    MusicTrackModel(
      id: 'demo_2',
      title: 'FE!N',
      artist: 'Travis Scott ft. Playboi Carti',
      audioUrl: 'https://cdn.pixabay.com/download/audio/2022/03/15/audio_c8c8a73467.mp3?filename=beat-hip-hop-10777.mp3',
      durationSeconds: 215,
    ),
    MusicTrackModel(
      id: 'demo_3',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      audioUrl: 'https://cdn.pixabay.com/download/audio/2022/01/18/audio_d0a13f69d2.mp3?filename=synthwave-80s-9685.mp3',
      durationSeconds: 200,
    ),
    MusicTrackModel(
      id: 'demo_4',
      title: 'Starboy',
      artist: 'The Weeknd',
      audioUrl: 'https://cdn.pixabay.com/download/audio/2022/10/14/audio_9939f7922f.mp3?filename=pop-summer-125026.mp3',
      durationSeconds: 230,
    ),
  ];

  MusicTrackModel? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isMusicSectionEnabled => _isMusicSectionEnabled;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _isMusicSectionEnabled = prefs.getBool('music_section_enabled') ?? true;

    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      notifyListeners();
    });
  }

  Future<void> setMusicSectionEnabled(bool enabled) async {
    _isMusicSectionEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('music_section_enabled', enabled);
    notifyListeners();
  }

  Future<void> playTrack(MusicTrackModel track) async {
    if (_currentTrack?.id == track.id && _audioPlayer.state == PlayerState.paused) {
      await _audioPlayer.resume();
      _isPlaying = true;
      notifyListeners();
      return;
    }

    _currentTrack = track;
    _position = Duration.zero;
    _duration = Duration(seconds: track.durationSeconds);
    notifyListeners();

    try {
      await _audioPlayer.stop();
      if (track.audioUrl.startsWith('http')) {
        await _audioPlayer.play(UrlSource(track.audioUrl));
      } else if (track.audioUrl.startsWith('assets/')) {
        await _audioPlayer.play(AssetSource(track.audioUrl));
      } else {
        await _audioPlayer.play(DeviceFileSource(track.audioUrl));
      }
      _isPlaying = true;
    } catch (e) {
      debugPrint('playTrack error: $e');
      _isPlaying = false;
    }
    notifyListeners();
  }

  Future<void> pauseTrack() async {
    await _audioPlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> resumeTrack() async {
    if (_currentTrack != null) {
      await _audioPlayer.resume();
      _isPlaying = true;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause(MusicTrackModel track) async {
    if (_currentTrack?.id == track.id && _isPlaying) {
      await pauseTrack();
    } else {
      await playTrack(track);
    }
  }

  Future<void> seek(Duration pos) async {
    await _audioPlayer.seek(pos);
    _position = pos;
    notifyListeners();
  }

  /// Add track to current user profile
  Future<bool> addSongToProfile(MusicTrackModel track) async {
    final user = PortalBackendService.instance.currentUser;
    if (user == null) return false;

    try {
      final songTitle = '${track.artist} - ${track.title}';
      await PortalBackendService.instance.updateProfileSong(
        profileSongTitle: songTitle,
        profileSongArtist: track.artist,
        profileSongUrl: track.audioUrl,
        profileSongDuration: track.durationSeconds,
      );

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('addSongToProfile error: $e');
      return false;
    }
  }

  /// Remove song from profile
  Future<bool> removeSongFromProfile() async {
    final user = PortalBackendService.instance.currentUser;
    if (user == null) return false;

    try {
      await PortalBackendService.instance.updateProfileSong(
        profileSongTitle: '',
        profileSongArtist: '',
        profileSongUrl: '',
        profileSongDuration: 0,
      );

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('removeSongFromProfile error: $e');
      return false;
    }
  }

  /// Add track to "My Music" section
  Future<bool> addSongToMyMusic(MusicTrackModel track) async {
    final user = PortalBackendService.instance.currentUser;
    if (user == null) return false;

    final existing = List<Map<String, dynamic>>.from(user.savedMusicTracks);
    if (!existing.any((t) => t['id'] == track.id || t['title'] == track.title)) {
      existing.add(track.toMap());
      await PortalBackendService.instance.updateSavedMusicTracks(existing);
      notifyListeners();
    }
    return true;
  }

  /// Remove track from "My Music" section
  Future<bool> removeSongFromMyMusic(String trackId) async {
    final user = PortalBackendService.instance.currentUser;
    if (user == null) return false;

    final existing = List<Map<String, dynamic>>.from(user.savedMusicTracks);
    existing.removeWhere((t) => t['id'] == trackId || t['title'] == trackId);

    await PortalBackendService.instance.updateSavedMusicTracks(existing);
    notifyListeners();
    return true;
  }
}
