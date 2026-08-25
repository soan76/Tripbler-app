class UserResponse {
  final int id;
  final String email;

  const UserResponse({required this.id, required this.email});

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    return UserResponse(
      id: _parseInt(json['id']),
      email: _parseRequiredString(json['email'], 'email'),
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
