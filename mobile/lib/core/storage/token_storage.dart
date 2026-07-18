import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _accessTokenKey = 'flowchat_access_token';
  static const String _refreshTokenKey = 'flowchat_refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> writeAccessToken(String token) {
    return _writeOrDelete(_accessTokenKey, token);
  }

  Future<void> writeRefreshToken(String token) {
    return _writeOrDelete(_refreshTokenKey, token);
  }

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    try {
      await writeAccessToken(accessToken);
      if (refreshToken != null) await writeRefreshToken(refreshToken);
    } on Object {
      await clear();
      rethrow;
    }
  }

  Future<void> clearAccessToken() => _storage.delete(key: _accessTokenKey);

  Future<void> clearRefreshToken() => _storage.delete(key: _refreshTokenKey);

  Future<void> clear() async {
    await Future.wait([clearAccessToken(), clearRefreshToken()]);
  }

  Future<void> _writeOrDelete(String key, String token) {
    final normalized = token.trim();
    if (normalized.isEmpty) return _storage.delete(key: key);
    return _storage.write(key: key, value: normalized);
  }
}
