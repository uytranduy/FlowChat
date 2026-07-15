import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/utils/json_utils.dart';
import '../models/friend_request.dart';
import '../models/user.dart';

class FriendService {
  const FriendService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<User>> getFriends() async {
    final response = await _apiClient.get<dynamic>('friends');
    return jsonList(
      _apiClient.responseMap(response)['friends'],
    ).map(User.tryParse).whereType<User>().toList(growable: false);
  }

  Future<FriendRequestsResult> getFriendRequests() async {
    final response = await _apiClient.get<dynamic>('friends/requests');
    return FriendRequestsResult.fromJson(_apiClient.responseMap(response));
  }

  Future<User?> searchByUsername(String username) async {
    final response = await _apiClient.get<dynamic>(
      'users/search',
      queryParameters: {'username': username.trim()},
    );
    return User.tryParse(_apiClient.responseMap(response)['user']);
  }

  Future<FriendRequest> sendFriendRequest({
    required String to,
    String? message,
  }) async {
    final response = await _apiClient.post<dynamic>(
      'friends/requests',
      data: {
        'to': to,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
    final request = FriendRequest.tryParse(
      _apiClient.responseMap(response)['request'],
    );
    if (request != null) return request;
    throw _invalidResponse(response, 'Không thể đọc lời mời kết bạn vừa tạo.');
  }

  Future<User> acceptFriendRequest(String requestId) async {
    final response = await _apiClient.post<dynamic>(
      'friends/requests/$requestId/accept',
    );
    final friend = User.tryParse(_apiClient.responseMap(response)['newFriend']);
    if (friend != null) return friend;
    throw _invalidResponse(response, 'Không thể đọc thông tin người bạn mới.');
  }

  Future<void> declineFriendRequest(String requestId) async {
    final response = await _apiClient.post<dynamic>(
      'friends/requests/$requestId/decline',
    );
    _apiClient.responseMap(response);
  }

  Future<List<User>> getFriendList() => getFriends();

  Future<FriendRelationship> getRelationship(String userId) async {
    final response = await _apiClient.get<dynamic>(
      'friends/relationship/$userId',
    );
    return FriendRelationship.fromJson(_apiClient.responseMap(response));
  }

  Future<FriendRequestsResult> getAllFriendRequests() => getFriendRequests();

  Future<User> acceptRequest(String requestId) =>
      acceptFriendRequest(requestId);

  Future<void> declineRequest(String requestId) =>
      declineFriendRequest(requestId);

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
