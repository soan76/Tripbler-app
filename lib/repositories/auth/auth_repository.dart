import 'dart:async';

import '../../core/network/api_exception.dart';
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

import 'auth_exceptions.dart';
import 'auth_token_refresher.dart';
import 'auth_token_session.dart';

export 'auth_exceptions.dart';

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
       _session = AuthTokenSession(
         tokenStorageService ?? TokenStorageService(),
       ),
       _googleAuthService = googleAuthService ?? GoogleAuthService();

  final AuthApiService _authApiService;
  final GoogleAuthService _googleAuthService;

  /// 세션 번호와 토큰 저장소 순차 경로. 모든 토큰 작업은 이 객체 하나를 거친다.
  final AuthTokenSession _session;

  /// 세션별 Access Token 재발급. [_session]의 순차 경로를 함께 쓴다.
  late final AuthTokenRefresher _refresher = AuthTokenRefresher(
    session: _session,
    authApiService: _authApiService,
  );

  /// 로그인 세션 번호([AuthTokenSession.sessionId]).
  int get sessionId => _session.sessionId;

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

  /// 비밀번호 재설정 인증코드를 이메일로 전송한다.
  Future<void> sendPasswordResetVerificationCode({
    required String loginId,
    required String email,
  }) {
    return _authApiService.sendPasswordResetVerificationCode(
      loginId: loginId,
      email: email,
    );
  }

  /// 비밀번호 재설정 인증코드를 검증하고 resetToken을 반환한다.
  Future<String> verifyPasswordResetVerificationCode({
    required String loginId,
    required String email,
    required String code,
  }) async {
    final response = await _authApiService.verifyPasswordResetVerificationCode(
      loginId: loginId,
      email: email,
      code: code,
    );

    return response.resetToken;
  }

  /// resetToken을 사용해 새 비밀번호로 변경한다.
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) {
    return _authApiService.resetPassword(
      resetToken: resetToken,
      newPassword: newPassword,
    );
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

    // 인증에 성공한 뒤 새 토큰을 반영하기 직전에 세션을 바꾼다.
    // 같은 순차 경로 안에서 번호 변경과 저장을 함께 처리한다.
    await _session.startSession(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      tokenType: response.tokenType,
    );

    return response;
  }

  /// Google 인증 후 현재 Tripbler 사용자 계정에 연동한다.
  Future<void> linkGoogleAccount() async {
    final idToken = await _googleAuthService.signInAndGetIdToken();

    await authorizedRequest<void>((authorizationHeader) {
      return _authApiService.linkGoogleAccount(
        authorizationHeader: authorizationHeader,
        idToken: idToken,
      );
    });
  }

  /// 현재 사용자에게 연동된 Google 계정을 해제한다.
  Future<void> unlinkGoogleAccount() {
    return authorizedRequest<void>((authorizationHeader) {
      return _authApiService.unlinkGoogleAccount(
        authorizationHeader: authorizationHeader,
      );
    });
  }

  /// 현재 세션의 Access Token을 재발급하고 새 Authorization 헤더를 돌려준다.
  ///
  /// 같은 세션에서 이미 재발급이 진행 중이면 그 결과를 함께 쓴다.
  Future<String> refreshAccessToken() async {
    final session = await _session.readSessionAuth();

    return _refresher.refreshForSession(session.sessionId, failedHeader: null);
  }

  /// 현재 로그인 사용자 정보를 조회한다.
  ///
  /// Access Token이 만료되어 401이 반환되면 토큰을 재발급한 뒤
  /// 사용자 조회 요청을 한 번 다시 시도한다.
  Future<UserResponse> getCurrentUser() {
    return authorizedRequest<UserResponse>((authorizationHeader) {
      return _authApiService.getCurrentUser(
        authorizationHeader: authorizationHeader,
      );
    });
  }

  /// 현재 로그인 사용자의 닉네임을 변경한다.
  ///
  /// Access Token이 만료되어 401이 반환되면 토큰을 재발급한 뒤
  /// 닉네임 변경 요청을 한 번 다시 시도한다.
  Future<UserResponse> updateNickname({required String nickname}) {
    return authorizedRequest<UserResponse>((authorizationHeader) {
      return _authApiService.updateNickname(
        authorizationHeader: authorizationHeader,
        nickname: nickname,
      );
    });
  }

  /// 현재 로그인 사용자의 프로필 이미지를 변경한다.
  ///
  /// Access Token이 만료되어 401이 반환되면 토큰을 재발급한 뒤
  /// 이미지 변경 요청을 한 번 다시 시도한다.
  Future<UserResponse> updateProfileImage({required String filePath}) {
    return authorizedRequest<UserResponse>((authorizationHeader) {
      return _authApiService.updateProfileImage(
        authorizationHeader: authorizationHeader,
        filePath: filePath,
      );
    });
  }

  /// 현재 로그인 사용자의 프로필 이미지를 삭제한다.
  ///
  /// Access Token이 만료되어 401이 반환되면 토큰을 재발급한 뒤
  /// 이미지 삭제 요청을 한 번 다시 시도한다.
  Future<void> deleteProfileImage() {
    return authorizedRequest<void>((authorizationHeader) {
      return _authApiService.deleteProfileImage(
        authorizationHeader: authorizationHeader,
      );
    });
  }

  /// 현재 사용자의 소셜 계정 연동 상태를 조회한다.
  Future<SocialAccountStatusResponse> getLinkedSocialAccounts() {
    return authorizedRequest<SocialAccountStatusResponse>((
      authorizationHeader,
    ) {
      return _authApiService.getLinkedSocialAccounts(
        authorizationHeader: authorizationHeader,
      );
    });
  }

  /// 현재 로그인 사용자의 계정을 삭제한다.
  /// 서버 계정 삭제가 성공한 뒤 로컬 Access / Refresh Token도 제거한다.
  Future<void> deleteAccount() async {
    final sessionId = _session.sessionId;

    // 탈퇴 요청 중 세션이 바뀌면 authorizedRequest가 SessionChangedException을 던진다.
    await authorizedRequest<void>((authorizationHeader) {
      return _authApiService.deleteAccount(
        authorizationHeader: authorizationHeader,
      );
    });

    try {
      // 공통 세션 종료 경로. 탈퇴한 세션일 때만 토큰을 지우고 번호를 한 번 바꾼다.
      await clearTokensIfSession(sessionId);
    } catch (error) {
      debugPrint('계정 탈퇴 후 로컬 토큰 삭제 실패: $error');
    }
  }

  /// 로그아웃(로컬 우선).
  ///
  /// 연결이 불안정해도 바로 끝나도록 로컬 세션을 먼저 끝낸다. 순차 경로 안에서
  /// 이 기기의 Refresh Token을 읽고, 세션 번호를 바꾸고, 로컬 토큰을 지운다.
  /// 서버 로그아웃은 그 뒤에 따로 보내며(Access Token 없이 Refresh Token 본문) 결과를
  /// 기다리지 않고 실패도 무시한다. 서버는 그 Refresh Token과 일치하는 토큰만 폐기하므로,
  /// 요청이 늦게 도착해도 그 사이 같은 계정으로 다시 로그인한 세션의 토큰은 지우지 않는다.
  /// 로컬 삭제가 늦게 끝나는 일도 없어 이후 로그인한 계정의 로컬 토큰을 지우지 않는다.
  ///
  /// 로컬 토큰 삭제가 실패하면 한 번 더 시도한다. 그래도 실패하면 서버 로그아웃은
  /// 그대로 보내 서버 세션을 끝낸 뒤 삭제 오류를 던져 호출부가 사용자에게 알리게 한다.
  Future<void> logout() async {
    // 순차 경로 안에서 Refresh Token 읽기 → 세션 번호 변경 → 로컬 토큰 삭제(실패 시 1회 재시도).
    final local = await _session.endSessionForLogout();

    _sendServerLogout(local.refreshToken);

    final error = local.clearError;

    if (error != null) {
      Error.throwWithStackTrace(
        error,
        local.clearStackTrace ?? StackTrace.current,
      );
    }
  }

  /// 서버 로그아웃을 기다리지 않고 보낸다(Access Token 없이 Refresh Token 본문). 실패는 기록만 한다.
  void _sendServerLogout(String? refreshToken) {
    if (refreshToken == null || refreshToken.isEmpty) {
      return;
    }

    unawaited(
      _authApiService
          .logout(refreshToken: refreshToken)
          .then<void>(
            (_) {},
            onError: (Object error) {
              debugPrint('서버 로그아웃 실패(로컬 로그아웃은 완료): $error');
            },
          ),
    );
  }

  /// Access Token 조회
  Future<String?> readAccessToken() {
    return _session.readAccessToken();
  }

  /// Refresh Token 조회
  Future<String?> readRefreshToken() {
    return _session.readRefreshToken();
  }

  /// API Authorization 헤더 값 조회
  Future<String?> readAuthorizationHeader() {
    return _session.readAuthorizationHeader();
  }

  /// Access Token / Refresh Token 저장 여부 확인
  Future<bool> hasTokens() {
    return _session.hasTokens();
  }

  /// 현재 세션을 끝내고 저장된 토큰을 모두 지운다(세션 번호 한 번 변경).
  Future<void> clearTokens() {
    return _session.clearTokens();
  }

  /// [sessionId] 세션이 아직 현재 세션일 때만 끝내고 토큰을 지운다.
  ///
  /// 세션 만료 처리나 탈퇴처럼 늦게 끝날 수 있는 작업이 그 사이 로그인한
  /// 다른 계정의 토큰을 지우지 않게 한다. 지웠으면 true.
  /// 저장소 삭제가 실패하면 [TokenClearException]을 던진다.
  Future<bool> clearTokensIfSession(int sessionId) {
    return _session.clearTokensIfSession(sessionId);
  }

  /// 저장된 Access Token으로 [request]를 실행한다.
  /// 401을 받으면 Access Token을 재발급하고 한 번만 다시 시도한다.
  ///
  /// 회원 API와 장소 검색처럼 로그인이 필요한 요청이 함께 쓴다.
  /// 요청을 시작할 때의 세션 번호를 기준으로 다음 시점에 세션이 그대로인지 확인한다.
  /// - 최초 토큰을 읽은 뒤 첫 전송 직전
  /// - 재발급과 토큰 읽기를 마친 뒤 재전송 직전
  /// - 응답(성공·실패)을 돌려주기 직전
  /// 세션이 바뀌었으면 결과 대신 [SessionChangedException]을 던진다.
  /// 이미 보낸 요청은 되돌릴 수 없지만, 그 응답이 새 세션의 화면에 반영되지 않게 한다.
  /// 재발급이 실패하면 원래 예외를 그대로 던진다. 세션 만료 여부는 [isSessionExpiredError]로 판정한다.
  Future<T> authorizedRequest<T>(
    Future<T> Function(String authorizationHeader) request,
  ) async {
    final start = await _session.readSessionAuth();
    final sessionId = start.sessionId;
    final authorizationHeader = start.header;

    if (authorizationHeader == null || authorizationHeader.isEmpty) {
      throw const AuthSessionException('저장된 Access Token이 없습니다.');
    }

    _session.ensureSameSession(sessionId);

    try {
      final result = await request(authorizationHeader);
      _session.ensureSameSession(sessionId);
      return result;
    } on SessionChangedException {
      rethrow;
    } on ApiException catch (error) {
      _session.ensureSameSession(sessionId);

      if (error.statusCode != 401) {
        rethrow;
      }

      debugPrint('Access Token 인증 실패 → 같은 세션에서 재발급 후 재시도');

      final retryHeader = await _refresher.refreshForSession(
        sessionId,
        failedHeader: authorizationHeader,
      );

      _session.ensureSameSession(sessionId);

      try {
        final result = await request(retryHeader);
        _session.ensureSameSession(sessionId);
        return result;
      } catch (_) {
        _session.ensureSameSession(sessionId);
        rethrow;
      }
    } catch (_) {
      // 네트워크 오류 등도 세션이 바뀌었다면 이전 세션의 결과로 보고 버린다.
      _session.ensureSameSession(sessionId);
      rethrow;
    }
  }

  /// [authorizedRequest]가 던진 예외가 세션 만료를 뜻하는지 판정한다.
  ///
  /// 세션 만료로 보는 경우:
  /// - 저장된 Access/Refresh Token이 없음([AuthSessionException])
  /// - 재발급 응답이 INVALID_REFRESH_TOKEN 또는 EXPIRED_REFRESH_TOKEN
  ///
  /// 네트워크 오류, 5xx, 재발급 뒤에도 받은 401은 세션 만료로 보지 않는다.
  static bool isSessionExpiredError(Object error) {
    if (error is AuthSessionException) {
      return true;
    }

    return error is ApiException &&
        _sessionExpiredErrorCodes.contains(error.code);
  }

  static const Set<String> _sessionExpiredErrorCodes = <String>{
    'INVALID_REFRESH_TOKEN',
    'EXPIRED_REFRESH_TOKEN',
  };

  void dispose() {
    _authApiService.dispose();
  }
}
