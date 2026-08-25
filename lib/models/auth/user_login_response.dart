class UserLoginResponse {
  final int id;
  final String email;
  final String accessToken;
  final String refreshToken;
  final String tokenType;

  const UserLoginResponse({
    required this.id,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
  });
  
  factory UserLoginResponse.fromJson(Map<String, dynamic> json) {
    return UserLoginResponse(
      id: _parseInt(json['id']),
      email: _parseRequiredString(json['email'], 'email'),
      accessToken: _parseRequiredString(json['accessToken'], 'accessToken'),
      refreshToken: _parseRequiredString(json['refreshToken'], 'refreshToken'),
      tokenType: _parseRequiredString(json['tokenType'], 'tokenType'),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    final parsed = int.tryParse(value?.toString() ?? '');

    if (parsed == null) {
      throw const FormatException('id 값이 올바르지 않습니다.');
    }

    return parsed;
  }

  static String _parseRequiredString(dynamic value, String fieldName) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      throw FormatException('$fieldName 값이 없습니다.');
    }

    return text;
  }
}
