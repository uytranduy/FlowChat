import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/json_utils.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.data,
    this.path,
  });

  factory ApiException.fromDioException(DioException exception) {
    final nested = exception.error;
    if (nested is ApiException) return nested;

    final response = exception.response;
    if (response != null) {
      return ApiException.fromResponse(response);
    }

    return ApiException(
      message: _networkMessage(exception.type),
      data: nested,
      path: exception.requestOptions.path,
    );
  }

  factory ApiException.fromResponse(Response<dynamic> response) {
    final statusCode = response.statusCode;
    return ApiException(
      statusCode: statusCode,
      message: messageFromData(
        response.data,
        fallback: statusCode == 204
            ? 'Yêu cầu đã hoàn tất.'
            : 'Yêu cầu thất bại${statusCode == null ? '' : ' ($statusCode)'}.',
      ),
      data: response.data,
      path: response.requestOptions.path,
    );
  }

  final String message;
  final int? statusCode;
  final Object? data;
  final String? path;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  static String messageFromData(Object? data, {required String fallback}) {
    if (data == null) return fallback;

    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) return fallback;

      try {
        return messageFromData(jsonDecode(text), fallback: text);
      } on FormatException {
        return text;
      }
    }

    final map = jsonMapOrNull(data);
    if (map != null) {
      for (final key in const ['message', 'error', 'detail', 'title']) {
        final value = map[key];
        final text = nullableString(value);
        if (text != null) return text;

        final nested = jsonMapOrNull(value);
        if (nested != null) {
          final nestedMessage = messageFromData(nested, fallback: '');
          if (nestedMessage.isNotEmpty) return nestedMessage;
        }
      }

      final errors = map['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = messageFromData(errors.first, fallback: '');
        if (first.isNotEmpty) return first;
      }
    }

    return fallback;
  }

  static String _networkMessage(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'Kết nối tới máy chủ đã hết thời gian chờ.';
      case DioExceptionType.connectionError:
        return 'Không thể kết nối tới máy chủ.';
      case DioExceptionType.cancel:
        return 'Yêu cầu đã bị hủy.';
      case DioExceptionType.badCertificate:
        return 'Chứng chỉ bảo mật của máy chủ không hợp lệ.';
      case DioExceptionType.badResponse:
        return 'Máy chủ trả về phản hồi không hợp lệ.';
      case DioExceptionType.unknown:
        return 'Đã xảy ra lỗi kết nối không xác định.';
    }
  }

  @override
  String toString() => message;
}
