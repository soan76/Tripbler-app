import '../../core/network/api_exception.dart';
import '../../models/auth/token_refresh_request.dart';
import '../../models/auth/token_refresh_response.dart';
import '../../models/auth/user_login_request.dart';
import '../../models/auth/user_login_response.dart';
import '../../models/auth/social_account_status_response.dart';
import '../../models/user/login_id_availability_response.dart';
import '../../models/user/user_create_request.dart';
import '../../models/user/user_response.dart';
import '../../services/auth/auth_api_service.dart';
import '../../services/auth/google_auth_service.dart';
import '../../services/auth/token_storage_service.dart';

import 'package:flutter/foundation.dart';

/// 인증 API와 로컬 토큰 저장소를 연결하는 Repository.
///
/// 담당 기능:
/// - 회원가입 / 로그인
/// - Google 계정 연동
/// - Access Token 재발급 / 로그아웃
/// - 저장된 인증 토큰 관리
class AuthRepository {
  AuthRepository({
    AuthApiService? authApiService,
    TokenStorageService? tokenStorageService,
    GoogleAuthService? googleAuthService,
  }) : _authApiService = authApiService ?? AuthApiService(),
       _tokenStorageService = tokenStorageService ?? TokenStorageService(),
       _googleAuthService = googleAuthService ?? GoogleAuthService();

  final AuthApiService _authApiService;
  final TokenStorageService _tokenStorageService;
  final GoogleAuthService _googleAuthService;

  /// 회원가입
  Future<UserResponse> signup({
    required String loginId,
    String? nickname,
    required String password,
  }) async {
    final request = UserCreateRequest(
      loginId: loginId,
      nickname: nickname,
      password: password,
    );

    return _authApiService.signup(request);
  }

  /// 아이디 사용 가능 여부 확인
  Future<LoginIdAvailabilityResponse> checkLoginIdAvailability(String loginId) {
    return _authApiService.checkLoginIdAvailability(loginId);
  }

  /// 아이디 찾기 인증코드를 이메일로 전송한다.
  ///
  /// 로그인하지 않은 사용자도 사용하는 공개 인증 API이므로
  /// Access Token은 사용하지 않는다.
  Future<void> sendFindIdVerificationCode({required String email}) {
    return _authApiService.sendFindIdVerificationCode(email: email);
  }

  /// 아이디 찾기 인증코드를 검증하고 loginId를 반환한다.
  ///
  /// 로그인하지 않은 사용자도 사용하는 공개 인증 API이므로
  /// Access Token은 사용하지 않는다.
  Future<String> verifyFindIdVerificationCode({
    required String email,
    required String code,
  }) async {
    final response = await _authApiService.verifyFindIdVerificationCode(
      email: email,
      code: code,
    );

    return response.loginId;
  }

  /// 로그인
  ///
  /// 백엔드 로그인 후 Access / Refresh Token을 로컬에 저장한다.
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

  /// Google 인증 후 현재 Tripbler 사용자 계정에 연동한다.
  Future<void> linkGoogleAccount() async {
    final idToken = await _googleAuthService.signInAndGetIdToken();

    await _requestWithTokenRetry<void>((authorizationHeader) {
      return _authApiService.linkGoogleAccount(
        authorizationHeader: authorizationHeader,
        idToken: idToken,
      );
    });
  }

  /// 현재 사용자에게 연동된 Google 계정을 해제한다.
  Future<void> unlinkGoogleAccount() {
    return _requestWithTokenRetry<void>((authorizationHeader) {
      return _authApiService.unlinkGoogleAccount(
        authorizationHeader: authorizationHeader,
      );
    });
  }

  /// Refresh Token을 이용해 Access Token을 재발급한다.
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

  /// 현재 사용자의 소셜 계정 연동 상태를 조회한다.
  Future<SocialAccountStatusResponse> getLinkedSocialAccounts() {
    return _requestWithTokenRetry<SocialAccountStatusResponse>((
      authorizationHeader,
    ) {
      return _authApiService.getLinkedSocialAccounts(
        authorizationHeader: authorizationHeader,
      );
    });
  }

  /// 서버 로그아웃 후 로컬 인증 토큰을 삭제한다.
  Future<void> logout() async {
    final authorizationHeader = await _tokenStorageService
        .readAuthorizationHeader();

    try {
      if (authorizationHeader != null && authorizationHeader.isNotEmpty) {
        await _authApiService.logout(authorizationHeader: authorizationHeader);
      }
    } finally {
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

  /// Access Token / Refresh Token 저장 여부 확인
  Future<bool> hasTokens() {
    return _tokenStorageService.hasTokens();
  }

  /// 저장된 토큰 전체 삭제
  Future<void> clearTokens() {
    return _tokenStorageService.clearTokens();
  }

  /// 인증 API가 401을 반환하면 Access Token을 재발급하고 한 번 재시도한다.
  Future<T> _requestWithTokenRetry<T>(
    Future<T> Function(String authorizationHeader) request,
  ) async {
    var authorizationHeader = await _tokenStorageService
        .readAuthorizationHeader();

    if (authorizationHeader == null || authorizationHeader.isEmpty) {
      throw const AuthSessionException('저장된 Access Token이 없습니다.');
    }

    try {
      return await request(authorizationHeader);
    } on ApiException catch (error) {
      if (error.statusCode != 401) {
        rethrow;
      }

      debugPrint('Access Token 만료 → 재발급 시도');

      await refreshAccessToken();

      debugPrint('Access Token 재발급 성공 → 기존 요청 재시도');

      authorizationHeader = await _tokenStorageService
          .readAuthorizationHeader();

      if (authorizationHeader == null || authorizationHeader.isEmpty) {
        throw const AuthSessionException('Access Token 재발급에 실패했습니다.');
      }

      return request(authorizationHeader);
    }
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