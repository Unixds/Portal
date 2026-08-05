/// User Profile Model for Portal Messenger
class UserModel {
  final String uid;
  final String phone;
  final String username;
  final String name;
  final String avatarUrl;
  final String bio;
  final String password;
  final bool isOnline;
  final DateTime? lastSeen;

  UserModel({
    required this.uid,
    required this.phone,
    required this.username,
    required this.name,
    required this.avatarUrl,
    required this.bio,
    this.password = '',
    this.isOnline = false,
    this.lastSeen,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phone': phone,
      'username': username,
      'name': name,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'password': password,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      uid: docId,
      phone: map['phone'] ?? '',
      username: map['username'] ?? '',
      name: map['name'] ?? '',
      avatarUrl: map['avatarUrl'] ?? '',
      bio: map['bio'] ?? '',
      password: map['password'] ?? '',
      isOnline: map['isOnline'] ?? false,
      lastSeen: map['lastSeen'] != null ? DateTime.tryParse(map['lastSeen']) : null,
    );
  }
}

/// Chat Room Summary Model
class ChatModel {
  final String chatId;
  final List<String> participants;
  final String lastMessage;
  final DateTime lastMessageTime;
  final List<String> pinnedBy;
  final UserModel? peerUser;

  ChatModel({
    required this.chatId,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageTime,
    this.pinnedBy = const [],
    this.peerUser,
  });

  bool isPinnedBy(String uid) => pinnedBy.contains(uid);

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'participants': participants,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'pinnedBy': pinnedBy,
    };
  }

  factory ChatModel.fromMap(Map<String, dynamic> map, String docId, {UserModel? peerUser}) {
    return ChatModel(
      chatId: docId,
      participants: List<String>.from(map['participants'] ?? []),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: DateTime.tryParse(map['lastMessageTime'] ?? '') ?? DateTime.now(),
      pinnedBy: List<String>.from(map['pinnedBy'] ?? []),
      peerUser: peerUser,
    );
  }
}

/// Chat Message Item Model (Supports text, image, voice attachments, read receipts, reactions, forwarded messages)
class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final String type; // 'text', 'image', or 'voice'
  final String imageUrl;
  final int audioDuration;
  final bool isRead;
  final Map<String, String> reactions; // Map of uid -> emoji
  final String forwardedSenderName;
  final String forwardedSenderAvatar;
  final DateTime timestamp;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.type = 'text',
    this.imageUrl = '',
    this.audioDuration = 0,
    this.isRead = false,
    this.reactions = const {},
    this.forwardedSenderName = '',
    this.forwardedSenderAvatar = '',
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'type': type,
      'imageUrl': imageUrl,
      'audioDuration': audioDuration,
      'isRead': isRead,
      'reactions': reactions,
      'forwardedSenderName': forwardedSenderName,
      'forwardedSenderAvatar': forwardedSenderAvatar,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawReactions = map['reactions'];
    Map<String, String> parsedReactions = {};
    if (rawReactions is Map) {
      rawReactions.forEach((key, value) {
        parsedReactions[key.toString()] = value.toString();
      });
    }

    return MessageModel(
      id: docId,
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      type: map['type'] ?? 'text',
      imageUrl: map['imageUrl'] ?? '',
      audioDuration: map['audioDuration'] ?? 0,
      isRead: map['isRead'] ?? false,
      reactions: parsedReactions,
      forwardedSenderName: map['forwardedSenderName'] ?? '',
      forwardedSenderAvatar: map['forwardedSenderAvatar'] ?? '',
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Public Channel Model for Telegram-style Channels ("Каналы")
class ChannelModel {
  final String channelId;
  final String ownerId;
  final String title;
  final String description;
  final String handle; // Unique link without @, e.g. "tech_news"
  final String avatarUrl;
  final List<String> subscribers;
  final int subscribersCount;
  final String lastPost;
  final DateTime lastPostTime;
  final List<String> pinnedBy;
  final DateTime createdAt;

  ChannelModel({
    required this.channelId,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.handle,
    required this.avatarUrl,
    required this.subscribers,
    required this.subscribersCount,
    required this.lastPost,
    required this.lastPostTime,
    this.pinnedBy = const [],
    required this.createdAt,
  });

  bool isPinnedBy(String uid) => pinnedBy.contains(uid);

  Map<String, dynamic> toMap() {
    return {
      'channelId': channelId,
      'ownerId': ownerId,
      'title': title,
      'description': description,
      'handle': handle,
      'avatarUrl': avatarUrl,
      'subscribers': subscribers,
      'subscribersCount': subscribersCount,
      'lastPost': lastPost,
      'lastPostTime': lastPostTime.toIso8601String(),
      'pinnedBy': pinnedBy,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChannelModel.fromMap(Map<String, dynamic> map, String docId) {
    final subs = List<String>.from(map['subscribers'] ?? []);
    return ChannelModel(
      channelId: docId,
      ownerId: map['ownerId'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      handle: map['handle'] ?? '',
      avatarUrl: map['avatarUrl'] ?? '',
      subscribers: subs,
      subscribersCount: map['subscribersCount'] ?? subs.length,
      lastPost: map['lastPost'] ?? '',
      lastPostTime: DateTime.tryParse(map['lastPostTime'] ?? '') ?? DateTime.now(),
      pinnedBy: List<String>.from(map['pinnedBy'] ?? []),
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Public Channel Broadcast Post Model
class ChannelPostModel {
  final String id;
  final String channelId;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String text;
  final String type; // 'text', 'image', 'voice', 'video_note'
  final String imageUrl;
  final int audioDuration;
  final List<String> viewers;
  final int viewsCount;
  final Map<String, String> reactions; // Map of uid -> emoji
  final DateTime timestamp;

  ChannelPostModel({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.text,
    this.type = 'text',
    this.imageUrl = '',
    this.audioDuration = 0,
    this.viewers = const [],
    this.viewsCount = 1,
    this.reactions = const {},
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'channelId': channelId,
      'authorId': authorId,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'text': text,
      'type': type,
      'imageUrl': imageUrl,
      'audioDuration': audioDuration,
      'viewers': viewers,
      'viewsCount': viewsCount,
      'reactions': reactions,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChannelPostModel.fromMap(Map<String, dynamic> map, String docId) {
    final viewersList = List<String>.from(map['viewers'] ?? []);
    final count = map['viewsCount'] ?? (viewersList.isNotEmpty ? viewersList.length : 1);

    final rawReactions = map['reactions'];
    Map<String, String> parsedReactions = {};
    if (rawReactions is Map) {
      rawReactions.forEach((key, value) {
        parsedReactions[key.toString()] = value.toString();
      });
    }

    return ChannelPostModel(
      id: docId,
      channelId: map['channelId'] ?? '',
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? '',
      authorAvatar: map['authorAvatar'] ?? '',
      text: map['text'] ?? '',
      type: map['type'] ?? 'text',
      imageUrl: map['imageUrl'] ?? '',
      audioDuration: map['audioDuration'] ?? 0,
      viewers: viewersList,
      viewsCount: count,
      reactions: parsedReactions,
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}

