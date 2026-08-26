class UserCreateRequest {
  final String loginId;
  final String nickname;
  final String email;
  final String password;

  const UserCreateRequest({
    required this.loginId,
    required this.nickname,
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'loginId': loginId,
      'nickname': nickname,
      'email': email,
      'password': password,
    };
  }
}
