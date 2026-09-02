class PasswordResetVerifyCodeResponse {
  const PasswordResetVerifyCodeResponse({required this.resetToken});

  final String resetToken;

  factory PasswordResetVerifyCodeResponse.fromJson(Map<String, dynamic> json) {
    final resetToken = json['resetToken'];

    if (resetToken is! String || resetToken.trim().isEmpty) {
      throw const FormatException('resetToken이 올바르지 않습니다.');
    }

    return PasswordResetVerifyCodeResponse(resetToken: resetToken);
  }
}