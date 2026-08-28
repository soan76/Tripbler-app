class FindLoginIdResponse {
  final String loginId;

  const FindLoginIdResponse({required this.loginId});

  factory FindLoginIdResponse.fromJson(Map<String, dynamic> json) {
    final loginId = json['loginId'];

    if (loginId is! String || loginId.trim().isEmpty) {
      throw const FormatException('loginId 값이 올바르지 않습니다.');
    }

    return FindLoginIdResponse(loginId: loginId.trim());
  }
}
