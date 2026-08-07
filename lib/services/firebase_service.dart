import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/portal_models.dart';

/// Firebase & Real-time Messaging Service for Portal Messenger.
/// Fully handles user registration, multi-account sessions, profile updates,
/// username availability checks, user search, presence status, typing indicators, read receipts, voice messages, circular video notes, and forwarded messages.
class PortalBackendService extends ChangeNotifier {
  static final PortalBackendService instance = PortalBackendService._internal();
  factory PortalBackendService() => instance;
  PortalBackendService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  // Active logged-in accounts list
  final List<UserModel> _activeAccounts = [];
  List<UserModel> get activeAccounts => List.unmodifiable(_activeAccounts);

  // Local user cache
  final Map<String, UserModel> _userCache = {};
  final List<ChatModel> _localChats = [];
  final Map<String, List<MessageModel>> _localMessages = {};
  final Map<String, StreamController<List<MessageModel>>> _messageStreamControllers = {};
  final Map<String, List<UserGiftModel>> _localUserGifts = {};

  /// Initialize persistent user session on app launch
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUid = prefs.getString('portal_saved_uid');
      if (savedUid != null && savedUid.isNotEmpty) {
        final user = await getUserProfile(savedUid);
        if (user != null) {
          _currentUser = user;
          _userCache[user.uid] = user;
          if (!_activeAccounts.any((a) => a.uid == user.uid)) {
            _activeAccounts.add(user);
          }
          await updateUserPresence(true);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('PortalBackendService init error: $e');
    }
  }

  Future<void> _saveUserSession(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('portal_saved_uid', uid);
    } catch (_) {}
  }

  /// Sign out current user and clear saved session
  Future<void> signOut() async {
    if (_currentUser != null) {
      await updateUserPresence(false);
    }
    _currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('portal_saved_uid');
    } catch (_) {}
    notifyListeners();
  }

  /// Switch active logged-in user account
  void switchAccount(UserModel account) {
    if (_currentUser?.uid == account.uid) return;
    updateUserPresence(false);
    _currentUser = account;
    _localChats.clear();
    updateUserPresence(true);
    notifyListeners();
  }

  /// Update online presence status in Firestore
  Future<void> updateUserPresence(bool isOnline) async {
    if (_currentUser == null) return;
    final now = DateTime.now();

    try {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'isOnline': isOnline,
        'lastSeen': now.toIso8601String(),
      });
    } catch (_) {}

    _currentUser = UserModel(
      uid: _currentUser!.uid,
      phone: _currentUser!.phone,
      username: _currentUser!.username,
      name: _currentUser!.name,
      avatarUrl: _currentUser!.avatarUrl,
      bio: _currentUser!.bio,
      password: _currentUser!.password,
      isOnline: isOnline,
      lastSeen: now,
    );
  }

  /// Set typing status in a chat room
  Future<void> setTypingStatus(String chatId, bool isTyping) async {
    if (_currentUser == null || chatId.isEmpty) return;
    try {
      await _firestore.collection('chats').doc(chatId).collection('typing').doc(_currentUser!.uid).set({
        'isTyping': isTyping,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Listen to peer user typing status in a chat
  Stream<bool> getTypingStatusStream(String chatId, String peerUid) {
    if (chatId.isEmpty || peerUid.isEmpty) return Stream.value(false);
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(peerUid)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final isTyping = snapshot.data()!['isTyping'] ?? false;
        final updatedAtStr = snapshot.data()!['updatedAt'];
        if (updatedAtStr != null) {
          final updatedAt = DateTime.tryParse(updatedAtStr);
          if (updatedAt != null && DateTime.now().difference(updatedAt).inSeconds > 6) {
            return false;
          }
        }
        return isTyping;
      }
      return false;
    });
  }

  /// Get list of active local chats
  List<ChatModel> get chats => List.unmodifiable(_localChats);

  /// Mark all unread messages from peer as read in a chat
  Future<void> markMessagesAsRead(String chatId, String peerUid) async {
    if (_currentUser == null || chatId.isEmpty) return;

    try {
      final snapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isEqualTo: peerUid)
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.update({'isRead': true});
      }
    } catch (_) {}
  }

  /// Check if username is available (case-insensitive)
  Future<bool> isUsernameAvailable(String username) async {
    final cleanUsername = username.toLowerCase().replaceAll('@', '').trim();
    if (cleanUsername.length < 3) return false;

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: cleanUsername)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final existingUserDoc = snapshot.docs.first;
        if (_currentUser != null && existingUserDoc.id == _currentUser!.uid) {
          return true;
        }
        return false;
      }
    } catch (_) {}

    return !_userCache.values.any((u) => u.username == cleanUsername && u.uid != _currentUser?.uid);
  }

  /// Complete Registration Flow
  Future<UserModel> registerUser({
    required String phone,
    String email = '',
    required String password,
    required String username,
    required String name,
    String avatarUrl = '',
    String bio = '',
  }) async {
    final cleanUsername = username.toLowerCase().replaceAll('@', '').trim();
    final uid = 'usr_${DateTime.now().millisecondsSinceEpoch}';

    final newUser = UserModel(
      uid: uid,
      phone: phone,
      email: email,
      password: password,
      username: cleanUsername,
      name: name,
      avatarUrl: avatarUrl.isEmpty
          ? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80'
          : avatarUrl,
      bio: bio,
      isOnline: true,
      lastSeen: DateTime.now(),
    );

    try {
      await _firestore.collection('users').doc(uid).set(newUser.toMap());
    } catch (e) {
      debugPrint('Firestore registerUser error: $e');
    }

    _userCache[uid] = newUser;
    _currentUser = newUser;
    if (!_activeAccounts.any((a) => a.uid == uid)) {
      _activeAccounts.add(newUser);
    }

    _saveUserSession(uid);
    notifyListeners();
    return newUser;
  }

  /// Login with Username and Cloud Password
  Future<UserModel?> loginWithUsernameAndPassword({
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.toLowerCase().replaceAll('@', '').trim();
    if (cleanUsername.isEmpty || password.isEmpty) return null;

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: cleanUsername)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final user = UserModel.fromMap(doc.data(), doc.id);
        if (user.password == password) {
          _currentUser = user;
          _userCache[user.uid] = user;
          if (!_activeAccounts.any((a) => a.uid == user.uid)) {
            _activeAccounts.add(user);
          }
          _saveUserSession(user.uid);
          updateUserPresence(true);
          notifyListeners();
          return user;
        }
      }
    } catch (e) {
      debugPrint('loginWithUsernameAndPassword error: $e');
    }

    for (var u in _userCache.values) {
      if (u.username == cleanUsername && u.password == password) {
        _currentUser = u;
        if (!_activeAccounts.any((a) => a.uid == u.uid)) {
          _activeAccounts.add(u);
        }
        _saveUserSession(u.uid);
        updateUserPresence(true);
        notifyListeners();
        return u;
      }
    }

    return null;
  }

  /// Find user doc in Firestore by exact email address
  Future<UserModel?> findUserByEmail(String rawEmail) async {
    final cleanEmail = rawEmail.trim().toLowerCase();
    if (cleanEmail.isEmpty) return null;

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final user = UserModel.fromMap(doc.data(), doc.id);
        return user;
      }
    } catch (e) {
      debugPrint('findUserByEmail error: $e');
    }

    for (var u in _userCache.values) {
      if (u.email.toLowerCase() == cleanEmail) return u;
    }

    return null;
  }

  /// Generate & Save 6-digit Email OTP Code
  Future<String> sendEmailOtpCode(String rawEmail) async {
    final cleanEmail = rawEmail.trim().toLowerCase();
    final otpCode = (100000 + Random().nextInt(899999)).toString();

    try {
      await _firestore.collection('email_otps').doc(cleanEmail).set({
        'email': cleanEmail,
        'code': otpCode,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('sendEmailOtpCode firestore error: $e');
    }

    debugPrint('==================================================');
    debugPrint('⚡ [PORTAL OTP CODE] Email: $cleanEmail -> CODE: $otpCode');
    debugPrint('==================================================');

    // Free Real Email Delivery (Supports Resend.com or EmailJS out-of-the-box)
    final String resendApiKey = utf8.decode(base64.decode('cmVfTFNMV2F6YkFfTE1ITEx3TEc4OU42b1lrS3BHUFY4d1NI'));

    if (resendApiKey.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('https://api.resend.com/emails'),
          headers: {
            'Authorization': 'Bearer $resendApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'from': 'onboarding@resend.dev',
            'to': [cleanEmail],
            'subject': 'Ваш код подтверждения Portal: $otpCode',
            'html': '<div style="font-family:sans-serif;padding:20px;background:#0f172a;color:#ffffff;border-radius:12px;"><h2>Код подтверждения Portal</h2><p style="font-size:16px;color:#94a3b8;">Ваш 6-значный код верификации:</p><h1 style="font-size:36px;letter-spacing:6px;color:#38bdf8;">$otpCode</h1></div>',
          }),
        );
        debugPrint('Resend API response status: ${response.statusCode}');
        debugPrint('Resend API response body: ${response.body}');
      } catch (e) {
        debugPrint('Resend Email dispatch error: $e');
      }
    }

    return otpCode;
  }

  /// Verify 6-digit Email OTP Code
  Future<bool> verifyEmailOtpCode(String rawEmail, String inputCode, String expectedLocalCode) async {
    final cleanEmail = rawEmail.trim().toLowerCase();
    final cleanInput = inputCode.trim();
    if (cleanInput == expectedLocalCode.trim()) return true;

    try {
      final doc = await _firestore.collection('email_otps').doc(cleanEmail).get();
      if (doc.exists) {
        final savedCode = doc.data()?['code'] as String?;
        if (savedCode == cleanInput) return true;
      }
    } catch (e) {
      debugPrint('verifyEmailOtpCode error: $e');
    }

    return false;
  }

  /// Find user doc in Firestore by exact phone number
  Future<UserModel?> findUserByPhone(String rawPhone) async {
    final cleanPhone = rawPhone.trim();
    if (cleanPhone.isEmpty) return null;

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('phone', isEqualTo: cleanPhone)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final user = UserModel.fromMap(doc.data(), doc.id);
        return user;
      }
    } catch (e) {
      debugPrint('findUserByPhone error: $e');
    }

    for (var u in _userCache.values) {
      if (u.phone == cleanPhone) return u;
    }

    return null;
  }

  /// Sign in user directly by UserModel
  void setCurrentUserSession(UserModel user) {
    _currentUser = user;
    _userCache[user.uid] = user;
    if (!_activeAccounts.any((a) => a.uid == user.uid)) {
      _activeAccounts.add(user);
    }
    _saveUserSession(user.uid);
    updateUserPresence(true);
    notifyListeners();
  }

  /// Update User Profile in Firestore and local state
  Future<bool> updateUserProfile({
    required String name,
    required String username,
    required String avatarUrl,
    required String bio,
  }) async {
    if (_currentUser == null) return false;

    final cleanUsername = username.toLowerCase().replaceAll('@', '').trim();
    if (cleanUsername != _currentUser!.username) {
      final isFree = await isUsernameAvailable(cleanUsername);
      if (!isFree) return false;
    }

    final updatedUser = UserModel(
      uid: _currentUser!.uid,
      phone: _currentUser!.phone,
      password: _currentUser!.password,
      username: cleanUsername,
      name: name,
      avatarUrl: avatarUrl.isEmpty ? _currentUser!.avatarUrl : avatarUrl,
      bio: bio,
      isOnline: _currentUser!.isOnline,
      lastSeen: _currentUser!.lastSeen,
    );

    try {
      await _firestore.collection('users').doc(_currentUser!.uid).update(updatedUser.toMap());
    } catch (e) {
      debugPrint('updateUserProfile Firestore error: $e');
    }

    _currentUser = updatedUser;
    _userCache[updatedUser.uid] = updatedUser;

    final accIdx = _activeAccounts.indexWhere((a) => a.uid == updatedUser.uid);
    if (accIdx != -1) {
      _activeAccounts[accIdx] = updatedUser;
    }

    notifyListeners();
    return true;
  }

  /// Instant 0ms synchronous local lookup for user by username
  UserModel? getCachedUserByUsername(String query) {
    final cleanQuery = query.toLowerCase().replaceAll('@', '').trim();
    if (cleanQuery.isEmpty) return null;
    for (var u in _userCache.values) {
      if (u.username.toLowerCase() == cleanQuery) return u;
    }
    for (var u in _activeAccounts) {
      if (u.username.toLowerCase() == cleanQuery) return u;
    }
    return null;
  }

  /// Instant 0ms synchronous local lookup for channel by handle
  ChannelModel? getCachedChannelByHandle(String query) {
    final cleanQuery = query.toLowerCase().replaceAll('@', '').trim();
    if (cleanQuery.isEmpty) return null;
    for (var c in _localChannels) {
      if (c.handle.toLowerCase() == cleanQuery) return c;
    }
    return null;
  }

  /// Search user by @username in Firestore
  Future<UserModel?> searchUserByUsername(String query) async {
    final cleanQuery = query.toLowerCase().replaceAll('@', '').trim();
    if (cleanQuery.isEmpty) return null;

    final cached = getCachedUserByUsername(cleanQuery);
    if (cached != null) return cached;

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: cleanQuery)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final user = UserModel.fromMap(doc.data(), doc.id);
        _userCache[user.uid] = user;
        return user;
      }
    } catch (_) {}

    return null;
  }

  /// Search multiple users by query matching username or name
  Future<List<UserModel>> searchUsers(String query) async {
    final cleanQuery = query.toLowerCase().replaceAll('@', '').trim();
    if (cleanQuery.isEmpty) return [];

    final Map<String, UserModel> results = {};

    // 1. Search local cache first
    for (var u in _userCache.values) {
      if (u.username.toLowerCase().contains(cleanQuery) ||
          u.name.toLowerCase().contains(cleanQuery)) {
        results[u.uid] = u;
      }
    }
    for (var u in _activeAccounts) {
      if (u.username.toLowerCase().contains(cleanQuery) ||
          u.name.toLowerCase().contains(cleanQuery)) {
        results[u.uid] = u;
      }
    }

    // 2. Query Firestore users collection
    try {
      final snapshot = await _firestore
          .collection('users')
          .limit(20)
          .get();

      for (var doc in snapshot.docs) {
        final user = UserModel.fromMap(doc.data(), doc.id);
        _userCache[user.uid] = user;
        if (user.username.toLowerCase().contains(cleanQuery) ||
            user.name.toLowerCase().contains(cleanQuery)) {
          results[user.uid] = user;
        }
      }
    } catch (_) {}

    return results.values.toList();
  }

  /// Search multiple channels by query matching handle, title, or description
  Future<List<ChannelModel>> searchChannels(String query) async {
    final cleanQuery = query.toLowerCase().replaceAll('@', '').trim();
    if (cleanQuery.isEmpty) return [];

    final Map<String, ChannelModel> results = {};

    // 1. Search local channels cache
    for (var c in _localChannels) {
      if (c.handle.toLowerCase().contains(cleanQuery) ||
          c.title.toLowerCase().contains(cleanQuery) ||
          c.description.toLowerCase().contains(cleanQuery)) {
        results[c.channelId] = c;
      }
    }

    // 2. Query Firestore channels collection
    try {
      final snapshot = await _firestore
          .collection('channels')
          .limit(20)
          .get();

      for (var doc in snapshot.docs) {
        final channel = ChannelModel.fromMap(doc.data(), doc.id);
        if (!_localChannels.any((lc) => lc.channelId == channel.channelId)) {
          _localChannels.add(channel);
        }
        if (channel.handle.toLowerCase().contains(cleanQuery) ||
            channel.title.toLowerCase().contains(cleanQuery) ||
            channel.description.toLowerCase().contains(cleanQuery)) {
          results[channel.channelId] = channel;
        }
      }
    } catch (_) {}

    return results.values.toList();
  }

  /// Top up Portals currency balance for current logged-in user
  Future<void> topUpPortalsBalance(int amount) async {
    if (_currentUser == null || amount <= 0) return;

    final newBalance = _currentUser!.portalsBalance + amount;
    final updated = UserModel(
      uid: _currentUser!.uid,
      phone: _currentUser!.phone,
      username: _currentUser!.username,
      name: _currentUser!.name,
      avatarUrl: _currentUser!.avatarUrl,
      bio: _currentUser!.bio,
      password: _currentUser!.password,
      isOnline: _currentUser!.isOnline,
      lastSeen: _currentUser!.lastSeen,
      portalsBalance: newBalance,
    );

    try {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'portalsBalance': newBalance,
      });
    } catch (_) {}

    _currentUser = updated;
    _userCache[updated.uid] = updated;
    notifyListeners();
  }

  /// Update user's active profile song
  Future<void> updateProfileSong({
    required String profileSongTitle,
    required String profileSongArtist,
    required String profileSongUrl,
    required int profileSongDuration,
  }) async {
    if (_currentUser == null) return;

    final updated = UserModel(
      uid: _currentUser!.uid,
      phone: _currentUser!.phone,
      email: _currentUser!.email,
      username: _currentUser!.username,
      name: _currentUser!.name,
      avatarUrl: _currentUser!.avatarUrl,
      bio: _currentUser!.bio,
      password: _currentUser!.password,
      isOnline: _currentUser!.isOnline,
      lastSeen: _currentUser!.lastSeen,
      portalsBalance: _currentUser!.portalsBalance,
      isVerified: _currentUser!.isVerified,
      profileSongTitle: profileSongTitle,
      profileSongArtist: profileSongArtist,
      profileSongUrl: profileSongUrl,
      profileSongDuration: profileSongDuration,
      savedMusicTracks: _currentUser!.savedMusicTracks,
    );

    _currentUser = updated;
    _userCache[updated.uid] = updated;

    try {
      await _firestore.collection('users').doc(updated.uid).update({
        'profileSongTitle': profileSongTitle,
        'profileSongArtist': profileSongArtist,
        'profileSongUrl': profileSongUrl,
        'profileSongDuration': profileSongDuration,
      });
    } catch (_) {}

    notifyListeners();
  }

  /// Update user's saved music tracks library
  Future<void> updateSavedMusicTracks(List<Map<String, dynamic>> tracks) async {
    if (_currentUser == null) return;

    final updated = UserModel(
      uid: _currentUser!.uid,
      phone: _currentUser!.phone,
      email: _currentUser!.email,
      username: _currentUser!.username,
      name: _currentUser!.name,
      avatarUrl: _currentUser!.avatarUrl,
      bio: _currentUser!.bio,
      password: _currentUser!.password,
      isOnline: _currentUser!.isOnline,
      lastSeen: _currentUser!.lastSeen,
      portalsBalance: _currentUser!.portalsBalance,
      isVerified: _currentUser!.isVerified,
      profileSongTitle: _currentUser!.profileSongTitle,
      profileSongArtist: _currentUser!.profileSongArtist,
      profileSongUrl: _currentUser!.profileSongUrl,
      profileSongDuration: _currentUser!.profileSongDuration,
      savedMusicTracks: tracks,
    );

    _currentUser = updated;
    _userCache[updated.uid] = updated;

    try {
      await _firestore.collection('users').doc(updated.uid).update({
        'savedMusicTracks': tracks,
      });
    } catch (_) {}

    notifyListeners();
  }

  /// Stream received user gifts from Firestore / local cache
  Stream<List<UserGiftModel>> getUserGiftsStream(String userId) {
    if (userId.isEmpty) return Stream.value([]);

    try {
      return _firestore
          .collection('users')
          .doc(userId)
          .collection('gifts')
          .snapshots()
          .map((snapshot) {
        final gifts = snapshot.docs
            .map((doc) => UserGiftModel.fromMap(doc.data(), doc.id))
            .toList();
        gifts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _localUserGifts[userId] = gifts;
        return gifts;
      });
    } catch (_) {
      return Stream.value(_localUserGifts[userId] ?? []);
    }
  }

  /// Send a gift to a target user, deducting Portals balance from sender
  Future<bool> sendGift({
    required String receiverId,
    required String giftId,
    required String giftName,
    required String giftIcon,
    required int price,
    required String note,
  }) async {
    if (_currentUser == null || receiverId.isEmpty) return false;

    // Check balance
    if (_currentUser!.portalsBalance < price) {
      return false;
    }

    final newBalance = _currentUser!.portalsBalance - price;

    // 1. Deduct balance from sender
    final updatedSender = UserModel(
      uid: _currentUser!.uid,
      phone: _currentUser!.phone,
      username: _currentUser!.username,
      name: _currentUser!.name,
      avatarUrl: _currentUser!.avatarUrl,
      bio: _currentUser!.bio,
      password: _currentUser!.password,
      isOnline: _currentUser!.isOnline,
      lastSeen: _currentUser!.lastSeen,
      portalsBalance: newBalance,
    );

    try {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'portalsBalance': newBalance,
      });
    } catch (_) {}

    _currentUser = updatedSender;
    _userCache[updatedSender.uid] = updatedSender;

    // 2. Create gift doc
    final now = DateTime.now();
    final giftDocId = 'gift_${now.millisecondsSinceEpoch}';

    final gift = UserGiftModel(
      id: giftDocId,
      giftId: giftId,
      giftName: giftName,
      giftIcon: giftIcon,
      senderId: _currentUser!.uid,
      senderName: _currentUser!.name,
      senderAvatar: _currentUser!.avatarUrl,
      receiverId: receiverId,
      price: price,
      note: note.trim(),
      timestamp: now,
    );

    try {
      await _firestore
          .collection('users')
          .doc(receiverId)
          .collection('gifts')
          .doc(giftDocId)
          .set(gift.toMap());
    } catch (_) {}

    // Add to local gifts cache
    _localUserGifts.putIfAbsent(receiverId, () => []);
    _localUserGifts[receiverId]!.insert(0, gift);

    // Send chat message of type 'gift' to chat conversation
    try {
      await sendGiftMessage(
        receiverId: receiverId,
        giftName: giftName,
        giftIcon: giftIcon,
        note: note,
      );
    } catch (e) {
      debugPrint('sendGiftToUser chat message error: $e');
    }

    notifyListeners();
    return true;
  }

  /// Helper to get deterministic chatId between 2 users
  String getChatId(String uid1, String uid2) {
    final list = [uid1, uid2]..sort();
    return 'chat_${list[0]}_${list[1]}';
  }

  /// Send chat message of type 'gift'
  Future<void> sendGiftMessage({
    required String receiverId,
    required String giftName,
    required String giftIcon,
    required String note,
  }) async {
    if (_currentUser == null || receiverId.isEmpty) return;

    final chatId = getChatId(_currentUser!.uid, receiverId);
    final now = DateTime.now();
    final msgId = 'msg_${now.millisecondsSinceEpoch}';

    final giftMessage = MessageModel(
      id: msgId,
      senderId: _currentUser!.uid,
      receiverId: receiverId,
      text: note.trim(),
      type: 'gift',
      imageUrl: giftIcon.isNotEmpty ? giftIcon : giftName,
      isRead: false,
      timestamp: now,
      forwardedSenderName: _currentUser!.name,
      forwardedSenderAvatar: _currentUser!.avatarUrl,
    );

    _localMessages.putIfAbsent(chatId, () => []);
    _localMessages[chatId]!.add(giftMessage);

    if (!_messageStreamControllers.containsKey(chatId)) {
      _messageStreamControllers[chatId] = StreamController<List<MessageModel>>.broadcast();
    }
    _messageStreamControllers[chatId]!.add(List.from(_localMessages[chatId]!));

    try {
      final chatRef = _firestore.collection('chats').doc(chatId);
      await chatRef.set({
        'chatId': chatId,
        'participants': FieldValue.arrayUnion([_currentUser!.uid, receiverId]),
        'lastMessage': '🎁 Подарок от ${_currentUser!.name}',
        'lastMessageTime': now.toIso8601String(),
      }, SetOptions(merge: true));

      await chatRef.collection('messages').doc(msgId).set(giftMessage.toMap());
    } catch (e) {
      debugPrint('sendGiftMessage error: $e');
    }

    notifyListeners();
  }

  /// Send custom MessageModel object to chat
  Future<void> sendCustomMessage({
    required String chatId,
    required MessageModel message,
  }) async {
    if (_currentUser == null || chatId.isEmpty) return;

    _localMessages.putIfAbsent(chatId, () => []);
    _localMessages[chatId]!.add(message);

    if (!_messageStreamControllers.containsKey(chatId)) {
      _messageStreamControllers[chatId] = StreamController<List<MessageModel>>.broadcast();
    }
    _messageStreamControllers[chatId]!.add(List.from(_localMessages[chatId]!));

    try {
      final chatRef = _firestore.collection('chats').doc(chatId);
      final previewText = message.type == 'music'
          ? '🎵 ${message.text}'
          : (message.type == 'image' ? '📷 Фото' : message.text);

      await chatRef.set({
        'chatId': chatId,
        'participants': FieldValue.arrayUnion([_currentUser!.uid, message.receiverId]),
        'lastMessage': previewText,
        'lastMessageTime': message.timestamp.toIso8601String(),
      }, SetOptions(merge: true));

      await chatRef.collection('messages').doc(message.id).set(message.toMap());
    } catch (e) {
      debugPrint('sendCustomMessage error: $e');
    }

    notifyListeners();
  }

  /// Fetch shared media photos in chat between current user and peer user
  Future<List<String>> getChatMediaImages(String peerUserId) async {
    if (_currentUser == null || peerUserId.isEmpty) return [];

    final List<String> images = [];

    // Search local messages
    for (var list in _localMessages.values) {
      for (var msg in list) {
        if ((msg.senderId == _currentUser!.uid && msg.receiverId == peerUserId) ||
            (msg.senderId == peerUserId && msg.receiverId == _currentUser!.uid)) {
          if (msg.type == 'image' && msg.imageUrl != null && msg.imageUrl!.isNotEmpty) {
            images.add(msg.imageUrl!);
          }
        }
      }
    }

    return images.toSet().toList();
  }

  /// Fetch user profile from Firestore by UID
  Future<UserModel?> getUserProfile(String uid) async {
    if (uid.isEmpty) return null;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final user = UserModel.fromMap(doc.data()!, doc.id);
        _userCache[uid] = user;
        return user;
      }
    } catch (_) {}

    if (_userCache.containsKey(uid)) return _userCache[uid];
    return null;
  }

  /// Stream user profile live updates from Firestore
  Stream<UserModel?> getUserProfileStream(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final user = UserModel.fromMap(doc.data()!, doc.id);
        _userCache[uid] = user;
        return user;
      }
      return _userCache[uid];
    });
  }

  /// Get or Create Chat between current user and peer user
  Future<ChatModel> getOrCreateChat(UserModel peerUser) async {
    if (_currentUser == null) throw Exception('User not logged in');

    _userCache[peerUser.uid] = peerUser;

    final uids = [_currentUser!.uid, peerUser.uid]..sort();
    final chatId = 'chat_${uids[0]}_${uids[1]}';

    final chat = ChatModel(
      chatId: chatId,
      participants: uids,
      lastMessage: 'Начни диалог...',
      lastMessageTime: DateTime.now(),
      peerUser: peerUser,
    );

    final existingIdx = _localChats.indexWhere((c) => c.chatId == chatId);
    if (existingIdx != -1) {
      _localChats[existingIdx] = chat;
    } else {
      _localChats.add(chat);
    }

    try {
      final docSnapshot = await _firestore.collection('chats').doc(chatId).get();
      if (!docSnapshot.exists) {
        await _firestore.collection('chats').doc(chatId).set(chat.toMap());
      }
    } catch (e) {
      debugPrint('getOrCreateChat error: $e');
    }

    notifyListeners();
    return chat;
  }

  /// Send Text Message in Chat (Supports optional reply)
  Future<void> sendMessage({
    required String chatId,
    required String text,
    String? peerUid,
    String replyMessageId = '',
    String replySenderName = '',
    String replyText = '',
    String replyType = '',
  }) async {
    if (_currentUser == null || text.trim().isEmpty) return;

    final trimmedText = text.trim();
    final now = DateTime.now();
    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

    List<String> participants = [];
    final chatIndex = _localChats.indexWhere((c) => c.chatId == chatId);

    if (chatIndex != -1) {
      participants = List<String>.from(_localChats[chatIndex].participants);
    }

    if (participants.isEmpty && peerUid != null && peerUid.isNotEmpty) {
      participants = [_currentUser!.uid, peerUid]..sort();
    }

    final targetPeerUid = peerUid ??
        participants.firstWhere(
          (id) => id != _currentUser!.uid,
          orElse: () => '',
        );

    if (participants.length < 2 && targetPeerUid.isNotEmpty) {
      participants = [_currentUser!.uid, targetPeerUid]..sort();
    }

    final newMessage = MessageModel(
      id: msgId,
      senderId: _currentUser!.uid,
      receiverId: targetPeerUid,
      text: trimmedText,
      type: 'text',
      replyMessageId: replyMessageId,
      replySenderName: replySenderName,
      replyText: replyText,
      replyType: replyType,
      isRead: false,
      timestamp: now,
    );

    _localMessages.putIfAbsent(chatId, () => []);
    _localMessages[chatId]!.add(newMessage);

    if (!_messageStreamControllers.containsKey(chatId)) {
      _messageStreamControllers[chatId] = StreamController<List<MessageModel>>.broadcast();
    }
    _messageStreamControllers[chatId]!.add(List.from(_localMessages[chatId]!));

    if (chatIndex != -1) {
      _localChats[chatIndex] = ChatModel(
        chatId: chatId,
        participants: participants,
        lastMessage: trimmedText,
        lastMessageTime: now,
        peerUser: _localChats[chatIndex].peerUser,
      );
    } else {
      _localChats.add(ChatModel(
        chatId: chatId,
        participants: participants,
        lastMessage: trimmedText,
        lastMessageTime: now,
        peerUser: await getUserProfile(targetPeerUid),
      ));
    }

    notifyListeners();

    try {
      await _firestore.collection('chats').doc(chatId).collection('messages').doc(msgId).set(newMessage.toMap());
      await _firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'participants': participants,
        'lastMessage': trimmedText,
        'lastMessageTime': now.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('sendMessage Firestore error: $e');
    }
  }

  /// Send Image Attachment Message with Caption in Chat
  Future<void> sendImageMessage({
    required String chatId,
    required String imageBase64OrUrl,
    String caption = '',
    String? peerUid,
    String replyMessageId = '',
    String replySenderName = '',
    String replyText = '',
    String replyType = '',
  }) async {
    if (_currentUser == null || imageBase64OrUrl.isEmpty) return;

    final now = DateTime.now();
    final msgId = 'msg_${now.millisecondsSinceEpoch}';

    List<String> participants = [];
    final chatIndex = _localChats.indexWhere((c) => c.chatId == chatId);
    if (chatIndex != -1) {
      participants = List<String>.from(_localChats[chatIndex].participants);
    }
    if (participants.isEmpty && peerUid != null && peerUid.isNotEmpty) {
      participants = [_currentUser!.uid, peerUid]..sort();
    }
    final targetPeerUid = peerUid ??
        participants.firstWhere(
          (id) => id != _currentUser!.uid,
          orElse: () => '',
        );

    if (participants.length < 2 && targetPeerUid.isNotEmpty) {
      participants = [_currentUser!.uid, targetPeerUid]..sort();
    }

    final displayText = caption.isNotEmpty ? caption : '📷 Фотография';

    final newMessage = MessageModel(
      id: msgId,
      senderId: _currentUser!.uid,
      receiverId: targetPeerUid,
      text: caption,
      type: 'image',
      imageUrl: imageBase64OrUrl,
      replyMessageId: replyMessageId,
      replySenderName: replySenderName,
      replyText: replyText,
      replyType: replyType,
      isRead: false,
      timestamp: now,
    );

    _localMessages.putIfAbsent(chatId, () => []);
    _localMessages[chatId]!.add(newMessage);

    if (!_messageStreamControllers.containsKey(chatId)) {
      _messageStreamControllers[chatId] = StreamController<List<MessageModel>>.broadcast();
    }
    _messageStreamControllers[chatId]!.add(List.from(_localMessages[chatId]!));

    if (chatIndex != -1) {
      _localChats[chatIndex] = ChatModel(
        chatId: chatId,
        participants: participants,
        lastMessage: displayText,
        lastMessageTime: now,
        peerUser: _localChats[chatIndex].peerUser,
      );
    } else {
      _localChats.add(ChatModel(
        chatId: chatId,
        participants: participants,
        lastMessage: displayText,
        lastMessageTime: now,
        peerUser: await getUserProfile(targetPeerUid),
      ));
    }

    notifyListeners();

    try {
      await _firestore.collection('chats').doc(chatId).collection('messages').doc(msgId).set(newMessage.toMap());
      await _firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'participants': participants,
        'lastMessage': displayText,
        'lastMessageTime': now.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('sendImageMessage error: $e');
    }
  }

  /// Send Voice Message in Chat
  Future<void> sendVoiceMessage({
    required String chatId,
    required int durationSeconds,
    String audioUrl = '',
    String? peerUid,
    String replyMessageId = '',
    String replySenderName = '',
    String replyText = '',
    String replyType = '',
  }) async {
    if (_currentUser == null) return;

    final now = DateTime.now();
    final msgId = 'msg_${now.millisecondsSinceEpoch}';

    List<String> participants = [];
    final chatIndex = _localChats.indexWhere((c) => c.chatId == chatId);
    if (chatIndex != -1) {
      participants = List<String>.from(_localChats[chatIndex].participants);
    }
    if (participants.isEmpty && peerUid != null && peerUid.isNotEmpty) {
      participants = [_currentUser!.uid, peerUid]..sort();
    }
    final targetPeerUid = peerUid ??
        participants.firstWhere(
          (id) => id != _currentUser!.uid,
          orElse: () => '',
        );

    if (participants.length < 2 && targetPeerUid.isNotEmpty) {
      participants = [_currentUser!.uid, targetPeerUid]..sort();
    }

    final displayText = '🎤 Голосовое сообщение ($durationSecondsс)';

    final newMessage = MessageModel(
      id: msgId,
      senderId: _currentUser!.uid,
      receiverId: targetPeerUid,
      text: displayText,
      type: 'voice',
      imageUrl: audioUrl,
      audioDuration: durationSeconds,
      replyMessageId: replyMessageId,
      replySenderName: replySenderName,
      replyText: replyText,
      replyType: replyType,
      isRead: false,
      timestamp: now,
    );

    _localMessages.putIfAbsent(chatId, () => []);
    _localMessages[chatId]!.add(newMessage);

    if (!_messageStreamControllers.containsKey(chatId)) {
      _messageStreamControllers[chatId] = StreamController<List<MessageModel>>.broadcast();
    }
    _messageStreamControllers[chatId]!.add(List.from(_localMessages[chatId]!));

    if (chatIndex != -1) {
      _localChats[chatIndex] = ChatModel(
        chatId: chatId,
        participants: participants,
        lastMessage: displayText,
        lastMessageTime: now,
        peerUser: _localChats[chatIndex].peerUser,
      );
    } else {
      _localChats.add(ChatModel(
        chatId: chatId,
        participants: participants,
        lastMessage: displayText,
        lastMessageTime: now,
        peerUser: await getUserProfile(targetPeerUid),
      ));
    }

    notifyListeners();

    try {
      await _firestore.collection('chats').doc(chatId).collection('messages').doc(msgId).set(newMessage.toMap());
      await _firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'participants': participants,
        'lastMessage': displayText,
        'lastMessageTime': now.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('sendVoiceMessage error: $e');
    }
  }

  /// Send Circular Video Note Message in Chat
  Future<void> sendVideoNoteMessage({
    required String chatId,
    required int durationSeconds,
    String videoUrl = '',
    String? peerUid,
    String replyMessageId = '',
    String replySenderName = '',
    String replyText = '',
    String replyType = '',
  }) async {
    if (_currentUser == null) return;

    final now = DateTime.now();
    final msgId = 'msg_${now.millisecondsSinceEpoch}';

    List<String> participants = [];
    final chatIndex = _localChats.indexWhere((c) => c.chatId == chatId);
    if (chatIndex != -1) {
      participants = List<String>.from(_localChats[chatIndex].participants);
    }
    if (participants.isEmpty && peerUid != null && peerUid.isNotEmpty) {
      participants = [_currentUser!.uid, peerUid]..sort();
    }
    final targetPeerUid = peerUid ??
        participants.firstWhere(
          (id) => id != _currentUser!.uid,
          orElse: () => '',
        );

    if (participants.length < 2 && targetPeerUid.isNotEmpty) {
      participants = [_currentUser!.uid, targetPeerUid]..sort();
    }

    final displayText = '📹 Видеосообщение ($durationSecondsс)';

    final newMessage = MessageModel(
      id: msgId,
      senderId: _currentUser!.uid,
      receiverId: targetPeerUid,
      text: displayText,
      type: 'video_note',
      imageUrl: videoUrl,
      audioDuration: durationSeconds,
      replyMessageId: replyMessageId,
      replySenderName: replySenderName,
      replyText: replyText,
      replyType: replyType,
      isRead: false,
      timestamp: now,
    );

    _localMessages.putIfAbsent(chatId, () => []);
    _localMessages[chatId]!.add(newMessage);

    if (!_messageStreamControllers.containsKey(chatId)) {
      _messageStreamControllers[chatId] = StreamController<List<MessageModel>>.broadcast();
    }
    _messageStreamControllers[chatId]!.add(List.from(_localMessages[chatId]!));

    if (chatIndex != -1) {
      _localChats[chatIndex] = ChatModel(
        chatId: chatId,
        participants: participants,
        lastMessage: displayText,
        lastMessageTime: now,
        peerUser: _localChats[chatIndex].peerUser,
      );
    } else {
      _localChats.add(ChatModel(
        chatId: chatId,
        participants: participants,
        lastMessage: displayText,
        lastMessageTime: now,
        peerUser: await getUserProfile(targetPeerUid),
      ));
    }

    notifyListeners();

    try {
      await _firestore.collection('chats').doc(chatId).collection('messages').doc(msgId).set(newMessage.toMap());
      await _firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'participants': participants,
        'lastMessage': displayText,
        'lastMessageTime': now.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('sendVideoNoteMessage error: $e');
    }
  }

  /// Toggle Pin Chat for Current User
  final Set<String> _pinnedIds = {};

  bool isPinnedLocally(String id) {
    if (_currentUser == null) return false;
    return _pinnedIds.contains(id);
  }

  /// Toggle Pin Chat for Current User
  Future<void> togglePinChat(String chatId) async {
    if (_currentUser == null || chatId.isEmpty) return;
    final currentUid = _currentUser!.uid;

    if (_pinnedIds.contains(chatId)) {
      _pinnedIds.remove(chatId);
    } else {
      _pinnedIds.add(chatId);
    }

    final index = _localChats.indexWhere((c) => c.chatId == chatId);
    if (index != -1) {
      final chat = _localChats[index];
      List<String> updatedPinnedBy = List.from(chat.pinnedBy);
      if (updatedPinnedBy.contains(currentUid)) {
        updatedPinnedBy.remove(currentUid);
      } else {
        updatedPinnedBy.add(currentUid);
      }

      _localChats[index] = ChatModel(
        chatId: chat.chatId,
        participants: chat.participants,
        lastMessage: chat.lastMessage,
        lastMessageTime: chat.lastMessageTime,
        pinnedBy: updatedPinnedBy,
        peerUser: chat.peerUser,
      );
    }
    notifyListeners();

    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      List<String> firestorePinnedBy = List<String>.from(chatDoc.data()?['pinnedBy'] ?? []);
      if (_pinnedIds.contains(chatId)) {
        if (!firestorePinnedBy.contains(currentUid)) firestorePinnedBy.add(currentUid);
      } else {
        firestorePinnedBy.remove(currentUid);
      }
      await _firestore.collection('chats').doc(chatId).set({
        'pinnedBy': firestorePinnedBy,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('togglePinChat Firestore error: $e');
    }
  }

  /// Toggle Pin Channel for Current User
  Future<void> togglePinChannel(String channelId) async {
    if (_currentUser == null || channelId.isEmpty) return;
    final currentUid = _currentUser!.uid;

    if (_pinnedIds.contains(channelId)) {
      _pinnedIds.remove(channelId);
    } else {
      _pinnedIds.add(channelId);
    }

    final index = _localChannels.indexWhere((c) => c.channelId == channelId);
    if (index != -1) {
      final channel = _localChannels[index];
      List<String> updatedPinnedBy = List.from(channel.pinnedBy);
      if (updatedPinnedBy.contains(currentUid)) {
        updatedPinnedBy.remove(currentUid);
      } else {
        updatedPinnedBy.add(currentUid);
      }

      _localChannels[index] = ChannelModel(
        channelId: channel.channelId,
        ownerId: channel.ownerId,
        title: channel.title,
        description: channel.description,
        handle: channel.handle,
        avatarUrl: channel.avatarUrl,
        subscribers: channel.subscribers,
        subscribersCount: channel.subscribersCount,
        lastPost: channel.lastPost,
        lastPostTime: channel.lastPostTime,
        pinnedBy: updatedPinnedBy,
        createdAt: channel.createdAt,
      );
    }
    notifyListeners();

    try {
      final chanDoc = await _firestore.collection('channels').doc(channelId).get();
      List<String> firestorePinnedBy = List<String>.from(chanDoc.data()?['pinnedBy'] ?? []);
      if (_pinnedIds.contains(channelId)) {
        if (!firestorePinnedBy.contains(currentUid)) firestorePinnedBy.add(currentUid);
      } else {
        firestorePinnedBy.remove(currentUid);
      }
      await _firestore.collection('channels').doc(channelId).set({
        'pinnedBy': firestorePinnedBy,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('togglePinChannel Firestore error: $e');
    }
  }

  /// Permanently delete chat room and all its messages for BOTH users
  Future<void> deleteChat(String chatId) async {
    if (chatId.isEmpty) return;

    _localChats.removeWhere((c) => c.chatId == chatId);
    _localMessages.remove(chatId);
    notifyListeners();

    try {
      final messagesSnap = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      for (var doc in messagesSnap.docs) {
        await doc.reference.delete();
      }

      await _firestore.collection('chats').doc(chatId).delete();
    } catch (e) {
      debugPrint('deleteChat Firestore error: $e');
    }
  }

  /// Real-time stream of chats for current user from Firestore
  Stream<List<ChatModel>> getChatsStream() {
    if (_currentUser == null) {
      return Stream.value([]);
    }

    final currentUid = _currentUser!.uid;

    try {
      return _firestore.collection('chats').snapshots().asyncMap((snapshot) async {
        List<ChatModel> chats = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final participants = List<String>.from(data['participants'] ?? []);

          if (participants.contains(currentUid)) {
            final peerUid = participants.firstWhere(
              (id) => id != currentUid,
              orElse: () => '',
            );

            UserModel? peerUser;
            if (peerUid.isNotEmpty) {
              peerUser = await getUserProfile(peerUid);
            }

            chats.add(ChatModel.fromMap(data, doc.id, peerUser: peerUser));
          }
        }

        chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

        for (var local in _localChats) {
          if (!chats.any((c) => c.chatId == local.chatId) && local.participants.contains(currentUid)) {
            chats.add(local);
          }
        }
        chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

        return chats;
      });
    } catch (e) {
      debugPrint('getChatsStream error: $e');
      return Stream.value(_localChats.where((c) => c.participants.contains(currentUid)).toList());
    }
  }

  /// Real-time stream of messages in a specific chat from Firestore
  Stream<List<MessageModel>> getMessagesStream(String chatId) {
    if (!_messageStreamControllers.containsKey(chatId)) {
      _messageStreamControllers[chatId] = StreamController<List<MessageModel>>.broadcast();
    }

    final initialList = _localMessages[chatId] ?? [];
    Future.microtask(() {
      _messageStreamControllers[chatId]!.add(List.from(initialList));
    });

    try {
      _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .snapshots()
          .listen((snapshot) {
        final messages = snapshot.docs
            .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
            .toList();

        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (messages.isNotEmpty) {
          _localMessages[chatId] = messages;
          _messageStreamControllers[chatId]!.add(messages);
        }
      });
    } catch (_) {}

    return _messageStreamControllers[chatId]!.stream;
  }

  // ==========================================
  // PUBLIC CHANNELS ("КАНАЛЫ") BACKEND API
  // ==========================================

  final List<ChannelModel> _localChannels = [];
  final Map<String, List<ChannelPostModel>> _localChannelPosts = {};
  final Map<String, StreamController<List<ChannelPostModel>>> _channelPostControllers = {};

  /// Check if channel handle is available (unique, e.g. "tech_news")
  Future<bool> isChannelHandleAvailable(String handle) async {
    final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();
    if (cleanHandle.length < 3) return false;

    try {
      final snapshot = await _firestore
          .collection('channels')
          .where('handle', isEqualTo: cleanHandle)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return false;
      }
    } catch (_) {}

    return !_localChannels.any((c) => c.handle == cleanHandle);
  }

  /// Create a new public channel
  Future<ChannelModel> createChannel({
    required String title,
    required String description,
    required String handle,
    String avatarUrl = '',
  }) async {
    if (_currentUser == null) {
      throw Exception('Пользователь не авторизован');
    }

    final cleanHandle = handle.toLowerCase().replaceAll('@', '').trim();

    if (avatarUrl.isEmpty) {
      avatarUrl = 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=400&q=80';
    }

    final channelId = 'channel_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    final channel = ChannelModel(
      channelId: channelId,
      ownerId: _currentUser!.uid,
      title: title.trim(),
      description: description.trim(),
      handle: cleanHandle,
      avatarUrl: avatarUrl,
      subscribers: [_currentUser!.uid],
      subscribersCount: 1,
      lastPost: 'Канал создан',
      lastPostTime: now,
      createdAt: now,
    );

    try {
      await _firestore.collection('channels').doc(channelId).set(channel.toMap());

      // Create initial system post
      final initialPost = ChannelPostModel(
        id: 'post_${DateTime.now().millisecondsSinceEpoch}',
        channelId: channelId,
        authorId: _currentUser!.uid,
        authorName: title.trim(),
        authorAvatar: avatarUrl,
        text: 'Канал "$title" был успешно создан! Добро пожаловать!',
        type: 'text',
        viewsCount: 1,
        timestamp: now,
      );

      await _firestore
          .collection('channels')
          .doc(channelId)
          .collection('posts')
          .doc(initialPost.id)
          .set(initialPost.toMap());

      _localChannels.insert(0, channel);
      _localChannelPosts[channelId] = [initialPost];
      notifyListeners();
    } catch (e) {
      debugPrint('Error creating channel in Firestore: $e');
      _localChannels.insert(0, channel);
      notifyListeners();
    }

    return channel;
  }

  /// Get real-time stream of subscribed channels for the current user
  Stream<List<ChannelModel>> getSubscribedChannelsStream() {
    final currentUid = _currentUser?.uid ?? '';
    if (currentUid.isEmpty) return Stream.value([]);

    try {
      return _firestore.collection('channels').snapshots().map((snapshot) {
        List<ChannelModel> channels = snapshot.docs
            .map((doc) => ChannelModel.fromMap(doc.data(), doc.id))
            .where((c) => c.subscribers.contains(currentUid))
            .toList();

        channels.sort((a, b) => b.lastPostTime.compareTo(a.lastPostTime));

        for (var local in _localChannels) {
          if (!channels.any((c) => c.channelId == local.channelId) && local.subscribers.contains(currentUid)) {
            channels.add(local);
          }
        }
        channels.sort((a, b) => b.lastPostTime.compareTo(a.lastPostTime));

        return channels;
      });
    } catch (e) {
      return Stream.value(_localChannels.where((c) => c.subscribers.contains(currentUid)).toList());
    }
  }

  /// Search channels by handle or title
  Future<ChannelModel?> searchChannelByHandle(String query) async {
    final cleanQuery = query.toLowerCase().replaceAll('@', '').trim();
    if (cleanQuery.isEmpty) return null;

    final cached = getCachedChannelByHandle(cleanQuery);
    if (cached != null) return cached;

    try {
      final snapshot = await _firestore
          .collection('channels')
          .where('handle', isEqualTo: cleanQuery)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final channel = ChannelModel.fromMap(snapshot.docs.first.data(), snapshot.docs.first.id);
        _localChannels.removeWhere((c) => c.channelId == channel.channelId);
        _localChannels.add(channel);
        return channel;
      }
    } catch (_) {}

    for (var c in _localChannels) {
      if (c.handle.toLowerCase() == cleanQuery || c.title.toLowerCase().contains(cleanQuery)) {
        return c;
      }
    }

    return null;
  }

  /// Join public channel
  Future<void> joinChannel(String channelId) async {
    if (_currentUser == null || channelId.isEmpty) return;

    final currentUid = _currentUser!.uid;

    try {
      await _firestore.collection('channels').doc(channelId).update({
        'subscribers': FieldValue.arrayUnion([currentUid]),
        'subscribersCount': FieldValue.increment(1),
      });
    } catch (_) {}

    // Update local cache if available
    final idx = _localChannels.indexWhere((c) => c.channelId == channelId);
    if (idx != -1) {
      final old = _localChannels[idx];
      if (!old.subscribers.contains(currentUid)) {
        final newSubs = List<String>.from(old.subscribers)..add(currentUid);
        _localChannels[idx] = ChannelModel(
          channelId: old.channelId,
          ownerId: old.ownerId,
          title: old.title,
          description: old.description,
          handle: old.handle,
          avatarUrl: old.avatarUrl,
          subscribers: newSubs,
          subscribersCount: old.subscribersCount + 1,
          lastPost: old.lastPost,
          lastPostTime: old.lastPostTime,
          createdAt: old.createdAt,
        );
        notifyListeners();
      }
    }
  }

  /// Leave public channel
  Future<void> leaveChannel(String channelId) async {
    if (_currentUser == null || channelId.isEmpty) return;

    final currentUid = _currentUser!.uid;

    try {
      await _firestore.collection('channels').doc(channelId).update({
        'subscribers': FieldValue.arrayRemove([currentUid]),
        'subscribersCount': FieldValue.increment(-1),
      });
    } catch (_) {}

    // Update local cache
    final idx = _localChannels.indexWhere((c) => c.channelId == channelId);
    if (idx != -1) {
      final old = _localChannels[idx];
      if (old.subscribers.contains(currentUid)) {
        final newSubs = List<String>.from(old.subscribers)..remove(currentUid);
        _localChannels[idx] = ChannelModel(
          channelId: old.channelId,
          ownerId: old.ownerId,
          title: old.title,
          description: old.description,
          handle: old.handle,
          avatarUrl: old.avatarUrl,
          subscribers: newSubs,
          subscribersCount: max(old.subscribersCount - 1, 0),
          lastPost: old.lastPost,
          lastPostTime: old.lastPostTime,
          createdAt: old.createdAt,
        );
        notifyListeners();
      }
    }
  }

  /// Post a broadcast message into a channel (Owner only)
  Future<void> postToChannel({
    required String channelId,
    required String text,
    String type = 'text',
    String imageUrl = '',
    int audioDuration = 0,
  }) async {
    if (_currentUser == null || channelId.isEmpty) return;

    final now = DateTime.now();
    final postId = 'post_${now.millisecondsSinceEpoch}';

    final post = ChannelPostModel(
      id: postId,
      channelId: channelId,
      authorId: _currentUser!.uid,
      authorName: _currentUser!.name,
      authorAvatar: _currentUser!.avatarUrl,
      text: text.trim(),
      type: type,
      imageUrl: imageUrl,
      audioDuration: audioDuration,
      viewers: [_currentUser!.uid],
      viewsCount: 1,
      timestamp: now,
    );

    final snippet = type == 'image'
        ? '📷 Фотография'
        : type == 'voice'
            ? '🎙️ Голосовое сообщение'
            : type == 'video_note'
                ? '📹 Видеосообщение'
                : text.trim();

    try {
      await _firestore
          .collection('channels')
          .doc(channelId)
          .collection('posts')
          .doc(postId)
          .set(post.toMap());

      await _firestore.collection('channels').doc(channelId).update({
        'lastPost': snippet,
        'lastPostTime': now.toIso8601String(),
      });
    } catch (_) {}

    if (!_localChannelPosts.containsKey(channelId)) {
      _localChannelPosts[channelId] = [];
    }
    _localChannelPosts[channelId]!.add(post);

    if (_channelPostControllers.containsKey(channelId)) {
      _channelPostControllers[channelId]!.add(_localChannelPosts[channelId]!);
    }

    notifyListeners();
  }

  /// Register unique post view for current user in real-time
  Future<void> registerPostView({
    required String channelId,
    required String postId,
  }) async {
    if (_currentUser == null || channelId.isEmpty || postId.isEmpty) return;
    final myUid = _currentUser!.uid;

    try {
      final postRef = _firestore
          .collection('channels')
          .doc(channelId)
          .collection('posts')
          .doc(postId);

      final doc = await postRef.get();
      if (doc.exists) {
        final viewers = List<String>.from(doc.data()?['viewers'] ?? []);
        if (!viewers.contains(myUid)) {
          await postRef.update({
            'viewers': FieldValue.arrayUnion([myUid]),
            'viewsCount': FieldValue.increment(1),
          });
        }
      }
    } catch (_) {}

    // Update local cache
    if (_localChannelPosts.containsKey(channelId)) {
      final idx = _localChannelPosts[channelId]!.indexWhere((p) => p.id == postId);
      if (idx != -1) {
        final old = _localChannelPosts[channelId]![idx];
        if (!old.viewers.contains(myUid)) {
          final newViewers = List<String>.from(old.viewers)..add(myUid);
          _localChannelPosts[channelId]![idx] = ChannelPostModel(
            id: old.id,
            channelId: old.channelId,
            authorId: old.authorId,
            authorName: old.authorName,
            authorAvatar: old.authorAvatar,
            text: old.text,
            type: old.type,
            imageUrl: old.imageUrl,
            audioDuration: old.audioDuration,
            viewers: newViewers,
            viewsCount: old.viewsCount + 1,
            timestamp: old.timestamp,
          );
          if (_channelPostControllers.containsKey(channelId)) {
            _channelPostControllers[channelId]!.add(_localChannelPosts[channelId]!);
          }
        }
      }
    }
  }

  /// Stream of posts for a channel
  Stream<List<ChannelPostModel>> getChannelPostsStream(String channelId) {
    if (!_channelPostControllers.containsKey(channelId)) {
      _channelPostControllers[channelId] = StreamController<List<ChannelPostModel>>.broadcast();
    }

    final initialList = _localChannelPosts[channelId] ?? [];
    Future.microtask(() {
      _channelPostControllers[channelId]!.add(List.from(initialList));
    });

    try {
      _firestore
          .collection('channels')
          .doc(channelId)
          .collection('posts')
          .snapshots()
          .listen((snapshot) {
        final posts = snapshot.docs
            .map((doc) => ChannelPostModel.fromMap(doc.data(), doc.id))
            .toList();

        posts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (posts.isNotEmpty) {
          _localChannelPosts[channelId] = posts;
          _channelPostControllers[channelId]!.add(posts);
        }
      });
    } catch (_) {}

    return _channelPostControllers[channelId]!.stream;
  }

  /// Toggle emoji reaction on a direct chat message (Instant Optimistic UI)
  Future<void> toggleMessageReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    if (_currentUser == null || chatId.isEmpty || messageId.isEmpty) return;
    final myUid = _currentUser!.uid;

    Map<String, String> updatedReactions = {};

    // 1. Instant Optimistic Local Cache & Stream Update (0ms latency!)
    if (_localMessages.containsKey(chatId)) {
      final idx = _localMessages[chatId]!.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final old = _localMessages[chatId]![idx];
        updatedReactions = Map<String, String>.from(old.reactions);
        if (updatedReactions[myUid] == emoji) {
          updatedReactions.remove(myUid);
        } else {
          updatedReactions[myUid] = emoji;
        }

        _localMessages[chatId]![idx] = MessageModel(
          id: old.id,
          senderId: old.senderId,
          receiverId: old.receiverId,
          text: old.text,
          type: old.type,
          imageUrl: old.imageUrl,
          audioDuration: old.audioDuration,
          isRead: old.isRead,
          reactions: updatedReactions,
          timestamp: old.timestamp,
        );

        if (_messageStreamControllers.containsKey(chatId)) {
          _messageStreamControllers[chatId]!.add(List.from(_localMessages[chatId]!));
        }
      }
    }
    notifyListeners();

    // 2. Background Firestore Sync
    try {
      final msgRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      await msgRef.set({
        'reactions': updatedReactions,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Delete a message from direct chat for both users
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty) return;

    if (_localMessages.containsKey(chatId)) {
      _localMessages[chatId]!.removeWhere((m) => m.id == messageId);
      if (_messageStreamControllers.containsKey(chatId)) {
        _messageStreamControllers[chatId]!.add(List.from(_localMessages[chatId]!));
      }
    }
    notifyListeners();

    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (_) {}
  }

  /// Toggle emoji reaction on a channel post (Instant Optimistic UI)
  Future<void> toggleChannelPostReaction({
    required String channelId,
    required String postId,
    required String emoji,
  }) async {
    if (_currentUser == null || channelId.isEmpty || postId.isEmpty) return;
    final myUid = _currentUser!.uid;

    Map<String, String> updatedReactions = {};

    // 1. Instant Optimistic Local Cache & Stream Update (0ms latency!)
    if (_localChannelPosts.containsKey(channelId)) {
      final idx = _localChannelPosts[channelId]!.indexWhere((p) => p.id == postId);
      if (idx != -1) {
        final old = _localChannelPosts[channelId]![idx];
        updatedReactions = Map<String, String>.from(old.reactions);
        if (updatedReactions[myUid] == emoji) {
          updatedReactions.remove(myUid);
        } else {
          updatedReactions[myUid] = emoji;
        }

        _localChannelPosts[channelId]![idx] = ChannelPostModel(
          id: old.id,
          channelId: old.channelId,
          authorId: old.authorId,
          authorName: old.authorName,
          authorAvatar: old.authorAvatar,
          text: old.text,
          type: old.type,
          imageUrl: old.imageUrl,
          audioDuration: old.audioDuration,
          viewers: old.viewers,
          viewsCount: old.viewsCount,
          reactions: updatedReactions,
          timestamp: old.timestamp,
        );

        if (_channelPostControllers.containsKey(channelId)) {
          _channelPostControllers[channelId]!.add(List.from(_localChannelPosts[channelId]!));
        }
      }
    }
    notifyListeners();

    // 2. Background Firestore Sync
    try {
      final postRef = _firestore
          .collection('channels')
          .doc(channelId)
          .collection('posts')
          .doc(postId);

      await postRef.set({
        'reactions': updatedReactions,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Delete a post from channel (Owner only)
  Future<void> deleteChannelPost({
    required String channelId,
    required String postId,
  }) async {
    if (channelId.isEmpty || postId.isEmpty) return;

    try {
      await _firestore
          .collection('channels')
          .doc(channelId)
          .collection('posts')
          .doc(postId)
          .delete();
    } catch (_) {}

    if (_localChannelPosts.containsKey(channelId)) {
      _localChannelPosts[channelId]!.removeWhere((p) => p.id == postId);
      if (_channelPostControllers.containsKey(channelId)) {
        _channelPostControllers[channelId]!.add(List.from(_localChannelPosts[channelId]!));
      }
    }

    notifyListeners();
  }

  /// Forward a message or post to another chat
  Future<void> forwardMessage({
    required String targetChatId,
    required String text,
    required String type,
    String imageUrl = '',
    int audioDuration = 0,
    required String originalAuthorName,
    required String originalAuthorAvatar,
    String? peerUid,
  }) async {
    if (_currentUser == null || targetChatId.isEmpty) return;

    final now = DateTime.now();
    final msgId = 'msg_${now.millisecondsSinceEpoch}';

    final targetPeerUid = peerUid ?? '';

    final forwardedMessage = MessageModel(
      id: msgId,
      senderId: _currentUser!.uid,
      receiverId: targetPeerUid,
      text: text,
      type: type,
      imageUrl: imageUrl,
      audioDuration: audioDuration,
      isRead: false,
      forwardedSenderName: originalAuthorName,
      forwardedSenderAvatar: originalAuthorAvatar,
      timestamp: now,
    );

    _localMessages.putIfAbsent(targetChatId, () => []);
    _localMessages[targetChatId]!.add(forwardedMessage);

    if (!_messageStreamControllers.containsKey(targetChatId)) {
      _messageStreamControllers[targetChatId] = StreamController<List<MessageModel>>.broadcast();
    }
    _messageStreamControllers[targetChatId]!.add(List.from(_localMessages[targetChatId]!));

    try {
      final chatRef = _firestore.collection('chats').doc(targetChatId);
      final previewText = type == 'image' ? '📷 Фото' : (type == 'voice' ? '🎤 Голосовое сообщение' : text);
      await chatRef.set({
        'chatId': targetChatId,
        'participants': FieldValue.arrayUnion([_currentUser!.uid, if (targetPeerUid.isNotEmpty) targetPeerUid]),
        'lastMessage': '↩️ Переслано: $previewText',
        'lastMessageTime': now.toIso8601String(),
      }, SetOptions(merge: true));

      await chatRef.collection('messages').doc(msgId).set(forwardedMessage.toMap());
    } catch (_) {}

    notifyListeners();
  }

  // ==========================================
  // CALL SIGNALING SERVICE
  // ==========================================

  /// Initiate a new audio call
  Future<CallModel?> startCall({required UserModel receiver}) async {
    if (_currentUser == null) return null;
    final now = DateTime.now();
    final callId = 'call_${_currentUser!.uid}_${receiver.uid}_${now.millisecondsSinceEpoch}';

    final call = CallModel(
      callId: callId,
      callerId: _currentUser!.uid,
      callerName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.username,
      callerAvatar: _currentUser!.avatarUrl,
      receiverId: receiver.uid,
      receiverName: receiver.name.isNotEmpty ? receiver.name : receiver.username,
      receiverAvatar: receiver.avatarUrl,
      status: 'calling',
      createdAt: now,
    );

    try {
      await _firestore.collection('calls').doc(callId).set(call.toMap());
    } catch (e) {
      debugPrint('Error starting call: $e');
    }

    return call;
  }

  /// Accept an incoming call
  Future<void> acceptCall(String callId) async {
    final now = DateTime.now();
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'accepted',
        'acceptedAt': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error accepting call: $e');
    }
  }

  /// Reject or end an active call
  Future<void> endCall(String callId) async {
    final now = DateTime.now();
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'ended',
        'endedAt': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error ending call: $e');
    }
  }

  /// Stream of active call status changes
  Stream<CallModel?> listenToCallState(String callId) {
    return _firestore.collection('calls').doc(callId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return CallModel.fromMap(doc.data()!, doc.id);
      }
      return null;
    });
  }

  /// Stream listening for incoming calls directed to the current user
  Stream<CallModel?> listenToIncomingCall(String currentUid) {
    if (currentUid.isEmpty) return const Stream.empty();

    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: currentUid)
        .snapshots()
        .map((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status == 'calling' || status == 'accepted') {
          final createdAtStr = data['createdAt'] as String?;
          if (createdAtStr != null) {
            final createdAt = DateTime.tryParse(createdAtStr);
            if (createdAt != null && DateTime.now().difference(createdAt).inSeconds < 45) {
              return CallModel.fromMap(data, doc.id);
            }
          }
        }
      }
      return null;
    });
  }

  /// Send live audio voice chunk for an ongoing call
  Future<void> sendCallAudioChunk({
    required String callId,
    required String base64Data,
  }) async {
    if (_currentUser == null || callId.isEmpty || base64Data.isEmpty) return;
    final chunkId = 'chunk_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await _firestore
          .collection('calls')
          .doc(callId)
          .collection('audio_chunks')
          .doc(chunkId)
          .set({
        'senderId': _currentUser!.uid,
        'data': base64Data,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error sending audio chunk: $e');
    }
  }

  /// Listen to real-time audio voice chunks from the peer during a call
  Stream<String> listenToCallAudioChunks(String callId, String currentUid) {
    if (callId.isEmpty || currentUid.isEmpty) return const Stream.empty();

    return _firestore
        .collection('calls')
        .doc(callId)
        .collection('audio_chunks')
        .snapshots()
        .map((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['senderId'] != currentUid) {
            final base64Str = data['data'] as String?;
            if (base64Str != null && base64Str.isNotEmpty) {
              return base64Str;
            }
          }
        }
      }
      return '';
    }).where((data) => data.isNotEmpty);
  }

  // --- STREAKS ("ОГОНЬКИ") SERVICE ---
  final Map<String, StreakModel> _localStreaks = {};

  /// Get or create chat with peer and propose streak
  Future<void> proposeStreak(UserModel peerUser) async {
    if (_currentUser == null) return;
    final chat = await getOrCreateChat(peerUser);
    final streakDoc = _firestore.collection('streaks').doc(chat.chatId);

    final streak = StreakModel(
      chatId: chat.chatId,
      status: 'proposed',
      proposedBy: _currentUser!.uid,
      proposerName: _currentUser!.name,
      count: 1,
      messageSendersInCycle: [_currentUser!.uid],
      cycleStartTime: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _localStreaks[chat.chatId] = streak;
    try {
      await streakDoc.set(streak.toMap());
    } catch (e) {
      debugPrint('Error proposing streak: $e');
    }
    notifyListeners();
  }

  /// Accept an incoming proposed streak
  Future<void> acceptStreak(String chatId) async {
    if (_currentUser == null || chatId.isEmpty) return;
    final now = DateTime.now();

    final existing = _localStreaks[chatId];
    final streak = StreakModel(
      chatId: chatId,
      status: 'active',
      proposedBy: existing?.proposedBy ?? '',
      proposerName: existing?.proposerName ?? '',
      count: 1,
      messageSendersInCycle: [_currentUser!.uid],
      cycleStartTime: now,
      updatedAt: now,
    );

    _localStreaks[chatId] = streak;
    try {
      await _firestore.collection('streaks').doc(chatId).set(streak.toMap());
    } catch (e) {
      debugPrint('Error accepting streak: $e');
    }
    notifyListeners();
  }

  /// Delete / Remove active or proposed streak
  Future<void> deleteStreak(String chatId) async {
    if (chatId.isEmpty) return;
    _localStreaks.remove(chatId);
    try {
      await _firestore.collection('streaks').doc(chatId).delete();
    } catch (e) {
      debugPrint('Error deleting streak: $e');
    }
    notifyListeners();
  }

  /// Listen to real-time streak updates for a chat
  Stream<StreakModel?> listenToStreak(String chatId) {
    if (chatId.isEmpty) return const Stream.empty();

    return _firestore.collection('streaks').doc(chatId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final streak = StreakModel.fromMap(snapshot.data()!, snapshot.id);
        _localStreaks[chatId] = streak;
        return streak;
      }
      _localStreaks.remove(chatId);
      return _localStreaks[chatId];
    });
  }

  /// Get streak synchronously from cache
  StreakModel? getStreakLocally(String chatId) {
    return _localStreaks[chatId];
  }

  /// Update streak cycle when a message is sent in chat
  Future<void> updateStreakOnMessageSent(String chatId, String senderUid) async {
    if (chatId.isEmpty || senderUid.isEmpty) return;
    final streak = _localStreaks[chatId];
    if (streak == null || streak.status != 'active') return;

    final now = DateTime.now();
    final senders = List<String>.from(streak.messageSendersInCycle);
    if (!senders.contains(senderUid)) {
      senders.add(senderUid);
    }

    final hoursDiff = now.difference(streak.cycleStartTime).inHours;
    int newCount = streak.count;
    DateTime newCycleStart = streak.cycleStartTime;

    if (hoursDiff >= 12 && senders.length >= 2) {
      newCount += 1;
      newCycleStart = now;
      senders.clear();
      senders.add(senderUid);
    }

    final updated = StreakModel(
      chatId: chatId,
      status: 'active',
      proposedBy: streak.proposedBy,
      proposerName: streak.proposerName,
      count: newCount,
      messageSendersInCycle: senders,
      cycleStartTime: newCycleStart,
      updatedAt: now,
    );

    _localStreaks[chatId] = updated;
    try {
      await _firestore.collection('streaks').doc(chatId).set(updated.toMap());
    } catch (_) {}
    notifyListeners();
  }
}
