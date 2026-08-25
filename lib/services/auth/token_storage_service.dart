import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Access Token / Refresh Token을
/// 기기의 보안 저장소에 저장하고 관리하는 서비스.
class TokenStorageService {
  TokenStorageService({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _secureStorage;

  static const String _accessTokenKey = 'auth_access_token';
  static const String _refreshTokenKey = 'auth_refresh_token';
  static const String _tokenTypeKey = 'auth_token_type';

  /// 로그인 성공 시 토큰 전체 저장
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String tokenType,
  }) async {
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: accessToken),
      _secureStorage.write(key: _refreshTokenKey, value: refreshToken),
      _secureStorage.write(key: _tokenTypeKey, value: tokenType),
    ]);
  }

  /// Access Token 재발급 시 Access Token만 갱신
  Future<void> saveAccessToken({
    required String accessToken,
    String? tokenType,
  }) async {
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: accessToken),
      if (tokenType != null)
        _secureStorage.write(key: _tokenTypeKey, value: tokenType),
    ]);
  }

  Future<String?> readAccessToken() {
    return _secureStorage.read(key: _accessTokenKey);
  }

  Future<String?> readRefreshToken() {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  Future<String?> readTokenType() {
    return _secureStorage.read(key: _tokenTypeKey);
  }

  /// Authorization 헤더 값 생성
  ///
  /// 예:
  /// Bearer eyJhbGciOi...
  Future<String?> readAuthorizationHeader() async {
    final accessToken = await readAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    final tokenType = await readTokenType();

    final scheme = tokenType == null || tokenType.isEmpty
        ? 'Bearer'
        : tokenType;

    return '$scheme $accessToken';
  }

  /// Access Token과 Refresh Token이 모두 존재하는지 확인
  Future<bool> hasTokens() async {
    final accessToken = await readAccessToken();
    final refreshToken = await readRefreshToken();

    return accessToken != null &&
        accessToken.isNotEmpty &&
        refreshToken != null &&
        refreshToken.isNotEmpty;
  }

  /// 로그아웃 또는 인증 만료 시 토큰 전체 삭제
  Future<void> clearTokens() async {
    await Future.wait([
      _secureStorage.delete(key: _accessTokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _tokenTypeKey),
    ]);
  }
}
