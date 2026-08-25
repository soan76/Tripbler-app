class TokenRefreshRequest {
  final String refreshToken;

  const TokenRefreshRequest({required this.refreshToken});

  Map<String, dynamic> toJson() {
    return {'refreshToken': refreshToken};
  }
}
