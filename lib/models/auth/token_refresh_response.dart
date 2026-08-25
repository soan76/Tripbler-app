class TokenRefreshResponse {
  final String accessToken;
  final String tokenType;

  const TokenRefreshResponse({
    required this.accessToken,
    required this.tokenType,
  });

  factory TokenRefreshResponse.fromJson(Map<String, dynamic> json) {
    return TokenRefreshResponse(
      accessToken: _parseRequiredString(json['accessToken'], 'accessToken'),
      tokenType: _parseRequiredString(json['tokenType'], 'tokenType'),
    );
  }

  static String _parseRequiredString(dynamic value, String fieldName) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      throw FormatException('$fieldName 값이 없습니다.');
    }

    return text;
  }
}
