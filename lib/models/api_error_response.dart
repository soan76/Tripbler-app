enum ApiErrorCode {
  invalidRequest,
  invalidCredentials,
  exchangeProviderUnavailable,
  translationProviderUnavailable,
  internalServerError,
  unauthorized,
  forbidden,
  unknown;
  /// 문자열로 변환된 code를 enum으로 변환.
  /// 백엔드에서 내려주는 code가 enum에 정의되지 않은 경우 unknown으로 처리
  static ApiErrorCode fromString(String? value) {
    switch (value) {
      case 'INVALID_REQUEST':
        return ApiErrorCode.invalidRequest;
      case 'INVALID_CREDENTIALS':
        return ApiErrorCode.invalidCredentials;
      case 'EXCHANGE_PROVIDER_UNAVAILABLE':
        return ApiErrorCode.exchangeProviderUnavailable;
      case 'TRANSLATION_PROVIDER_UNAVAILABLE':
        return ApiErrorCode.translationProviderUnavailable;
      case 'INTERNAL_SERVER_ERROR':
        return ApiErrorCode.internalServerError;
      case 'UNAUTHORIZED':
        return ApiErrorCode.unauthorized;
      case 'FORBIDDEN':
        return ApiErrorCode.forbidden;
      default:
        return ApiErrorCode.unknown;
    }
  }
}

class ApiErrorResponse {
  final DateTime? timestamp;
  final int? status;
  final String? code;
  final String message;
  final String? path;

  const ApiErrorResponse({
    required this.message,
    this.timestamp,
    this.status,
    this.code,
    this.path,
  });

  /// 백엔드가 정상적으로 ErrorResponse JSON을 내려준 경우 사용.
  factory ApiErrorResponse.fromJson(Map<String, dynamic> json) {
    return ApiErrorResponse(
      timestamp: _parseDateTime(json['timestamp']),
      status: _parseInt(json['status']),
      code: _parseString(json['code']),
      message: _parseString(json['message']) ?? '요청 처리 중 오류가 발생했습니다.',
      path: _parseString(json['path']),
    );
  }

  /// 네트워크 오류, 타임아웃, JSON 파싱 실패, 502/504 HTML 응답 등
  /// 백엔드의 정상적인 ErrorResponse 형식을 받지 못한 경우 사용하는 fallback.
  factory ApiErrorResponse.unknown([String? message]) {
    return ApiErrorResponse(message: message ?? '네트워크 오류가 발생했습니다. 다시 시도해주세요.');
  }

  /// 문자열로 파싱된 code를 enum으로 변환.
  ApiErrorCode get errorCode => ApiErrorCode.fromString(code);

  bool get isUnauthorized => status == 401;

  bool get isForbidden => status == 403;

  bool get isBadRequest => status == 400;

  bool get isConflict => status == 409;

  bool get isServerError => status != null && status! >= 500;

  static DateTime? _parseDateTime(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  static int? _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return null;
  }

  static String? _parseString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }

    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApiErrorResponse &&
        other.timestamp == timestamp &&
        other.status == status &&
        other.code == code &&
        other.message == message &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(timestamp, status, code, message, path);

  @override
  String toString() {
    return 'ApiErrorResponse(status: $status, code: $code, '
        'message: $message, path: $path, timestamp: $timestamp)';
  }
}
