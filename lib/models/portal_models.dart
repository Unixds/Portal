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
  final UserModel? peerUser;

  ChatModel({
    required this.chatId,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageTime,
    this.peerUser,
  });

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'participants': participants,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
    };
  }

  factory ChatModel.fromMap(Map<String, dynamic> map, String docId, {UserModel? peerUser}) {
    return ChatModel(
      chatId: docId,
      participants: List<String>.from(map['participants'] ?? []),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: DateTime.tryParse(map['lastMessageTime'] ?? '') ?? DateTime.now(),
      peerUser: peerUser,
    );
  }
}

/// Chat Message Item Model (Supports text, image, voice attachments, read receipts)
class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final String type; // 'text', 'image', or 'voice'
  final String imageUrl;
  final int audioDuration;
  final bool isRead;
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
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, String docId) {
    return MessageModel(
      id: docId,
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      type: map['type'] ?? 'text',
      imageUrl: map['imageUrl'] ?? '',
      audioDuration: map['audioDuration'] ?? 0,
      isRead: map['isRead'] ?? false,
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}
