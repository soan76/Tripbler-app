class UserLoginRequest {
  final String loginId;
  final String password;

  const UserLoginRequest({required this.loginId, required this.password});

  Map<String, dynamic> toJson() {
    return {'loginId': loginId, 'password': password};
  }
}
