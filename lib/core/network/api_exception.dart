class ApiException implements Exception {
  final int? statusCode;
  final String? code;
  final String message;
  final String? path;
  final DateTime? timestamp;

  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.path,
    this.timestamp,
  });

  bool get isNetworkError => statusCode == null;

  @override
  String toString() {
    return 'ApiException(statusCode: $statusCode, code: $code, message: $message)';
  }
}
