import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/portal_models.dart';

/// Firebase & Real-time Messaging Service for Portal Messenger.
/// Fully handles user registration, multi-account sessions, profile updates,
/// username availability checks, user search, presence status, typing indicators, read receipts, voice messages, and circular video notes.
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

  Future<void> init() async {}

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
        updateUserPresence(true);
        notifyListeners();
        return u;
      }
    }

    return null;
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

  /// Search user by @username in Firestore
  Future<UserModel?> searchUserByUsername(String query) async {
    final cleanQuery = query.toLowerCase().replaceAll('@', '').trim();
    if (cleanQuery.isEmpty) return null;

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: cleanQuery)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        if (doc.id != _currentUser?.uid) {
          final user = UserModel.fromMap(doc.data(), doc.id);
          _userCache[user.uid] = user;
          return user;
        }
      }
    } catch (_) {}

    for (var u in _userCache.values) {
      if (u.uid != _currentUser?.uid && u.username.toLowerCase().contains(cleanQuery)) {
        return u;
      }
    }

    return null;
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

  /// Send Text Message in Chat
  Future<void> sendMessage({
    required String chatId,
    required String text,
    String? peerUid,
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
    String? peerUid,
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
      audioDuration: durationSeconds,
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
    String? peerUid,
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
      audioDuration: durationSeconds,
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
}
