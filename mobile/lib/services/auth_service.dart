import 'package:google_sign_in/google_sign_in.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/utils/json_utils.dart';
import '../models/user.dart';

class AuthService {
  AuthService(this._apiClient);

  final ApiClient _apiClient;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;

  Future<String> signUp({
    required String username,
    required String password,
    required String email,
    required String firstName,
    required String lastName,
  }) async {
    final response = await _apiClient.post<dynamic>(
      'auth/signup',
      data: {
        'username': username.trim(),
        'password': password,
        'email': email.trim(),
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
      },
      options: _apiClient.publicOptions(),
    );
    final body = _apiClient.responseMap(response);
    return nullableString(body['message']) ??
        'Đăng ký thành công. Vui lòng kiểm tra email để xác minh tài khoản.';
  }

  Future<String> requestPasswordReset(String email) async {
    final response = await _apiClient.post<dynamic>(
      'auth/forgot-password',
      data: {'email': email.trim()},
      options: _apiClient.publicOptions(),
    );
    final body = _apiClient.responseMap(response);
    return nullableString(body['message']) ??
        'Nếu email tồn tại, FlowChat đã gửi liên kết đặt lại mật khẩu.';
  }

  Future<String> resendVerification(String email) async {
    final response = await _apiClient.post<dynamic>(
      'auth/resend-verification',
      data: {'email': email.trim()},
      options: _apiClient.publicOptions(),
    );
    final body = _apiClient.responseMap(response);
    return nullableString(body['message']) ??
        'Nếu email đang chờ xác minh, FlowChat đã gửi một liên kết mới.';
  }

  Future<String> signIn({
    required String username,
    required String password,
  }) async {
    final response = await _apiClient.post<dynamic>(
      'auth/signin',
      data: {'username': username.trim(), 'password': password},
      options: _apiClient.publicOptions(),
    );
    await _apiClient.saveSignInSession(response);

    final token = nullableString(
      _apiClient.responseMap(response)['accessToken'],
    );
    if (token == null) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Đăng nhập thành công nhưng access token không hợp lệ.',
        data: response.data,
        path: response.requestOptions.path,
      );
    }
    return token;
  }

  Future<void> signInWithGoogle() async {
    final clientId = AppConfig.googleWebClientId.trim();
    if (clientId.isEmpty) {
      throw const ApiException(
        message: 'Thiếu GOOGLE_WEB_CLIENT_ID. Hãy chạy app với --dart-define.',
      );
    }

    try {
      if (!_googleInitialized) {
        await _googleSignIn.initialize(serverClientId: clientId);
        _googleInitialized = true;
      }
      if (!_googleSignIn.supportsAuthenticate()) {
        throw const ApiException(
          message: 'Thiết bị này không hỗ trợ đăng nhập Google trực tiếp.',
        );
      }

      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken?.trim();
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException(
          message: 'Google không trả về ID token. Hãy kiểm tra Web Client ID.',
        );
      }

      final response = await _apiClient.post<dynamic>(
        'auth/google',
        data: {'idToken': idToken},
        options: _apiClient.publicOptions(),
      );
      await _apiClient.saveSignInSession(response);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const ApiException(message: 'Bạn đã hủy đăng nhập Google.');
      }
      throw ApiException(
        message: error.description?.trim().isNotEmpty == true
            ? error.description!.trim()
            : 'Không thể đăng nhập bằng Google.',
        data: error,
      );
    }
  }

  Future<String> refreshAccessToken() => _apiClient.refreshAccessToken();

  Future<void> signOut() async {
    try {
      final response = await _apiClient.post<dynamic>(
        'auth/signout',
        options: _apiClient.refreshCookieOptions(skipBearer: true),
      );
      _apiClient.responseMap(response);
    } finally {
      if (_googleInitialized) {
        try {
          await _googleSignIn.signOut();
        } catch (_) {
          // Phiên FlowChat vẫn phải được xóa nếu Google Play Services lỗi.
        }
      }
      await _apiClient.clearSession();
    }
  }

  Future<bool> hasSession() => _apiClient.hasSession();

  Future<void> clearLocalSession() => _apiClient.clearSession();

  Future<User> getMe() async {
    final response = await _apiClient.get<dynamic>('users/me');
    final body = _apiClient.responseMap(response);
    final user = User.tryParse(body['user']);
    if (user != null) return user;
    throw ApiException(
      statusCode: response.statusCode,
      message: 'Không thể đọc thông tin người dùng.',
      data: response.data,
      path: response.requestOptions.path,
    );
  }

  Future<User> fetchMe() => getMe();
}
