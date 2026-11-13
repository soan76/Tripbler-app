import 'dart:async';

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

  /// 로그인 세션 번호.
  ///
  /// 로그인(새 토큰 저장)과 세션 종료(로그아웃·탈퇴·토큰 삭제) 때만 바뀌고,
  /// 같은 세션에서 Access Token만 재발급할 때는 그대로다.
  /// 인증 요청은 시작할 때 이 번호를 기록해 두고, 재시도·토큰 저장·만료 처리를
  /// 원래 세션에만 적용한다. AuthNotifier도 같은 번호를 참조한다.
  int _sessionId = 0;

  int get sessionId => _sessionId;

  /// 토큰 저장소 작업을 한 줄로 처리하는 꼬리 Future.
  ///
  /// 세션 번호 변경과 토큰 저장·삭제, 인증 요청의 "번호 + 토큰" 읽기를 모두 이 경로로
  /// 순서대로 실행해 새 번호와 이전 토큰이 한 쌍으로 읽히지 않게 한다.
  /// 네트워크 호출은 이 경로에 넣지 않는다(느린 요청이 다른 인증 요청을 막지 않도록).
  Future<void> _storageTail = Future<void>.value();

  /// 진행 중인 Access Token 재발급. 같은 세션의 요청끼리만 공유한다.
  _RefreshTask? _ongoingRefresh;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _storageTail.then((_) => operation());
    _storageTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// 현재 세션 번호와 저장된 Authorization 헤더를 한 쌍으로 읽는다.
  Future<({int sessionId, String? header})> _readSessionAuth() {
    return _serialized(() async {
      return (
        sessionId: _sessionId,
        header: await _tokenStorageService.readAuthorizationHeader(),
      );
    });
  }

  /// 요청을 시작한 세션이 아직 유지되는지 확인한다.
  void _ensureSameSession(int sessionId) {
    if (_sessionId != sessionId) {
      throw const SessionChangedException();
    }
  }

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
    await _serialized(() async {
      _sessionId++;

      await _tokenStorageService.saveTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        tokenType: response.tokenType,
      );
    });

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
    final session = await _readSessionAuth();

    return _refreshForSession(session.sessionId, failedHeader: null);
  }

  /// [sessionId] 세션의 Access Token을 재발급한다.
  ///
  /// - 같은 세션의 진행 중인 재발급이 있으면 합류한다. 다른 세션의 재발급에는 합류하지 않는다.
  /// - [failedHeader]보다 새 토큰이 이미 저장돼 있으면(다른 요청이 먼저 재발급함) 그 토큰을 쓴다.
  /// - 결과는 순차 경로에서 세션이 그대로일 때만 저장한다. 세션이 바뀌었으면
  ///   [SessionChangedException]을 던지고, 이전 세션의 실패가 새 세션의 만료로 판정되지 않게 한다.
  Future<String> _refreshForSession(
    int sessionId, {
    required String? failedHeader,
  }) {
    final ongoing = _ongoingRefresh;

    if (ongoing != null && ongoing.sessionId == sessionId) {
      return ongoing.future;
    }

    final task = _RefreshTask(
      sessionId,
      _performRefresh(sessionId, failedHeader: failedHeader),
    );

    _ongoingRefresh = task;

    // 늦게 끝난 다른 세션의 재발급이 진행 중인 참조를 지우지 않도록 자기 것만 지운다.
    task.future.then<void>(
      (_) => _clearOngoingRefresh(task),
      onError: (Object _) => _clearOngoingRefresh(task),
    );

    return task.future;
  }

  void _clearOngoingRefresh(_RefreshTask task) {
    if (identical(_ongoingRefresh, task)) {
      _ongoingRefresh = null;
    }
  }

  Future<String> _performRefresh(
    int sessionId, {
    required String? failedHeader,
  }) async {
    final stored = await _serialized(() async {
      return (
        sessionId: _sessionId,
        header: await _tokenStorageService.readAuthorizationHeader(),
        refreshToken: await _tokenStorageService.readRefreshToken(),
      );
    });

    if (stored.sessionId != sessionId) {
      throw const SessionChangedException();
    }

    final storedHeader = stored.header;

    if (failedHeader != null &&
        storedHeader != null &&
        storedHeader.isNotEmpty &&
        storedHeader != failedHeader) {
      debugPrint('다른 요청에서 Access Token 재발급 완료 → 저장된 토큰 사용');
      return storedHeader;
    }

    final refreshToken = stored.refreshToken;

    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthSessionException('저장된 Refresh Token이 없습니다.');
    }

    final TokenRefreshResponse response;

    try {
      response = await _authApiService.refresh(
        TokenRefreshRequest(refreshToken: refreshToken),
      );
    } catch (_) {
      // 재발급 중 세션이 바뀌었다면 이전 세션의 실패(만료 포함)는 세션 변경으로 바꾼다.
      _ensureSameSession(sessionId);
      rethrow;
    }

    final saved = await _serialized(() async {
      if (_sessionId != sessionId) {
        return (sameSession: false, header: null);
      }

      await _tokenStorageService.saveAccessToken(
        accessToken: response.accessToken,
        tokenType: response.tokenType,
      );

      return (
        sameSession: true,
        header: await _tokenStorageService.readAuthorizationHeader(),
      );
    });

    if (!saved.sameSession) {
      // 재발급 응답이 오기 전에 로그아웃·재로그인됨: 이전 세션의 토큰은 저장하지 않는다.
      throw const SessionChangedException();
    }

    final refreshedHeader = saved.header;

    if (refreshedHeader == null || refreshedHeader.isEmpty) {
      // 서버는 새 Access Token을 발급했지만 기기 저장소에서 다시 읽지 못했다.
      // 세션 만료가 아니라 로컬 저장·읽기 실패이므로 Refresh Token은 지우지 않는다.
      throw const TokenStorageException('재발급한 Access Token을 기기에서 읽지 못했습니다.');
    }

    return refreshedHeader;
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
    final sessionId = _sessionId;

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
    String? refreshToken;
    Object? clearError;
    StackTrace? clearStackTrace;

    await _serialized(() async {
      try {
        // 서버는 이 Refresh Token과 일치하는 토큰만 폐기한다(같은 계정의 새 로그인 세션은 보존).
        refreshToken = await _tokenStorageService.readRefreshToken();
      } catch (error) {
        debugPrint('로그아웃용 토큰 읽기 실패: $error');
      }

      _sessionId++;

      try {
        await _tokenStorageService.clearTokens();
      } catch (error) {
        debugPrint('로컬 토큰 삭제 실패, 한 번 더 시도: $error');

        try {
          await _tokenStorageService.clearTokens();
        } catch (retryError, stackTrace) {
          clearError = retryError;
          clearStackTrace = stackTrace;
        }
      }
    });

    _sendServerLogout(refreshToken);

    final error = clearError;

    if (error != null) {
      Error.throwWithStackTrace(error, clearStackTrace ?? StackTrace.current);
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

  /// 현재 세션을 끝내고 저장된 토큰을 모두 지운다(세션 번호 한 번 변경).
  Future<void> clearTokens() {
    return _serialized(() async {
      _sessionId++;
      await _tokenStorageService.clearTokens();
    });
  }

  /// [sessionId] 세션이 아직 현재 세션일 때만 끝내고 토큰을 지운다.
  ///
  /// 세션 만료 처리나 탈퇴처럼 늦게 끝날 수 있는 작업이 그 사이 로그인한
  /// 다른 계정의 토큰을 지우지 않게 한다. 지웠으면 true.
  Future<bool> clearTokensIfSession(int sessionId) {
    return _serialized(() async {
      if (_sessionId != sessionId) {
        return false;
      }

      _sessionId++;
      await _tokenStorageService.clearTokens();

      return true;
    });
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
    final start = await _readSessionAuth();
    final sessionId = start.sessionId;
    final authorizationHeader = start.header;

    if (authorizationHeader == null || authorizationHeader.isEmpty) {
      throw const AuthSessionException('저장된 Access Token이 없습니다.');
    }

    _ensureSameSession(sessionId);

    try {
      final result = await request(authorizationHeader);
      _ensureSameSession(sessionId);
      return result;
    } on SessionChangedException {
      rethrow;
    } on ApiException catch (error) {
      _ensureSameSession(sessionId);

      if (error.statusCode != 401) {
        rethrow;
      }

      debugPrint('Access Token 인증 실패 → 같은 세션에서 재발급 후 재시도');

      final retryHeader = await _refreshForSession(
        sessionId,
        failedHeader: authorizationHeader,
      );

      _ensureSameSession(sessionId);

      try {
        final result = await request(retryHeader);
        _ensureSameSession(sessionId);
        return result;
      } catch (_) {
        _ensureSameSession(sessionId);
        rethrow;
      }
    } catch (_) {
      // 네트워크 오류 등도 세션이 바뀌었다면 이전 세션의 결과로 보고 버린다.
      _ensureSameSession(sessionId);
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

/// 로컬 인증 세션 자체에 문제가 있을 때 사용하는 예외(저장된 토큰이 없음).
/// 세션 만료로 판정된다([AuthRepository.isSessionExpiredError]).
class AuthSessionException implements Exception {
  final String message;

  const AuthSessionException(this.message);

  @override
  String toString() => message;
}

/// 기기 토큰 저장소의 저장·읽기가 기대와 다르게 끝났을 때의 예외.
///
/// 세션 만료가 아니므로 [AuthRepository.isSessionExpiredError]는 false다.
/// 세션 복구에서는 토큰을 남기고 상단 배너의 다시 시도로 보낸다.
class TokenStorageException implements Exception {
  final String message;

  const TokenStorageException(this.message);

  @override
  String toString() => message;
}

/// 세션 만료가 확인되어 로그인 상태를 해제했음을 알리는 예외.
///
/// AuthNotifier.runAuthorizedRequest가 던진다. 앱은 비로그인으로도 쓸 수 있어 화면은
/// 그대로 남으므로, 안내가 필요하면 호출한 화면이 맡는다(예: 지도 검색의 만료 안내).
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.sessionId]);

  /// 만료된 요청이 시작된 로그인 세션 번호([AuthRepository.sessionId]).
  /// 같은 세션의 만료 안내를 한 번만 띄우는 데 쓴다.
  final int? sessionId;

  @override
  String toString() => '로그인이 만료되었습니다. 다시 로그인해 주세요.';
}

/// 요청을 시작한 로그인 세션이 그 사이 바뀌어(로그아웃·재로그인) 작업을 중단했음을 알리는 예외.
///
/// 세션 만료가 아니므로 [AuthRepository.isSessionExpiredError]는 false다.
/// 이전 화면에서 시작한 작업이므로 호출부는 현재 화면의 데이터와 오류 문구를 그대로 두고 무시한다.
class SessionChangedException implements Exception {
  const SessionChangedException();

  @override
  String toString() => '로그인 세션이 바뀌어 이전 요청을 중단했습니다.';
}

/// 세션별 Access Token 재발급 작업.
class _RefreshTask {
  _RefreshTask(this.sessionId, this.future);

  final int sessionId;
  final Future<String> future;
}
