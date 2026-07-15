import '../core/utils/json_utils.dart';
import 'message.dart';
import 'user.dart';
import 'voice_call.dart';

class Participant {
  const Participant({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.username,
    this.bio,
    this.lastSeenAt,
    this.presenceVisible = true,
    this.joinedAt,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    final rawUser = json['userId'] ?? json['user'] ?? json;
    final userMap = jsonMapOrNull(rawUser);
    return Participant(
      id: objectId(rawUser).isNotEmpty ? objectId(rawUser) : objectId(json),
      displayName: stringValue(json['displayName'] ?? userMap?['displayName']),
      avatarUrl: nullableString(json['avatarUrl'] ?? userMap?['avatarUrl']),
      username: nullableString(json['username'] ?? userMap?['username']),
      bio: nullableString(json['bio'] ?? userMap?['bio']),
      lastSeenAt: dateTimeOrNull(json['lastSeenAt'] ?? userMap?['lastSeenAt']),
      presenceVisible:
          (json['presenceVisible'] ?? userMap?['presenceVisible']) is bool
          ? (json['presenceVisible'] ?? userMap?['presenceVisible']) as bool
          : true,
      joinedAt: dateTimeOrNull(json['joinedAt']),
    );
  }

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? username;
  final String? bio;
  final DateTime? lastSeenAt;
  final bool presenceVisible;
  final DateTime? joinedAt;

  static Participant? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return Participant.fromJson(map);
  }
}

class ConversationGroup {
  const ConversationGroup({
    required this.name,
    this.createdById,
    this.allowMembersToInvite = true,
    this.dissolvedAt,
    this.dissolvedById,
  });

  factory ConversationGroup.fromJson(Map<String, dynamic> json) {
    return ConversationGroup(
      name: stringValue(json['name']),
      createdById: nullableString(objectId(json['createdBy'])),
      allowMembersToInvite: json['allowMembersToInvite'] is bool
          ? json['allowMembersToInvite'] as bool
          : true,
      dissolvedAt: dateTimeOrNull(json['dissolvedAt']),
      dissolvedById: nullableString(objectId(json['dissolvedBy'])),
    );
  }

  final String name;
  final String? createdById;
  final bool allowMembersToInvite;
  final DateTime? dissolvedAt;
  final String? dissolvedById;
  bool get isDissolved => dissolvedAt != null;

  static ConversationGroup? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return ConversationGroup.fromJson(map);
  }
}

class LastMessage {
  const LastMessage({
    required this.id,
    required this.content,
    required this.senderId,
    this.sender,
    this.createdAt,
    this.messageType = MessageType.text,
    this.call,
    this.attachment,
    this.isRecalled = false,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    final rawSender = json['sender'] ?? json['senderId'];
    final senderMap = jsonMapOrNull(rawSender);
    return LastMessage(
      id: objectId(json),
      content: stringValue(json['content']),
      senderId: objectId(rawSender),
      sender: senderMap == null ? null : User.fromJson(senderMap),
      createdAt: dateTimeOrNull(json['createdAt']),
      messageType: MessageType.fromValue(json['messageType']),
      call: CallMessageMetadata.tryParse(json['call']),
      attachment: ReplyAttachmentMetadata.tryParse(json['attachment']),
      isRecalled: boolValue(json['isRecalled']),
    );
  }

  final String id;
  final String content;
  final String senderId;
  final User? sender;
  final DateTime? createdAt;
  final MessageType messageType;
  final CallMessageMetadata? call;
  final ReplyAttachmentMetadata? attachment;
  final bool isRecalled;

  String previewFor(String currentUserId) {
    if (isRecalled) return 'Tin nhắn đã thu hồi';

    final callMetadata = call;
    if (messageType == MessageType.call || callMetadata != null) {
      final mediaLabel = callMetadata?.mediaType.isVideo == true
          ? 'Cuộc gọi video'
          : 'Cuộc gọi thoại';
      final direction = callMetadata?.callerId == currentUserId ? 'đi' : 'đến';
      final duration = callMetadata == null
          ? null
          : formatCallDuration(callMetadata.durationSeconds);
      return duration == null
          ? '$mediaLabel $direction'
          : '$mediaLabel $direction · $duration';
    }

    final attachmentSummary = attachment;
    if (messageType == MessageType.attachment || attachmentSummary != null) {
      final label = switch (attachmentSummary?.kind) {
        MessageAttachmentKind.image => '📷 Ảnh',
        MessageAttachmentKind.video => '🎬 Video',
        MessageAttachmentKind.file =>
          '📎 ${attachmentSummary?.fileName ?? 'Tệp đính kèm'}',
        null => '📎 Tệp đính kèm',
      };
      final caption = content.trim();
      return caption.isEmpty ? label : '$label · $caption';
    }

    return content.trim();
  }

  static LastMessage? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return LastMessage.fromJson(map);
  }
}

class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.participants,
    required this.seenBy,
    required this.unreadCounts,
    this.group,
    this.lastMessageAt,
    this.lastMessage,
    this.createdAt,
    this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final unreadCounts = <String, int>{};
    final rawUnreadCounts = jsonMapOrNull(json['unreadCounts']);
    rawUnreadCounts?.forEach((key, value) {
      unreadCounts[key] = intValue(value);
    });

    return Conversation(
      id: objectId(json),
      type: stringValue(json['type'], fallback: 'direct'),
      participants: jsonList(json['participants'])
          .map(Participant.tryParse)
          .whereType<Participant>()
          .toList(growable: false),
      group: ConversationGroup.tryParse(json['group']),
      lastMessageAt: dateTimeOrNull(json['lastMessageAt']),
      seenBy: jsonList(
        json['seenBy'],
      ).map(User.tryParse).whereType<User>().toList(growable: false),
      lastMessage: LastMessage.tryParse(json['lastMessage']),
      unreadCounts: Map.unmodifiable(unreadCounts),
      createdAt: dateTimeOrNull(json['createdAt']),
      updatedAt: dateTimeOrNull(json['updatedAt']),
    );
  }

  final String id;
  final String type;
  final List<Participant> participants;
  final ConversationGroup? group;
  final DateTime? lastMessageAt;
  final List<User> seenBy;
  final LastMessage? lastMessage;
  final Map<String, int> unreadCounts;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDirect => type == 'direct';
  bool get isGroup => type == 'group';

  static Conversation? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return Conversation.fromJson(map);
  }

  Participant? otherParticipant(String currentUserId) {
    for (final participant in participants) {
      if (participant.id != currentUserId) return participant;
    }
    return participants.isEmpty ? null : participants.first;
  }

  String titleFor(String currentUserId) {
    if (isGroup && (group?.name.isNotEmpty ?? false)) return group!.name;
    final participant = otherParticipant(currentUserId);
    if (participant != null && participant.displayName.isNotEmpty) {
      return participant.displayName;
    }
    return isGroup ? 'Nhóm trò chuyện' : 'Cuộc trò chuyện';
  }

  String? avatarUrlFor(String currentUserId) {
    if (isGroup) return null;
    return otherParticipant(currentUserId)?.avatarUrl;
  }

  int unreadCountFor(String userId) => unreadCounts[userId] ?? 0;
}

class MarkSeenResult {
  const MarkSeenResult({
    required this.message,
    required this.seenBy,
    required this.myUnreadCount,
  });

  factory MarkSeenResult.fromJson(Map<String, dynamic> json) {
    return MarkSeenResult(
      message: stringValue(json['message']),
      seenBy: jsonList(
        json['seenBy'],
      ).map(User.tryParse).whereType<User>().toList(growable: false),
      myUnreadCount: intValue(json['myUnreadCount']),
    );
  }

  final String message;
  final List<User> seenBy;
  final int myUnreadCount;
}
