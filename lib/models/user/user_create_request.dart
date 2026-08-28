class UserCreateRequest {
  final String loginId;
  final String? nickname;
  final String password;

  const UserCreateRequest({
    required this.loginId,
    this.nickname,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'loginId': loginId,
      if (nickname != null && nickname!.isNotEmpty) 'nickname': nickname,
      'password': password,
    };
  }
}
