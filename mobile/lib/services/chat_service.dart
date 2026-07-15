import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/utils/json_utils.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';

class ChatService {
  const ChatService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Conversation>> getConversations() async {
    final response = await _apiClient.get<dynamic>('conversations');
    return jsonList(_apiClient.responseMap(response)['conversations'])
        .map(Conversation.tryParse)
        .whereType<Conversation>()
        .toList(growable: false);
  }

  Future<MessagePage> getMessages(
    String conversationId, {
    int limit = 50,
    String? cursor,
  }) async {
    if (limit <= 0) {
      throw const ApiException(message: 'Giới hạn tin nhắn phải lớn hơn 0.');
    }
    final response = await _apiClient.get<dynamic>(
      'conversations/$conversationId/messages',
      queryParameters: {
        'limit': limit,
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    return MessagePage.fromJson(_apiClient.responseMap(response));
  }

  Future<Message> sendDirectMessage(
    String recipientId,
    String content, {
    String? conversationId,
    String? imgUrl,
    String? replyToMessageId,
    String? filePath,
    String? fileName,
    ProgressCallback? onSendProgress,
  }) async {
    final fields = <String, dynamic>{
      'recipientId': recipientId,
      'content': content,
      if (conversationId != null && conversationId.isNotEmpty)
        'conversationId': conversationId,
      if (imgUrl != null && imgUrl.isNotEmpty) 'imgUrl': imgUrl,
      if (replyToMessageId != null && replyToMessageId.isNotEmpty)
        'replyToMessageId': replyToMessageId,
    };
    final response = await _apiClient.post<dynamic>(
      'messages/direct',
      data: await _messagePayload(
        fields,
        filePath: filePath,
        fileName: fileName,
      ),
      onSendProgress: onSendProgress,
    );
    return _messageFromResponse(response);
  }

  Future<Message> sendGroupMessage(
    String conversationId,
    String content, {
    String? imgUrl,
    String? replyToMessageId,
    String? filePath,
    String? fileName,
    ProgressCallback? onSendProgress,
  }) async {
    final fields = <String, dynamic>{
      'conversationId': conversationId,
      'content': content,
      if (imgUrl != null && imgUrl.isNotEmpty) 'imgUrl': imgUrl,
      if (replyToMessageId != null && replyToMessageId.isNotEmpty)
        'replyToMessageId': replyToMessageId,
    };
    final response = await _apiClient.post<dynamic>(
      'messages/group',
      data: await _messagePayload(
        fields,
        filePath: filePath,
        fileName: fileName,
      ),
      onSendProgress: onSendProgress,
    );
    return _messageFromResponse(response);
  }

  Future<Message> recallMessage(String messageId) async {
    final response = await _apiClient.patch<dynamic>(
      'messages/$messageId/recall',
    );
    return _messageFromResponse(response);
  }

  Future<Message> setReaction(String messageId, String emoji) async {
    final response = await _apiClient.request<dynamic>(
      'messages/$messageId/reaction',
      method: 'PUT',
      data: {'emoji': emoji},
    );
    return _messageFromResponse(response);
  }

  Future<Message> removeReaction(String messageId) async {
    final response = await _apiClient.request<dynamic>(
      'messages/$messageId/reaction',
      method: 'DELETE',
    );
    return _messageFromResponse(response);
  }

  Future<Message> forwardMessage(
    String messageId,
    String conversationId,
  ) async {
    final response = await _apiClient.post<dynamic>(
      'messages/$messageId/forward',
      data: {'conversationId': conversationId},
    );
    return _messageFromResponse(response);
  }

  Future<MarkSeenResult> markAsSeen(String conversationId) async {
    final response = await _apiClient.patch<dynamic>(
      'conversations/$conversationId/seen',
    );
    return MarkSeenResult.fromJson(_apiClient.responseMap(response));
  }

  Future<Conversation> createConversation(
    String type, {
    String? name,
    required List<String> memberIds,
  }) async {
    if (type != 'direct' && type != 'group') {
      throw const ApiException(
        message: 'Loại cuộc trò chuyện phải là direct hoặc group.',
      );
    }
    final response = await _apiClient.post<dynamic>(
      'conversations',
      data: {
        'type': type,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        'memberIds': memberIds,
      },
    );
    final conversation = Conversation.tryParse(
      _apiClient.responseMap(response)['conversation'],
    );
    if (conversation != null) return conversation;
    throw _invalidResponse(response, 'Không thể đọc cuộc trò chuyện vừa tạo.');
  }

  Future<Conversation> createDirectConversation(String memberId) {
    return createConversation('direct', memberIds: [memberId]);
  }

  Future<Conversation> addGroupMember(
    String conversationId,
    String userId,
  ) async {
    final response = await _apiClient.post<dynamic>(
      'conversations/$conversationId/members',
      data: {'userId': userId},
    );
    final conversation = Conversation.tryParse(
      _apiClient.responseMap(response)['conversation'],
    );
    if (conversation != null) return conversation;
    throw _invalidResponse(response, 'Không thể đọc nhóm vừa cập nhật.');
  }

  Future<Conversation> transferGroupOwnership(
    String conversationId,
    String userId,
  ) async {
    final response = await _apiClient.patch<dynamic>(
      'conversations/$conversationId/owner',
      data: {'userId': userId},
    );
    final conversation = Conversation.tryParse(
      _apiClient.responseMap(response)['conversation'],
    );
    if (conversation != null) return conversation;
    throw _invalidResponse(response, 'Không thể đọc nhóm vừa cập nhật.');
  }

  Future<Conversation> updateGroupInvitePermission(
    String conversationId,
    bool allowMembersToInvite,
  ) async {
    final response = await _apiClient.patch<dynamic>(
      'conversations/$conversationId/group-settings',
      data: {'allowMembersToInvite': allowMembersToInvite},
    );
    final conversation = Conversation.tryParse(
      _apiClient.responseMap(response)['conversation'],
    );
    if (conversation != null) return conversation;
    throw _invalidResponse(response, 'Không thể đọc quyền nhóm vừa cập nhật.');
  }

  Future<void> leaveGroup(String conversationId) async {
    await _apiClient.request<dynamic>(
      'conversations/$conversationId/members/me',
      method: 'DELETE',
    );
  }

  Future<Conversation> dissolveGroup(String conversationId) async {
    final response = await _apiClient.patch<dynamic>(
      'conversations/$conversationId/dissolve',
    );
    final conversation = Conversation.tryParse(
      _apiClient.responseMap(response)['conversation'],
    );
    if (conversation != null) return conversation;
    throw _invalidResponse(response, 'Không thể đọc nhóm vừa giải tán.');
  }

  Future<void> removeDissolvedGroup(String conversationId) async {
    await _apiClient.request<dynamic>(
      'conversations/$conversationId',
      method: 'DELETE',
    );
  }

  Future<UserBlockStatus> getBlockStatus(String userId) async {
    final response = await _apiClient.get<dynamic>(
      'users/blocks/$userId/status',
    );
    return UserBlockStatus.fromJson(_apiClient.responseMap(response));
  }

  Future<UserBlockStatus> blockUser(String userId) async {
    final response = await _apiClient.post<dynamic>('users/blocks/$userId');
    return UserBlockStatus.fromJson(
      jsonMapOrNull(_apiClient.responseMap(response)['status']) ?? const {},
    );
  }

  Future<UserBlockStatus> unblockUser(String userId) async {
    final response = await _apiClient.request<dynamic>(
      'users/blocks/$userId',
      method: 'DELETE',
    );
    return UserBlockStatus.fromJson(
      jsonMapOrNull(_apiClient.responseMap(response)['status']) ?? const {},
    );
  }

  Future<List<User>> getBlockedUsers() async {
    final response = await _apiClient.get<dynamic>('users/blocks');
    return jsonList(
      _apiClient.responseMap(response)['blockedUsers'],
    ).map(User.tryParse).whereType<User>().toList(growable: false);
  }

  Future<Conversation> createGroupConversation({
    required String name,
    required List<String> memberIds,
  }) {
    return createConversation('group', name: name, memberIds: memberIds);
  }

  Future<List<Conversation>> fetchConversations() => getConversations();

  Future<MessagePage> fetchMessages(
    String conversationId, {
    int limit = 50,
    String? cursor,
  }) => getMessages(conversationId, limit: limit, cursor: cursor);

  Future<Object> _messagePayload(
    Map<String, dynamic> fields, {
    String? filePath,
    String? fileName,
  }) async {
    if (filePath == null || filePath.trim().isEmpty) return fields;
    final multipart = await MultipartFile.fromFile(
      filePath,
      filename: fileName == null || fileName.trim().isEmpty
          ? _fileName(filePath)
          : fileName.trim(),
    );
    return FormData.fromMap({...fields, 'file': multipart});
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last.trim();
    return name.isEmpty ? 'attachment' : name;
  }

  Message _messageFromResponse(Response<dynamic> response) {
    final message = Message.tryParse(
      _apiClient.responseMap(response)['message'],
    );
    if (message != null) return message;
    throw _invalidResponse(response, 'Không thể đọc tin nhắn vừa gửi.');
  }

  static ApiException _invalidResponse(
    Response<dynamic> response,
    String message,
  ) {
    return ApiException(
      statusCode: response.statusCode,
      message: message,
      data: response.data,
      path: response.requestOptions.path,
    );
  }
}

class UserBlockStatus {
  const UserBlockStatus({
    required this.isBlocked,
    required this.isBlockedByMe,
    required this.hasBlockedMe,
  });

  factory UserBlockStatus.fromJson(Map<String, dynamic> json) =>
      UserBlockStatus(
        isBlocked: boolValue(json['isBlocked']),
        isBlockedByMe: boolValue(json['isBlockedByMe']),
        hasBlockedMe: boolValue(json['hasBlockedMe']),
      );

  final bool isBlocked;
  final bool isBlockedByMe;
  final bool hasBlockedMe;
}
