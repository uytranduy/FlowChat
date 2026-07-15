import '../core/utils/json_utils.dart';
import 'user.dart';

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.from,
    required this.to,
    required this.message,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: objectId(json),
      from: User.tryParse(json['from']),
      to: User.tryParse(json['to']),
      message: stringValue(json['message']),
      createdAt: dateTimeOrNull(json['createdAt']),
    );
  }

  final String id;
  final User? from;
  final User? to;
  final String message;
  final DateTime? createdAt;

  static FriendRequest? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return FriendRequest.fromJson(map);
  }
}

class FriendRequestsResult {
  const FriendRequestsResult({required this.sent, required this.received});

  factory FriendRequestsResult.fromJson(Map<String, dynamic> json) {
    List<FriendRequest> parseList(Object? value) => jsonList(value)
        .map(FriendRequest.tryParse)
        .whereType<FriendRequest>()
        .toList(growable: false);

    return FriendRequestsResult(
      sent: parseList(json['sent']),
      received: parseList(json['received']),
    );
  }

  final List<FriendRequest> sent;
  final List<FriendRequest> received;
}

class FriendRelationship {
  const FriendRelationship({
    required this.isFriend,
    required this.canCall,
    required this.canSendMessage,
    required this.isBlocked,
    required this.isBlockedByMe,
    required this.hasBlockedMe,
    this.requestId,
    this.requestDirection,
  });

  factory FriendRelationship.fromJson(Map<String, dynamic> json) {
    final request = jsonMapOrNull(json['request']);
    return FriendRelationship(
      isFriend: boolValue(json['isFriend']),
      canCall: boolValue(json['canCall']),
      canSendMessage: boolValue(json['canSendMessage']),
      requestId: nullableString(objectId(request)),
      requestDirection: nullableString(request?['direction']),
      isBlocked: boolValue(jsonMapOrNull(json['blockStatus'])?['isBlocked']),
      isBlockedByMe: boolValue(
        jsonMapOrNull(json['blockStatus'])?['isBlockedByMe'],
      ),
      hasBlockedMe: boolValue(
        jsonMapOrNull(json['blockStatus'])?['hasBlockedMe'],
      ),
    );
  }

  final bool isFriend;
  final bool canCall;
  final bool canSendMessage;
  final String? requestId;
  final String? requestDirection;
  final bool isBlocked;
  final bool isBlockedByMe;
  final bool hasBlockedMe;

  bool get isIncomingRequest => requestDirection == 'incoming';
  bool get isOutgoingRequest => requestDirection == 'outgoing';
}
