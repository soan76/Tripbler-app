class UserLoginRequest {
  final String email;
  final String password;

  const UserLoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() {
    return {'email': email, 'password': password};
  }
}
