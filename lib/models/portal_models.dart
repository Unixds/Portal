/// User Profile Model for Portal Messenger
class UserModel {
  final String uid;
  final String phone;
  final String email;
  final String username;
  final String name;
  final String avatarUrl;
  final String bio;
  final String password;
  final bool isOnline;
  final DateTime? lastSeen;
  final int portalsBalance;
  final bool isVerified;
  final String profileSongTitle;
  final String profileSongArtist;
  final String profileSongUrl;
  final int profileSongDuration;
  final List<Map<String, dynamic>> savedMusicTracks;

  UserModel({
    required this.uid,
    required this.phone,
    this.email = '',
    required this.username,
    required this.name,
    required this.avatarUrl,
    required this.bio,
    this.password = '',
    this.isOnline = false,
    this.lastSeen,
    this.portalsBalance = 100,
    this.isVerified = false,
    this.profileSongTitle = '',
    this.profileSongArtist = '',
    this.profileSongUrl = '',
    this.profileSongDuration = 0,
    this.savedMusicTracks = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phone': phone,
      'email': email,
      'username': username,
      'name': name,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'password': password,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.toIso8601String(),
      'portalsBalance': portalsBalance,
      'isVerified': isVerified,
      'profileSongTitle': profileSongTitle,
      'profileSongArtist': profileSongArtist,
      'profileSongUrl': profileSongUrl,
      'profileSongDuration': profileSongDuration,
      'savedMusicTracks': savedMusicTracks,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      uid: docId,
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      username: map['username'] ?? '',
      name: map['name'] ?? '',
      avatarUrl: map['avatarUrl'] ?? '',
      bio: map['bio'] ?? '',
      password: map['password'] ?? '',
      isOnline: map['isOnline'] ?? false,
      lastSeen: map['lastSeen'] != null ? DateTime.tryParse(map['lastSeen'].toString()) : null,
      portalsBalance: map['portalsBalance'] ?? 100,
      isVerified: map['isVerified'] ?? false,
      profileSongTitle: map['profileSongTitle'] ?? '',
      profileSongArtist: map['profileSongArtist'] ?? '',
      profileSongUrl: map['profileSongUrl'] ?? '',
      profileSongDuration: map['profileSongDuration'] ?? 0,
      savedMusicTracks: List<Map<String, dynamic>>.from(map['savedMusicTracks'] ?? []),
    );
  }
}

/// Chat Conversation Model
class ChatModel {
  final String chatId;
  final List<String> participants;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final List<String> pinnedBy;
  final UserModel? peerUser;

  bool isPinnedBy(String uid) => pinnedBy.contains(uid);

  ChatModel({
    required this.chatId,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.pinnedBy = const [],
    this.peerUser,
  });

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'participants': participants,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'unreadCount': unreadCount,
      'pinnedBy': pinnedBy,
    };
  }

  factory ChatModel.fromMap(Map<String, dynamic> map, String docId, {UserModel? peerUser}) {
    return ChatModel(
      chatId: docId,
      participants: List<String>.from(map['participants'] ?? []),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: map['lastMessageTime'] != null
          ? DateTime.parse(map['lastMessageTime'].toString())
          : DateTime.now(),
      unreadCount: map['unreadCount'] ?? 0,
      pinnedBy: List<String>.from(map['pinnedBy'] ?? []),
      peerUser: peerUser,
    );
  }
}

/// Message Model (supports text, voice, circular video notes, images, files, reactions)
class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime timestamp;
  final bool isRead;
  final String type; // 'text', 'voice', 'video_note', 'image', 'file', 'gift'
  final String mediaUrl;
  final String imageUrl;
  final int audioDuration;
  final MessageModel? replyToMessage;
  final String replyMessageId;
  final String replySenderName;
  final String replyText;
  final String replyType;
  final String forwardedSenderName;
  final String forwardedSenderAvatar;
  final Map<String, dynamic> reactions;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    this.isRead = false,
    this.type = 'text',
    String? mediaUrl,
    String? imageUrl,
    int? audioDuration,
    this.replyToMessage,
    String? replyMessageId,
    String? replySenderName,
    String? replyText,
    String? replyType,
    String? forwardedSenderName,
    String? forwardedSenderAvatar,
    this.reactions = const {},
  })  : mediaUrl = mediaUrl ?? imageUrl ?? '',
        imageUrl = imageUrl ?? mediaUrl ?? '',
        audioDuration = audioDuration ?? 0,
        replyMessageId = replyMessageId ?? '',
        replySenderName = replySenderName ?? '',
        replyText = replyText ?? '',
        replyType = replyType ?? '',
        forwardedSenderName = forwardedSenderName ?? '',
        forwardedSenderAvatar = forwardedSenderAvatar ?? '';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'type': type,
      'mediaUrl': mediaUrl,
      'imageUrl': imageUrl,
      'audioDuration': audioDuration,
      'replyToMessage': replyToMessage?.toMap(),
      'replyMessageId': replyMessageId,
      'replySenderName': replySenderName,
      'replyText': replyText,
      'replyType': replyType,
      'forwardedSenderName': forwardedSenderName,
      'forwardedSenderAvatar': forwardedSenderAvatar,
      'reactions': reactions,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, String docId) {
    final media = (map['mediaUrl'] ?? map['imageUrl'] ?? '').toString();
    return MessageModel(
      id: docId,
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'].toString())
          : DateTime.now(),
      isRead: map['isRead'] ?? false,
      type: map['type'] ?? 'text',
      mediaUrl: media,
      imageUrl: media,
      audioDuration: map['audioDuration'] ?? 0,
      replyToMessage: map['replyToMessage'] != null
          ? MessageModel.fromMap(Map<String, dynamic>.from(map['replyToMessage']), '')
          : null,
      replyMessageId: map['replyMessageId'] ?? '',
      replySenderName: map['replySenderName'] ?? '',
      replyText: map['replyText'] ?? '',
      replyType: map['replyType'] ?? '',
      forwardedSenderName: map['forwardedSenderName'] ?? '',
      forwardedSenderAvatar: map['forwardedSenderAvatar'] ?? '',
      reactions: Map<String, dynamic>.from(map['reactions'] ?? {}),
    );
  }
}

/// Channel Model for Broadcast Channels
class ChannelModel {
  final String channelId;
  final String ownerId;
  final String title;
  final String handle;
  final String description;
  final String avatarUrl;
  final List<String> subscribers;
  final int subscribersCount;
  final String lastPost;
  final DateTime lastPostTime;
  final DateTime createdAt;
  final List<String> pinnedBy;

  String get creatorId => ownerId;
  bool isPinnedBy(String uid) => pinnedBy.contains(uid);

  ChannelModel({
    required this.channelId,
    required this.ownerId,
    required this.title,
    required this.handle,
    required this.description,
    required this.avatarUrl,
    required this.subscribers,
    this.subscribersCount = 1,
    this.lastPost = '',
    required this.lastPostTime,
    required this.createdAt,
    this.pinnedBy = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'channelId': channelId,
      'ownerId': ownerId,
      'creatorId': ownerId,
      'title': title,
      'handle': handle,
      'description': description,
      'avatarUrl': avatarUrl,
      'subscribers': subscribers,
      'subscribersCount': subscribersCount,
      'lastPost': lastPost,
      'lastPostTime': lastPostTime.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'pinnedBy': pinnedBy,
    };
  }

  factory ChannelModel.fromMap(Map<String, dynamic> map, String docId) {
    final subs = List<String>.from(map['subscribers'] ?? []);
    return ChannelModel(
      channelId: docId,
      ownerId: map['ownerId'] ?? map['creatorId'] ?? '',
      title: map['title'] ?? '',
      handle: map['handle'] ?? '',
      description: map['description'] ?? '',
      avatarUrl: map['avatarUrl'] ?? '',
      subscribers: subs,
      subscribersCount: map['subscribersCount'] ?? subs.length,
      lastPost: map['lastPost'] ?? '',
      lastPostTime: map['lastPostTime'] != null
          ? DateTime.parse(map['lastPostTime'].toString())
          : DateTime.now(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'].toString())
          : DateTime.now(),
      pinnedBy: List<String>.from(map['pinnedBy'] ?? []),
    );
  }
}

/// Channel Post Model
class ChannelPostModel {
  final String id;
  final String channelId;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String text;
  final String type;
  final String imageUrl;
  final int audioDuration;
  final DateTime timestamp;
  final int viewsCount;
  final List<String> viewers;
  final Map<String, dynamic> reactions;

  ChannelPostModel({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.text,
    this.type = 'text',
    String? imageUrl,
    int? audioDuration,
    required this.timestamp,
    this.viewsCount = 0,
    this.viewers = const [],
    this.reactions = const {},
  })  : imageUrl = imageUrl ?? '',
        audioDuration = audioDuration ?? 0;

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
      'timestamp': timestamp.toIso8601String(),
      'viewsCount': viewsCount,
      'viewers': viewers,
      'reactions': reactions,
    };
  }

  factory ChannelPostModel.fromMap(Map<String, dynamic> map, String docId) {
    final v = List<String>.from(map['viewers'] ?? []);
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
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'].toString())
          : DateTime.now(),
      viewsCount: map['viewsCount'] ?? v.length,
      viewers: v,
      reactions: Map<String, dynamic>.from(map['reactions'] ?? {}),
    );
  }
}

/// User Gift Model
class UserGiftModel {
  final String id;
  final String giftId;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String receiverId;
  final String giftName;
  final String giftIcon;
  final int price;
  final String note;
  final DateTime timestamp;

  DateTime get sentAt => timestamp;
  int get priceInPortals => price;

  UserGiftModel({
    required this.id,
    String? giftId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar = '',
    this.receiverId = '',
    required this.giftName,
    required this.giftIcon,
    required this.price,
    this.note = '',
    required this.timestamp,
  }) : giftId = giftId ?? id;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'giftId': giftId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'receiverId': receiverId,
      'giftName': giftName,
      'giftIcon': giftIcon,
      'price': price,
      'note': note,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory UserGiftModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserGiftModel(
      id: docId,
      giftId: map['giftId'] ?? docId,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      senderAvatar: map['senderAvatar'] ?? '',
      receiverId: map['receiverId'] ?? '',
      giftName: map['giftName'] ?? '',
      giftIcon: map['giftIcon'] ?? '',
      price: map['price'] ?? map['priceInPortals'] ?? 0,
      note: map['note'] ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'].toString())
          : (map['sentAt'] != null
              ? DateTime.parse(map['sentAt'].toString())
              : DateTime.now()),
    );
  }
}

/// Voice / Video Call Model
class CallModel {
  final String callId;
  final String callerId;
  final String callerName;
  final String callerAvatar;
  final String receiverId;
  final String receiverName;
  final String receiverAvatar;
  final String status; // 'calling', 'accepted', 'ended', 'declined'
  final bool isVideo;
  final DateTime startedAt;

  DateTime get createdAt => startedAt;

  CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.receiverId,
    this.receiverName = '',
    this.receiverAvatar = '',
    required this.status,
    this.isVideo = false,
    DateTime? startedAt,
    DateTime? createdAt,
  }) : startedAt = startedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callerAvatar': callerAvatar,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverAvatar': receiverAvatar,
      'status': status,
      'isVideo': isVideo,
      'startedAt': startedAt.toIso8601String(),
      'createdAt': startedAt.toIso8601String(),
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map, String docId) {
    return CallModel(
      callId: docId,
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerAvatar: map['callerAvatar'] ?? '',
      receiverId: map['receiverId'] ?? '',
      receiverName: map['receiverName'] ?? '',
      receiverAvatar: map['receiverAvatar'] ?? '',
      status: map['status'] ?? 'calling',
      isVideo: map['isVideo'] ?? false,
      startedAt: map['startedAt'] != null
          ? DateTime.parse(map['startedAt'].toString())
          : (map['createdAt'] != null
              ? DateTime.parse(map['createdAt'].toString())
              : DateTime.now()),
    );
  }
}
