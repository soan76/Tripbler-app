import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  GoogleAuthService();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_SERVER_CLIENT_ID',
  );

  bool _isInitialized = false;

  // Google Sign-In을 서버용 Web Client ID로 한 번만 초기화한다.
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    if (_serverClientId.isEmpty) {
      throw const GoogleAuthException(
        'Google OAuth Server Client ID가 설정되지 않았습니다.',
      );
    }

    await _googleSignIn.initialize(serverClientId: _serverClientId);

    _isInitialized = true;
  }

  // Google 로그인을 진행하고 백엔드 검증에 사용할 ID Token을 반환한다.
  Future<String> signInAndGetIdToken() async {
    await initialize();

    try {
      final account = await _googleSignIn.authenticate();

      final idToken = account.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const GoogleAuthException('Google ID Token을 가져오지 못했습니다.');
      }

      return idToken;
    } on GoogleSignInException catch (error) {
      throw GoogleAuthException('Google 로그인에 실패했습니다: ${error.code}');
    }
  }

  Future<void> signOut() {
    return _googleSignIn.signOut();
  }
}

class GoogleAuthException implements Exception {
  final String message;

  const GoogleAuthException(this.message);

  @override
  String toString() => message;
}