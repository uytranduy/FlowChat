import '../core/utils/json_utils.dart';
import 'user.dart';
import 'voice_call.dart';

enum MessageType {
  text,
  call,
  attachment,
  system;

  static MessageType fromValue(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'call' => MessageType.call,
      'attachment' => MessageType.attachment,
      'system' => MessageType.system,
      _ => MessageType.text,
    };
  }
}

enum MessageAttachmentKind {
  image,
  video,
  file;

  static MessageAttachmentKind fromValue(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'image' => MessageAttachmentKind.image,
      'video' => MessageAttachmentKind.video,
      _ => MessageAttachmentKind.file,
    };
  }
}

class MessageAttachment {
  const MessageAttachment({
    required this.kind,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.publicId,
    this.width,
    this.height,
    this.durationSeconds,
  });

  factory MessageAttachment.fromJson(Map<String, dynamic> json) {
    return MessageAttachment(
      kind: MessageAttachmentKind.fromValue(json['kind']),
      url: stringValue(json['url']),
      publicId: nullableString(json['publicId']),
      fileName: stringValue(json['fileName'], fallback: 'Tệp đính kèm'),
      mimeType: stringValue(
        json['mimeType'],
        fallback: 'application/octet-stream',
      ),
      sizeBytes: intValue(json['sizeBytes']),
      width: json['width'] == null ? null : intValue(json['width']),
      height: json['height'] == null ? null : intValue(json['height']),
      durationSeconds: json['durationSeconds'] == null
          ? null
          : intValue(json['durationSeconds']),
    );
  }

  factory MessageAttachment.legacyImage(String url) {
    return MessageAttachment(
      kind: MessageAttachmentKind.image,
      url: url,
      fileName: 'Hình ảnh',
      mimeType: 'image/*',
      sizeBytes: 0,
    );
  }

  final MessageAttachmentKind kind;
  final String url;
  final String? publicId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationSeconds;

  bool get isImage => kind == MessageAttachmentKind.image;
  bool get isVideo => kind == MessageAttachmentKind.video;

  static MessageAttachment? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    final attachment = MessageAttachment.fromJson(map);
    return attachment.url.isEmpty ? null : attachment;
  }
}

class CallMessageMetadata {
  const CallMessageMetadata({
    required this.callId,
    required this.callType,
    required this.mediaType,
    required this.callerId,
    required this.calleeId,
    required this.participantCount,
    required this.reason,
    required this.durationSeconds,
    required this.startedAt,
    this.acceptedAt,
    this.endedAt,
  });

  factory CallMessageMetadata.fromJson(Map<String, dynamic> json) {
    return CallMessageMetadata(
      callId: stringValue(json['callId']),
      callType: stringValue(json['callType'], fallback: 'direct'),
      mediaType: CallMediaType.fromValue(json['mediaType']),
      callerId: objectId(json['callerId']),
      calleeId: objectId(json['calleeId']),
      participantCount: json['participantCount'] == null
          ? null
          : intValue(json['participantCount']),
      reason: stringValue(json['reason'], fallback: 'ended'),
      durationSeconds: intValue(json['durationSeconds']),
      startedAt:
          dateTimeOrNull(json['startedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      acceptedAt: dateTimeOrNull(json['acceptedAt']),
      endedAt: dateTimeOrNull(json['endedAt']),
    );
  }

  final String callId;
  final String callType;
  final CallMediaType mediaType;
  final String callerId;
  final String calleeId;
  final int? participantCount;
  final String reason;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;

  bool isOutgoingFor(String userId) => callerId == userId;
  bool get isGroup => callType == 'group';

  static CallMessageMetadata? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return CallMessageMetadata.fromJson(map);
  }
}

class ReplyMessageMetadata {
  const ReplyMessageMetadata({
    required this.messageId,
    required this.senderId,
    required this.content,
    required this.messageType,
    required this.isRecalled,
    this.attachment,
  });

  factory ReplyMessageMetadata.fromJson(Map<String, dynamic> json) {
    return ReplyMessageMetadata(
      messageId: objectId(json['messageId']),
      senderId: objectId(json['senderId']),
      content: stringValue(json['content']),
      messageType: MessageType.fromValue(json['messageType']),
      isRecalled: boolValue(json['isRecalled']),
      attachment: ReplyAttachmentMetadata.tryParse(json['attachment']),
    );
  }

  final String messageId;
  final String senderId;
  final String content;
  final MessageType messageType;
  final bool isRecalled;
  final ReplyAttachmentMetadata? attachment;

  static ReplyMessageMetadata? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return ReplyMessageMetadata.fromJson(map);
  }
}

class ReplyAttachmentMetadata {
  const ReplyAttachmentMetadata({required this.kind, required this.fileName});

  factory ReplyAttachmentMetadata.fromJson(Map<String, dynamic> json) {
    return ReplyAttachmentMetadata(
      kind: MessageAttachmentKind.fromValue(json['kind']),
      fileName: stringValue(json['fileName'], fallback: 'Tệp đính kèm'),
    );
  }

  final MessageAttachmentKind kind;
  final String fileName;

  static ReplyAttachmentMetadata? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    return map == null ? null : ReplyAttachmentMetadata.fromJson(map);
  }
}

class MessageReaction {
  const MessageReaction({
    required this.userId,
    required this.emoji,
    this.createdAt,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      userId: objectId(json['userId']),
      emoji: stringValue(json['emoji']),
      createdAt: dateTimeOrNull(json['createdAt']),
    );
  }

  final String userId;
  final String emoji;
  final DateTime? createdAt;

  static MessageReaction? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    final reaction = MessageReaction.fromJson(map);
    return reaction.userId.isEmpty || reaction.emoji.isEmpty ? null : reaction;
  }
}

class ForwardedMessageMetadata {
  const ForwardedMessageMetadata({required this.messageId});

  factory ForwardedMessageMetadata.fromJson(Map<String, dynamic> json) {
    return ForwardedMessageMetadata(messageId: objectId(json['messageId']));
  }

  final String messageId;

  static ForwardedMessageMetadata? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    final forwarded = ForwardedMessageMetadata.fromJson(map);
    return forwarded.messageId.isEmpty ? null : forwarded;
  }
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.sender,
    this.imgUrl,
    this.attachment,
    this.updatedAt,
    this.messageType = MessageType.text,
    this.call,
    this.isRecalled = false,
    this.recalledAt,
    this.replyTo,
    this.reactions = const [],
    this.forwardedFrom,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final rawSender = json['sender'] ?? json['senderId'];
    final senderMap = jsonMapOrNull(rawSender);
    final imgUrl = nullableString(json['imgUrl']);
    return Message(
      id: objectId(json),
      conversationId: objectId(json['conversationId']),
      senderId: objectId(rawSender),
      sender: senderMap == null ? null : User.fromJson(senderMap),
      content: stringValue(json['content']),
      imgUrl: imgUrl,
      attachment:
          MessageAttachment.tryParse(json['attachment']) ??
          (imgUrl == null ? null : MessageAttachment.legacyImage(imgUrl)),
      messageType: MessageType.fromValue(json['messageType']),
      call: CallMessageMetadata.tryParse(json['call']),
      isRecalled: boolValue(json['isRecalled']),
      recalledAt: dateTimeOrNull(json['recalledAt']),
      replyTo: ReplyMessageMetadata.tryParse(json['replyTo']),
      reactions: jsonList(json['reactions'])
          .map(MessageReaction.tryParse)
          .whereType<MessageReaction>()
          .toList(growable: false),
      forwardedFrom: ForwardedMessageMetadata.tryParse(json['forwardedFrom']),
      createdAt:
          dateTimeOrNull(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: dateTimeOrNull(json['updatedAt']),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final User? sender;
  final String content;
  final String? imgUrl;
  final MessageAttachment? attachment;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final MessageType messageType;
  final CallMessageMetadata? call;
  final bool isRecalled;
  final DateTime? recalledAt;
  final ReplyMessageMetadata? replyTo;
  final List<MessageReaction> reactions;
  final ForwardedMessageMetadata? forwardedFrom;

  bool get isCall => messageType == MessageType.call && call != null;
  bool get isAttachment => attachment != null;
  bool get isForwarded => forwardedFrom != null;

  bool isOwn(String currentUserId) => senderId == currentUserId;

  bool hasReaction(String userId, String emoji) {
    return reactions.any(
      (reaction) => reaction.userId == userId && reaction.emoji == emoji,
    );
  }

  static Message? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return Message.fromJson(map);
  }
}

class MessagePage {
  const MessagePage({required this.messages, required this.nextCursor});

  factory MessagePage.fromJson(Map<String, dynamic> json) {
    return MessagePage(
      messages: jsonList(
        json['messages'],
      ).map(Message.tryParse).whereType<Message>().toList(growable: false),
      nextCursor: nullableString(json['nextCursor'] ?? json['cursor']),
    );
  }

  final List<Message> messages;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
