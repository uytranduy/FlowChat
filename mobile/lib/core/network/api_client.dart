import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import '../utils/json_utils.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({Dio? dio, TokenStorage? tokenStorage, String? baseUrl})
    : tokenStorage = tokenStorage ?? TokenStorage(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _normalizeBaseUrl(
                baseUrl ?? AppConfig.normalizedApiBaseUrl,
              ),
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: const {'Accept': 'application/json'},
            ),
          ) {
    if (dio != null) {
      _dio.options.baseUrl = _normalizeBaseUrl(
        baseUrl ??
            (_dio.options.baseUrl.isEmpty
                ? AppConfig.normalizedApiBaseUrl
                : _dio.options.baseUrl),
      );
    }
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  static const String _skipBearerKey = 'flowchat.skipBearer';
  static const String _skipRefreshKey = 'flowchat.skipRefresh';
  static const String _sendRefreshCookieKey = 'flowchat.sendRefreshCookie';
  static const String _retriedKey = 'flowchat.authRetried';

  final Dio _dio;
  final TokenStorage tokenStorage;

  Future<String?>? _refreshInFlight;

  Dio get dio => _dio;

  Options publicOptions({bool sendRefreshCookie = false}) => Options(
    extra: {
      _skipBearerKey: true,
      _skipRefreshKey: true,
      if (sendRefreshCookie) _sendRefreshCookieKey: true,
    },
  );

  Options refreshCookieOptions({bool skipBearer = false}) => Options(
    extra: {
      if (skipBearer) _skipBearerKey: true,
      _skipRefreshKey: true,
      _sendRefreshCookieKey: true,
    },
  );

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return request<T>(
      path,
      method: 'GET',
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) {
    return request<T>(
      path,
      method: 'POST',
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
  }

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return request<T>(
      path,
      method: 'PATCH',
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> request<T>(
    String path, {
    required String method,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      return await _dio.request<T>(
        _relativePath(path),
        data: data,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
  }) {
    return tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<void> saveSignInSession(Response<dynamic> response) async {
    final body = responseMap(response);
    final accessToken = nullableString(body['accessToken']);
    if (accessToken == null) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Phản hồi đăng nhập không chứa access token.',
        data: response.data,
        path: response.requestOptions.path,
      );
    }

    final refreshToken = refreshTokenFromHeaders(response.headers);
    if (refreshToken == null) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Phản hồi đăng nhập không chứa refresh token.',
        data: response.data,
        path: response.requestOptions.path,
      );
    }

    await saveSession(accessToken: accessToken, refreshToken: refreshToken);
  }

  Future<String> refreshAccessToken() async {
    final token = await _refreshAccessTokenShared();
    if (token != null) return token;
    throw const ApiException(
      statusCode: 401,
      message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
    );
  }

  Future<bool> hasSession() async {
    final values = await Future.wait([
      tokenStorage.readAccessToken(),
      tokenStorage.readRefreshToken(),
    ]);
    return values.every((value) => value != null && value.trim().isNotEmpty);
  }

  Future<void> clearSession() => tokenStorage.clear();

  JsonMap responseMap(Response<dynamic> response) {
    final data = response.data;
    if (response.statusCode == 204 || data == null || data == '') {
      return const <String, dynamic>{};
    }
    final map = jsonMapOrNull(data);
    if (map != null) return map;
    throw ApiException(
      statusCode: response.statusCode,
      message: 'Máy chủ trả về dữ liệu không đúng định dạng.',
      data: data,
      path: response.requestOptions.path,
    );
  }

  String? refreshTokenFromHeaders(Headers headers) {
    final cookieHeaders = <String>[];
    for (final entry in headers.map.entries) {
      if (entry.key.toLowerCase() == 'set-cookie') {
        cookieHeaders.addAll(entry.value);
      }
    }

    final pattern = RegExp(
      r'(?:^|[,;]\s*)refreshToken=([^;,\s]+)',
      caseSensitive: false,
    );
    for (final header in cookieHeaders) {
      final encoded = pattern.firstMatch(header)?.group(1);
      if (encoded == null || encoded.isEmpty) continue;
      try {
        return Uri.decodeComponent(encoded);
      } on FormatException {
        return encoded;
      }
    }
    return null;
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      if (options.extra[_skipBearerKey] != true) {
        final accessToken = await tokenStorage.readAccessToken();
        if (accessToken != null && accessToken.trim().isNotEmpty) {
          options.headers['Authorization'] = 'Bearer ${accessToken.trim()}';
        }
      }

      if (options.extra[_sendRefreshCookieKey] == true) {
        final refreshToken = await tokenStorage.readRefreshToken();
        if (refreshToken != null && refreshToken.trim().isNotEmpty) {
          options.headers['Cookie'] = _mergeRefreshCookie(
            options.headers['Cookie']?.toString(),
            refreshToken.trim(),
          );
        }
      }
      handler.next(options);
    } catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
          stackTrace: stackTrace,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    if (!_isAuthenticationFailure(error) ||
        request.extra[_skipRefreshKey] == true ||
        request.extra[_retriedKey] == true) {
      handler.next(error);
      return;
    }

    request.extra[_retriedKey] = true;
    try {
      final accessToken = await _refreshAccessTokenShared();
      if (accessToken == null) {
        await clearSession();
        handler.next(error);
        return;
      }

      request.headers['Authorization'] = 'Bearer $accessToken';
      final response = await _dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException catch (retryError) {
      if (_isAuthenticationFailure(retryError)) await clearSession();
      handler.next(retryError);
    } on Object {
      handler.next(error);
    }
  }

  bool _isAuthenticationFailure(DioException error) {
    final status = error.response?.statusCode;
    if (status != 401 && status != 403) return false;

    final path = error.requestOptions.path.toLowerCase();
    if (path.contains('auth/signin') ||
        path.contains('auth/signup') ||
        path.contains('auth/refresh') ||
        path.contains('auth/signout')) {
      return false;
    }

    if (status == 401) return true;

    final message = ApiException.messageFromData(
      error.response?.data,
      fallback: '',
    ).toLowerCase();
    return message.contains('access token') ||
        message.contains('jwt') ||
        message.contains('token hết hạn');
  }

  Future<String?> _refreshAccessTokenShared() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    late final Future<String?> refresh;
    refresh = _performRefresh().whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
    _refreshInFlight = refresh;
    return refresh;
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.trim().isEmpty) return null;

    try {
      final response = await _dio.post<dynamic>(
        'auth/refresh',
        options: refreshCookieOptions(skipBearer: true),
      );
      final accessToken = nullableString(responseMap(response)['accessToken']);
      if (accessToken == null) return null;
      await tokenStorage.writeAccessToken(accessToken);
      return accessToken;
    } on DioException {
      return null;
    } on ApiException {
      return null;
    }
  }

  static String _mergeRefreshCookie(String? existing, String refreshToken) {
    final cookies = (existing ?? '')
        .split(';')
        .map((item) => item.trim())
        .where(
          (item) =>
              item.isNotEmpty &&
              !item.toLowerCase().startsWith('refreshtoken='),
        )
        .toList();
    cookies.add('refreshToken=$refreshToken');
    return cookies.join('; ');
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim();
    final fallback = AppConfig.defaultApiBaseUrl;
    final result = normalized.isEmpty ? fallback : normalized;
    return result.endsWith('/') ? result : '$result/';
  }

  static String _relativePath(String value) {
    var path = value.trim();
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path;
  }
}
