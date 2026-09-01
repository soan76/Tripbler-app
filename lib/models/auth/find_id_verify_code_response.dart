class FindIdVerifyCodeResponse {
  final String loginId;

  const FindIdVerifyCodeResponse({required this.loginId});

  factory FindIdVerifyCodeResponse.fromJson(Map<String, dynamic> json) {
    final loginId = json['loginId'];

    if (loginId is! String || loginId.trim().isEmpty) {
      throw const FormatException('loginId가 올바르지 않습니다.');
    }

    return FindIdVerifyCodeResponse(loginId: loginId);
  }
}