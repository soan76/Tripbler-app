import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../repositories/auth/auth_repository.dart';
import '../models/user/user_response.dart';
import '../core/network/api_exception.dart';

/// 로그인이 필요한 요청을 토큰과 함께 실행하는 함수 형식.
/// [AuthNotifier.runAuthorizedRequest]를 다른 Notifier에 넘길 때 쓴다.
typedef AuthorizedRequestRunner =
    Future<T> Function<T>(
      Future<T> Function(String authorizationHeader) request,
    );

/// 토큰 저장·재발급과 인증 API를 맡는 저장소.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = AuthRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

/// 로그인이 필요한 요청을 실행하는 함수. 지도 검색처럼 다른 Notifier가 쓴다.
final authorizedRequestRunnerProvider = Provider<AuthorizedRequestRunner>(
  (ref) => ref.read(authProvider.notifier).runAuthorizedRequest,
);

/// 인증 작업이 끝났을 때 상태에 반영할 변경.
typedef _AuthChange = AuthState Function(AuthState state);

/// 앱의 인증 상태.
class AuthState {
  const AuthState({
    this.isInitialized = false,
    this.isLoading = false,
    this.isAuthenticated = false,
    this.isCheckingLoginId = false,
    this.isLoadingSocialAccounts = false,
    this.sessionRestoreFailed = false,
    this.googleLinked,
    this.userId,
    this.loginId,
    this.nickname,
    this.profileImageUrl,
    this.errorMessage,
    this.isLoginIdAvailable,
    this.checkedLoginId,
    this.loginIdCheckMessage,
    this.sessionId = 0,
  });

  /// 앱 초기화 시 인증 상태를 복구했는지 여부
  final bool isInitialized;
  final bool isLoading;
  final bool isAuthenticated;
  final bool isCheckingLoginId;
  final bool isLoadingSocialAccounts;

  /// 세션 만료가 확인되지 않은 오류로 세션 복구에 실패해 토큰을 남겨 둔 상태.
  /// 화면은 상단 배너로 다시 시도([AuthNotifier.retryRestoreSession])를 안내한다.
  final bool sessionRestoreFailed;

  /// 현재 로그인 사용자의 Google 계정 연동 상태
  final bool? googleLinked;

  /// 현재 로그인 사용자의 정보
  final int? userId;
  final String? loginId;
  final String? nickname;
  final String? profileImageUrl;
  final String? errorMessage;
  final bool? isLoginIdAvailable;
  final String? checkedLoginId;
  final String? loginIdCheckMessage;

  /// 상태를 내보낸 시점의 [AuthRepository.sessionId].
  /// 로그인·로그아웃·세션 만료 때마다 바뀐다. 중간 전이가 합쳐져도 세션이 바뀐 것을
  /// 알 수 있도록 다른 상태(지도)가 이 번호를 비교한다.
  final int sessionId;

  bool isLoginIdCheckedAndAvailable(String loginId) {
    return isLoginIdAvailable == true && checkedLoginId == loginId.trim();
  }

  AuthState copyWith({
    bool? isInitialized,
    bool? isLoading,
    bool? isAuthenticated,
    bool? isCheckingLoginId,
    bool? isLoadingSocialAccounts,
    bool? sessionRestoreFailed,
    bool? googleLinked,
    bool clearGoogleLinked = false,
    int? userId,
    bool clearUserId = false,
    String? loginId,
    bool clearLoginId = false,
    String? nickname,
    bool clearNickname = false,
    String? profileImageUrl,
    bool clearProfileImageUrl = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isLoginIdAvailable,
    bool clearIsLoginIdAvailable = false,
    String? checkedLoginId,
    bool clearCheckedLoginId = false,
    String? loginIdCheckMessage,
    bool clearLoginIdCheckMessage = false,
    int? sessionId,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isCheckingLoginId: isCheckingLoginId ?? this.isCheckingLoginId,
      isLoadingSocialAccounts:
          isLoadingSocialAccounts ?? this.isLoadingSocialAccounts,
      sessionRestoreFailed: sessionRestoreFailed ?? this.sessionRestoreFailed,
      googleLinked: clearGoogleLinked
          ? null
          : googleLinked ?? this.googleLinked,
      userId: clearUserId ? null : userId ?? this.userId,
      loginId: clearLoginId ? null : loginId ?? this.loginId,
      nickname: clearNickname ? null : nickname ?? this.nickname,
      profileImageUrl: clearProfileImageUrl
          ? null
          : profileImageUrl ?? this.profileImageUrl,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      isLoginIdAvailable: clearIsLoginIdAvailable
          ? null
          : isLoginIdAvailable ?? this.isLoginIdAvailable,
      checkedLoginId: clearCheckedLoginId
          ? null
          : checkedLoginId ?? this.checkedLoginId,
      loginIdCheckMessage: clearLoginIdCheckMessage
          ? null
          : loginIdCheckMessage ?? this.loginIdCheckMessage,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  /// 서버가 준 현재 사용자 정보로 로그인 상태가 된다. 없는 값(닉네임·사진)은 비운다.
  AuthState withUser(UserResponse user) {
    return copyWith(
      userId: user.id,
      loginId: user.loginId,
      nickname: user.nickname,
      clearNickname: user.nickname == null,
      profileImageUrl: user.profileImageUrl,
      clearProfileImageUrl: user.profileImageUrl == null,
      isAuthenticated: true,
      sessionRestoreFailed: false,
    );
  }

  /// 현재 로그인 사용자의 상태를 비운다.
  ///
  /// 세션 번호는 [AuthRepository]가 토큰 저장·삭제와 함께 관리한다.
  AuthState withoutUser() {
    return copyWith(
      isAuthenticated: false,
      sessionRestoreFailed: false,
      clearUserId: true,
      clearLoginId: true,
      clearNickname: true,
      clearProfileImageUrl: true,
      clearGoogleLinked: true,
    );
  }

  /// 아이디 중복확인 결과를 비운다. [message]를 주면 안내 문구만 남긴다.
  AuthState withoutLoginIdCheck({String? message}) {
    return copyWith(
      clearIsLoginIdAvailable: true,
      clearCheckedLoginId: true,
      loginIdCheckMessage: message,
      clearLoginIdCheckMessage: message == null,
    );
  }
}

/// 앱의 인증 상태를 관리한다.
class AuthNotifier extends Notifier<AuthState> {
  late AuthRepository _authRepository;

  @override
  AuthState build() {
    _authRepository = ref.read(authRepositoryProvider);
    return AuthState(sessionId: _authRepository.sessionId);
  }

  /// 상태를 내보낸다. 저장소의 현재 세션 번호를 함께 넣는다.
  /// 상태 객체가 폐기된 뒤(앱 종료, 테스트 컨테이너 폐기)에는 아무것도 하지 않는다.
  void _emit(AuthState next) {
    if (!ref.mounted) {
      return;
    }

    state = next.copyWith(sessionId: _authRepository.sessionId);
  }

  /// 현재 상태에 [change]를 적용해 내보낸다. 폐기된 뒤에는 현재 상태도 읽지 않는다.
  void _update(_AuthChange change) {
    if (!ref.mounted) {
      return;
    }

    _emit(change(state));
  }

  /// 로딩을 켜고 이전 오류 문구를 지운다.
  void _startLoading() {
    _emit(state.copyWith(isLoading: true, clearErrorMessage: true));
  }

  /// 회원가입
  Future<bool> signup({
    required String loginId,
    String? nickname,
    required String password,
  }) {
    return _runGuardedAction(
      action: () async {
        await _authRepository.signup(
          loginId: loginId,
          nickname: nickname,
          password: password,
        );

        return null;
      },
      logPrefix: '회원가입 실패',
      fallbackErrorMessage: '회원가입 중 오류가 발생했습니다.',
    );
  }

  /// 아이디 중복확인
  Future<void> checkLoginIdAvailability(String loginId) async {
    final trimmedLoginId = loginId.trim();

    if (state.isCheckingLoginId) {
      return;
    }

    if (trimmedLoginId.isEmpty) {
      _emit(state.withoutLoginIdCheck(message: '아이디를 입력해 주세요.'));
      return;
    }

    if (trimmedLoginId.length < 4 || trimmedLoginId.length > 30) {
      _emit(state.withoutLoginIdCheck(message: '아이디는 4자 이상 30자 이하여야 합니다.'));
      return;
    }

    _emit(state.withoutLoginIdCheck().copyWith(isCheckingLoginId: true));

    _AuthChange result;

    try {
      final response = await _authRepository.checkLoginIdAvailability(
        trimmedLoginId,
      );

      result = (s) => s.copyWith(
        checkedLoginId: response.loginId,
        isLoginIdAvailable: response.available,
        loginIdCheckMessage: response.available
            ? '사용 가능한 아이디입니다.'
            : '이미 사용 중인 아이디입니다.',
      );
    } catch (error) {
      debugPrint('아이디 중복확인 실패: $error');

      result = (s) => s.withoutLoginIdCheck(message: '아이디 중복확인에 실패했습니다.');
    }

    _update((s) => result(s).copyWith(isCheckingLoginId: false));
  }

  void resetLoginIdAvailability() {
    if (state.isLoginIdAvailable == null &&
        state.checkedLoginId == null &&
        state.loginIdCheckMessage == null) {
      return;
    }

    _emit(state.withoutLoginIdCheck());
  }

  /// 로그인
  Future<bool> login({required String loginId, required String password}) {
    return _runGuardedAction(
      action: () async {
        await _authRepository.login(loginId: loginId, password: password);

        // 로그인 성공 후 /users/me 호출
        // → loginId, nickname 등 현재 사용자 정보 조회
        final user = await _authRepository.getCurrentUser();

        return (AuthState s) => s.withUser(user);
      },
      logPrefix: '로그인 실패',
      fallbackErrorMessage: '로그인 중 오류가 발생했습니다.',
      onFailure: (s) => s.withoutUser(),
    );
  }

  /// 현재 로그인 사용자의 닉네임을 변경한다.
  ///
  /// 서버에서 반환한 최신 사용자 정보를 상태에 반영한다.
  Future<bool> updateNickname({required String nickname}) {
    return _runGuardedAction(
      canRun: state.isAuthenticated,
      action: () async {
        final user = await _authRepository.updateNickname(
          nickname: nickname.trim(),
        );

        return (AuthState s) => s.withUser(user);
      },
      logPrefix: '닉네임 변경 실패',
      fallbackErrorMessage: '닉네임 변경 중 오류가 발생했습니다.',
    );
  }

  /// 현재 로그인 사용자의 프로필 이미지를 변경한다.
  ///
  /// 서버에서 반환한 최신 사용자 정보를 상태에 반영한다.
  Future<bool> updateProfileImage({required String filePath}) {
    return _runGuardedAction(
      canRun: state.isAuthenticated,
      action: () async {
        final user = await _authRepository.updateProfileImage(
          filePath: filePath,
        );

        return (AuthState s) => s.withUser(user);
      },
      logPrefix: '프로필 이미지 변경 실패',
      fallbackErrorMessage: '프로필 이미지 변경 중 오류가 발생했습니다.',
    );
  }

  /// 현재 로그인 사용자의 프로필 이미지를 삭제한다.
  Future<bool> deleteProfileImage() {
    return _runGuardedAction(
      canRun: state.isAuthenticated,
      action: () async {
        await _authRepository.deleteProfileImage();

        return (AuthState s) => s.copyWith(clearProfileImageUrl: true);
      },
      logPrefix: '프로필 이미지 삭제 실패',
      fallbackErrorMessage: '프로필 이미지 삭제 중 오류가 발생했습니다.',
    );
  }

  /// 앱 시작 시 저장된 토큰으로 로그인 상태를 복구한다.
  ///
  /// - 세션 만료가 확인되면([AuthRepository.isSessionExpiredError]) 토큰을 지운다.
  /// - 그 밖의 실패(네트워크 오류, 5xx, 403, 재발급 뒤 401, 예상하지 못한 오류 등)는
  ///   토큰을 남기고 [AuthState.sessionRestoreFailed]를 켠다. 화면은 상단 배너로
  ///   [retryRestoreSession]을 안내한다.
  /// - 복구 중 다른 계정으로 로그인되면 늦게 온 복구 결과는 버린다.
  Future<void> restoreSession() async {
    if (state.isInitialized) {
      return;
    }

    await _restoreSessionFromStorage();
  }

  /// 일시적 장애로 실패한 세션 복구를 다시 시도한다(상단 배너의 다시 시도).
  Future<void> retryRestoreSession() async {
    if (!state.sessionRestoreFailed || state.isLoading) {
      return;
    }

    await _restoreSessionFromStorage();
  }

  Future<void> _restoreSessionFromStorage() async {
    _startLoading();

    final sessionId = _authRepository.sessionId;
    _AuthChange? outcome;

    try {
      final hasTokens = await _authRepository.hasTokens();

      if (_authRepository.sessionId != sessionId) {
        return;
      }

      if (!hasTokens) {
        outcome = (s) => s.withoutUser();
        return;
      }

      // 401이면 getCurrentUser 안에서 같은 세션으로 재발급·재시도한다.
      final user = await _authRepository.getCurrentUser();

      if (_authRepository.sessionId != sessionId) {
        return;
      }

      outcome = (s) => s.withUser(user);
    } on SessionChangedException {
      // 복구 중 로그아웃·재로그인됨: 늦게 온 복구 응답은 버린다.
    } catch (error) {
      debugPrint('인증 상태 복구 실패: $error');

      if (_authRepository.sessionId != sessionId) {
        return;
      }

      if (AuthRepository.isSessionExpiredError(error)) {
        // 세션 만료가 확인된 경우에만 토큰을 지운다.
        try {
          await _authRepository.clearTokensIfSession(sessionId);
        } catch (clearError) {
          debugPrint('토큰 삭제 실패: $clearError');
        }

        outcome = (s) => s.withoutUser();
      } else {
        // 만료가 확인되지 않은 실패(네트워크 오류, 5xx, 403, 재발급 뒤 401 등)는
        // 로그인 정보를 잃지 않도록 토큰을 남기고 다시 시도를 안내한다.
        outcome = (s) => s.withoutUser().copyWith(sessionRestoreFailed: true);
      }
    } finally {
      final change = outcome;

      _update(
        (s) => (change == null ? s : change(s)).copyWith(
          isInitialized: true,
          isLoading: false,
        ),
      );
    }
  }

  /// 현재 사용자의 Google 계정 연동 상태를 조회한다.
  Future<void> loadLinkedSocialAccounts() async {
    if (!state.isAuthenticated || state.isLoadingSocialAccounts) {
      return;
    }

    _emit(state.copyWith(isLoadingSocialAccounts: true));

    bool? googleLinked;

    try {
      final response = await _authRepository.getLinkedSocialAccounts();

      googleLinked = response.isLinked('GOOGLE');
    } catch (error) {
      debugPrint('소셜 계정 연동 상태 조회 실패: $error');
    } finally {
      _update(
        (s) => s.copyWith(
          googleLinked: googleLinked,
          isLoadingSocialAccounts: false,
        ),
      );
    }
  }

  /// 현재 사용자에게 Google 계정을 연동한다.
  Future<bool> linkGoogleAccount() {
    return _runGuardedAction(
      action: () async {
        await _authRepository.linkGoogleAccount();
        return (AuthState s) => s.copyWith(googleLinked: true);
      },
      logPrefix: 'Google 계정 연동 실패',
      fallbackErrorMessage: 'Google 계정 연동 중 오류가 발생했습니다.',
    );
  }

  /// 현재 사용자에게 연동된 Google 계정을 해제한다.
  Future<bool> unlinkGoogleAccount() {
    return _runGuardedAction(
      action: () async {
        await _authRepository.unlinkGoogleAccount();
        return (AuthState s) => s.copyWith(googleLinked: false);
      },
      logPrefix: 'Google 계정 연동 해제 실패',
      fallbackErrorMessage: 'Google 계정 연동 해제 중 오류가 발생했습니다.',
    );
  }

  /// 현재 로그인 사용자의 계정을 탈퇴 처리한다.
  Future<bool> deleteAccount() {
    return _runGuardedAction(
      canRun: state.isAuthenticated,
      action: () async {
        await _authRepository.deleteAccount();

        // 서버에서 계정 삭제가 완료된 경우
        // Flutter의 현재 사용자 상태도 비로그인으로 초기화한다.
        return (AuthState s) => s.withoutUser();
      },
      logPrefix: '계정 탈퇴 실패',
      fallbackErrorMessage: '계정 탈퇴 중 오류가 발생했습니다.',
    );
  }

  /// 로그아웃
  Future<void> logout() async {
    if (state.isLoading) {
      return;
    }

    _startLoading();

    String? errorMessage;

    try {
      await _authRepository.logout();
    } on ApiException catch (error) {
      debugPrint('로그아웃 API 호출 실패: $error');

      errorMessage = error.message;
    } catch (error) {
      debugPrint('로그아웃 API 호출 실패: $error');

      errorMessage = '로그아웃 중 오류가 발생했습니다.';
    } finally {
      // AuthRepository가 로컬 토큰을 먼저 지우고 서버 로그아웃은 따로 보내므로(로컬 우선)
      // 연결 상태와 관계없이 Flutter 인증 상태도 바로 로그아웃으로 바꾼다.
      _update(
        (s) => s.withoutUser().copyWith(
          errorMessage: errorMessage,
          isLoading: false,
        ),
      );
    }
  }

  /// 로그인이 필요한 요청을 실행한다(장소 검색 등).
  ///
  /// 토큰 첨부, 401 재발급·재시도, 세션 확인은 [AuthRepository.authorizedRequest]가 맡는다.
  /// - 세션 만료가 확인되면([AuthRepository.isSessionExpiredError]) 요청을 시작한 세션이
  ///   아직 현재 세션일 때만 토큰을 지우고 로그인 상태를 해제한 뒤 [SessionExpiredException]을 던진다.
  ///   앱은 비로그인으로도 쓸 수 있으므로 화면 이동은 하지 않는다. 안내는 호출한 화면이 맡는다.
  /// - 요청 중 로그아웃·재로그인되면 [SessionChangedException]을 그대로 던진다.
  ///   호출부는 현재 화면의 데이터와 오류 문구를 그대로 두고 무시한다.
  /// - 그 밖의 오류(네트워크, 5xx 등)는 로그인 상태를 유지한 채 그대로 던진다.
  Future<T> runAuthorizedRequest<T>(
    Future<T> Function(String authorizationHeader) request,
  ) async {
    final sessionId = _authRepository.sessionId;

    try {
      return await _authRepository.authorizedRequest<T>(request);
    } on SessionChangedException {
      rethrow;
    } catch (error) {
      if (!AuthRepository.isSessionExpiredError(error)) {
        rethrow;
      }

      final isSameSession =
          ref.mounted &&
          state.isAuthenticated &&
          _authRepository.sessionId == sessionId;

      if (isSameSession) {
        debugPrint('세션 만료 확인: 로그인 상태를 해제합니다.');

        await _endExpiredSession(sessionId);
      }

      throw SessionExpiredException(sessionId);
    }
  }

  /// 만료된 세션이 아직 현재 세션일 때만 토큰을 지우고 로그인 상태를 해제한다.
  Future<void> _endExpiredSession(int sessionId) async {
    bool cleared;

    try {
      cleared = await _authRepository.clearTokensIfSession(sessionId);
    } catch (error) {
      // 저장소 삭제가 실패해도 세션 번호는 이미 바뀌었으므로 상태는 해제한다.
      debugPrint('토큰 삭제 실패: $error');
      cleared = true;
    }

    if (!cleared) {
      return;
    }

    _update((s) => s.withoutUser());
  }

  /// 인증 상태를 강제로 해제할 때 사용
  ///
  /// 추후 Refresh Token 만료 등에서 사용할 수 있다.
  Future<void> clearSession() async {
    try {
      await _authRepository.clearTokens();
    } catch (error) {
      debugPrint('토큰 삭제 실패: $error');
    }

    _update((s) => s.withoutUser());
  }

  /// 인증 관련 단일 작업의 로딩 상태와 예외 처리를 공통으로 관리한다.
  ///
  /// [action]과 [onFailure]는 반영할 상태 변경을 돌려준다.
  /// 변경은 작업 종료 시 로딩 해제와 함께 한 번에 내보낸다.
  Future<bool> _runGuardedAction({
    required Future<_AuthChange?> Function() action,
    required String logPrefix,
    required String fallbackErrorMessage,
    _AuthChange? onFailure,
    bool canRun = true,
  }) async {
    if (state.isLoading || !canRun) {
      return false;
    }

    _startLoading();

    _AuthChange? outcome;

    AuthState fail(AuthState s, String message) =>
        (onFailure == null ? s : onFailure(s)).copyWith(errorMessage: message);

    try {
      outcome = await action();
      return true;
    } on SessionChangedException {
      // 이전 세션에서 시작한 작업: 현재 화면의 데이터와 오류 문구를 그대로 둔다.
      debugPrint('$logPrefix: 로그인 세션이 바뀌어 결과를 반영하지 않습니다.');

      return false;
    } on ApiException catch (error) {
      debugPrint('$logPrefix: $error');

      outcome = (s) => fail(s, error.message);

      return false;
    } catch (error) {
      debugPrint('$logPrefix: $error');

      outcome = (s) => fail(s, fallbackErrorMessage);

      return false;
    } finally {
      final change = outcome;

      _update(
        (s) => (change == null ? s : change(s)).copyWith(isLoading: false),
      );
    }
  }

  /// 인증 관련 예외 메시지를 초기화한다.
  void clearError() {
    if (state.errorMessage == null) {
      return;
    }

    _emit(state.copyWith(clearErrorMessage: true));
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
