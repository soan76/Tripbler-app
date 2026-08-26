import '../../models/auth/token_refresh_request.dart';
import '../../models/auth/token_refresh_response.dart';
import '../../models/auth/user_login_request.dart';
import '../../models/auth/user_login_response.dart';
import '../../services/auth/auth_api_service.dart';
import '../../services/auth/token_storage_service.dart';
import '../../models/user/user_create_request.dart';
import '../../models/user/user_response.dart';
import '../../models/user/login_id_availability_response.dart'; 

/// 인증 API와 로컬 토큰 저장소를 연결하는 Repository.
///
/// 담당 기능:
/// - 로그인
/// - Access Token 재발급
/// - 로그아웃
/// - 저장된 토큰 조회
/// - 로그인 상태 확인
class AuthRepository {
  AuthRepository({
    AuthApiService? authApiService,
    TokenStorageService? tokenStorageService,
  }) : _authApiService = authApiService ?? AuthApiService(),
       _tokenStorageService = tokenStorageService ?? TokenStorageService();

  final AuthApiService _authApiService;
  final TokenStorageService _tokenStorageService;

  /// 회원가입
  Future<UserResponse> signup({
    required String loginId,
    required String nickname,
    required String email,
    required String password,
  }) async {
    final request = UserCreateRequest(
      loginId: loginId,
      nickname: nickname,
      email: email,
      password: password,
    );

    return _authApiService.signup(request);
  }

  /// 아이디 사용 가능 여부 확인
  Future<LoginIdAvailabilityResponse> checkLoginIdAvailability(String loginId) {
    return _authApiService.checkLoginIdAvailability(loginId);
  }

  /// 로그인
  ///
  /// 1. 백엔드 로그인 API 호출
  /// 2. Access Token / Refresh Token / Token Type 저장
  /// 3. 로그인 응답 반환
  Future<UserLoginResponse> login({
    required String loginId,
    required String password,
  }) async {
    final request = UserLoginRequest(loginId: loginId, password: password);

    final response = await _authApiService.login(request);

    await _tokenStorageService.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      tokenType: response.tokenType,
    );

    return response;
  }

  /// Refresh Token을 이용해 Access Token 재발급
  ///
  /// 저장된 Refresh Token을 읽은 뒤
  /// 백엔드 Refresh API를 호출하고 새 Access Token을 저장한다.
  Future<TokenRefreshResponse> refreshAccessToken() async {
    final refreshToken = await _tokenStorageService.readRefreshToken();

    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthSessionException('저장된 Refresh Token이 없습니다.');
    }

    final request = TokenRefreshRequest(refreshToken: refreshToken);

    final response = await _authApiService.refresh(request);

    await _tokenStorageService.saveAccessToken(
      accessToken: response.accessToken,
      tokenType: response.tokenType,
    );

    return response;
  }

  Future<UserResponse> getCurrentUser() async {
    final authorizationHeader = await _tokenStorageService
        .readAuthorizationHeader();

    if (authorizationHeader == null || authorizationHeader.isEmpty) {
      throw const AuthSessionException('저장된 Access Token이 없습니다.');
    }

    return _authApiService.getCurrentUser(
      authorizationHeader: authorizationHeader,
    );
  }

  /// 로그아웃
  ///
  /// 서버 로그아웃 API를 호출한 뒤
  /// 기기에 저장된 인증 토큰을 삭제한다.
  Future<void> logout() async {
    final authorizationHeader = await _tokenStorageService
        .readAuthorizationHeader();

    try {
      if (authorizationHeader != null && authorizationHeader.isNotEmpty) {
        await _authApiService.logout(authorizationHeader: authorizationHeader);
      }
    } finally {
      // 서버 로그아웃 호출 성공 여부와 관계없이
      // 기기의 인증 토큰은 제거한다.
      await _tokenStorageService.clearTokens();
    }
  }

  /// Access Token 조회
  Future<String?> readAccessToken() {
    return _tokenStorageService.readAccessToken();
  }

  /// Refresh Token 조회
  Future<String?> readRefreshToken() {
    return _tokenStorageService.readRefreshToken();
  }

  /// API Authorization 헤더 값 조회
  Future<String?> readAuthorizationHeader() {
    return _tokenStorageService.readAuthorizationHeader();
  }

  /// 기기에 Access Token / Refresh Token이 모두 저장되어 있는지 확인
  Future<bool> hasTokens() {
    return _tokenStorageService.hasTokens();
  }

  /// 저장된 토큰 전체 삭제
  Future<void> clearTokens() {
    return _tokenStorageService.clearTokens();
  }

  void dispose() {
    _authApiService.dispose();
  }
}

/// 로컬 인증 세션 자체에 문제가 있을 때 사용하는 예외.
class AuthSessionException implements Exception {
  final String message;

  const AuthSessionException(this.message);

  @override
  String toString() => message;
}
