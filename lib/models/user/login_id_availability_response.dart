class LoginIdAvailabilityResponse {
  final String loginId;
  final bool available;

  const LoginIdAvailabilityResponse({
    required this.loginId,
    required this.available,
  });

  factory LoginIdAvailabilityResponse.fromJson(Map<String, dynamic> json) {
    final loginId = json['loginId'];
    final available = json['available'];

    if (loginId is! String || loginId.trim().isEmpty) {
      throw const FormatException('loginId가 올바르지 않습니다.');
    }

    if (available is! bool) {
      throw const FormatException('available 값이 올바르지 않습니다.');
    }

    return LoginIdAvailabilityResponse(loginId: loginId, available: available);
  }
}
