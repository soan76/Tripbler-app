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

  factory ApiErrorResponse.fromJson(Map<String, dynamic> json) {
    return ApiErrorResponse(
      timestamp: _parseDateTime(json['timestamp']),
      status: _parseInt(json['status']),
      code: json['code'] as String?,
      message: json['message'] as String? ?? '요청 처리 중 오류가 발생했습니다.',
      path: json['path'] as String?,
    );
  }

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
}
