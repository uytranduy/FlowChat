import 'dart:io';

import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/utils/json_utils.dart';
import '../models/user.dart';

class UserService {
  const UserService(this._apiClient);

  static const int maxAvatarBytes = 1024 * 1024;

  final ApiClient _apiClient;

  Future<User> getMe() async {
    final response = await _apiClient.get<dynamic>('users/me');
    final user = User.tryParse(_apiClient.responseMap(response)['user']);
    if (user != null) return user;
    throw _invalidResponse(response, 'Không thể đọc thông tin người dùng.');
  }

  Future<User?> searchByUsername(String username) async {
    final response = await _apiClient.get<dynamic>(
      'users/search',
      queryParameters: {'username': username.trim()},
    );
    return User.tryParse(_apiClient.responseMap(response)['user']);
  }

  Future<User> getPublicUser(String userId) async {
    final response = await _apiClient.get<dynamic>('users/$userId/public');
    final user = User.tryParse(_apiClient.responseMap(response)['user']);
    if (user != null) return user;
    throw _invalidResponse(response, 'Không thể đọc hồ sơ người dùng.');
  }

  Future<User> updateProfile({
    required String displayName,
    required String username,
    required String email,
    required String phone,
    required String bio,
  }) async {
    final response = await _apiClient.patch<dynamic>(
      'users/me',
      data: {
        'displayName': displayName.trim(),
        'username': username.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'bio': bio.trim(),
      },
    );
    final user = User.tryParse(_apiClient.responseMap(response)['user']);
    if (user != null) return user;
    throw _invalidResponse(response, 'Không thể đọc hồ sơ vừa cập nhật.');
  }

  Future<User> updatePreferences({
    bool? showOnlineStatus,
    bool? notificationsEnabled,
  }) async {
    final data = <String, dynamic>{};
    if (showOnlineStatus != null) {
      data['showOnlineStatus'] = showOnlineStatus;
    }
    if (notificationsEnabled != null) {
      data['notificationsEnabled'] = notificationsEnabled;
    }
    final response = await _apiClient.patch<dynamic>(
      'users/me/preferences',
      data: data,
    );
    final user = User.tryParse(_apiClient.responseMap(response)['user']);
    if (user != null) return user;
    throw _invalidResponse(response, 'Không thể đọc cấu hình vừa cập nhật.');
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _apiClient.patch<dynamic>(
      'users/me/password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    _apiClient.responseMap(response);
  }

  Future<String> uploadAvatar(
    String filePath, {
    ProgressCallback? onSendProgress,
  }) async {
    final file = File(filePath);
    int length;
    try {
      length = await file.length();
    } on FileSystemException catch (error) {
      throw ApiException(
        message: 'Không thể đọc ảnh đại diện đã chọn.',
        data: error,
      );
    }
    _validateAvatarSize(length);

    final multipart = await MultipartFile.fromFile(
      filePath,
      filename: _fileName(filePath),
    );
    return _uploadMultipart(multipart, onSendProgress: onSendProgress);
  }

  Future<String> uploadAvatarBytes(
    List<int> bytes, {
    required String fileName,
    ProgressCallback? onSendProgress,
  }) async {
    _validateAvatarSize(bytes.length);
    final multipart = MultipartFile.fromBytes(bytes, filename: fileName);
    return _uploadMultipart(multipart, onSendProgress: onSendProgress);
  }

  Future<String> _uploadMultipart(
    MultipartFile multipart, {
    ProgressCallback? onSendProgress,
  }) async {
    final response = await _apiClient.post<dynamic>(
      'users/uploadAvatar',
      data: FormData.fromMap({'file': multipart}),
      onSendProgress: onSendProgress,
    );
    final avatarUrl = nullableString(
      _apiClient.responseMap(response)['avatarUrl'],
    );
    if (avatarUrl != null) return avatarUrl;
    throw _invalidResponse(response, 'Máy chủ không trả về ảnh đại diện.');
  }

  static void _validateAvatarSize(int byteLength) {
    if (byteLength <= 0) {
      throw const ApiException(message: 'Tệp ảnh đại diện đang trống.');
    }
    if (byteLength > maxAvatarBytes) {
      throw const ApiException(
        statusCode: 413,
        message: 'Ảnh đại diện không được vượt quá 1 MB.',
      );
    }
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last.trim();
    return name.isEmpty ? 'avatar' : name;
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
