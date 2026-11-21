import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../../repositories/auth/auth_repository.dart';
import 'auth_action_runner.dart';
import 'auth_request_guard.dart';
import 'auth_session_restorer.dart';
import 'auth_state.dart';

export 'auth_state.dart';

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
  void _update(AuthChange change) {
    if (!ref.mounted) {
      return;
    }

    _emit(change(state));
  }

  /// 로딩·오류 처리를 공통으로 맡는 실행기. 상태는 [_emit]·[_update]로만 내보낸다.
  late final AuthActionRunner _actionRunner = AuthActionRunner(
    readState: () => state,
    emit: _emit,
    update: _update,
  );

  /// 로딩을 켜고 이전 오류 문구를 지운다.
  void _startLoading() => _actionRunner.startLoading();

  /// 저장된 토큰으로 로그인 상태를 복구한다. 저장소는 쓸 때마다 [_authRepository]를 읽는다.
  late final AuthSessionRestorer _sessionRestorer = AuthSessionRestorer(
    readRepository: () => _authRepository,
    readState: () => state,
    update: _update,
    startLoading: _startLoading,
  );

  /// 로그인이 필요한 요청을 실행하고 세션 만료를 처리한다.
  late final AuthRequestGuard _requestGuard = AuthRequestGuard(
    readRepository: () => _authRepository,
    isMounted: () => ref.mounted,
    readState: () => state,
    update: _update,
  );

  /// 회원가입
  Future<bool> signup({
    required String loginId,
    String? nickname,
    required String password,
  }) {
    return _actionRunner.run(
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

  /// 로그인
  Future<bool> login({required String loginId, required String password}) {
    return _actionRunner.run(
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
    return _actionRunner.run(
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
    return _actionRunner.run(
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
    return _actionRunner.run(
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
  /// 세션 만료면 토큰을 지우고, 그 밖의 실패는 토큰을 남긴 채
  /// [AuthState.sessionRestoreFailed]를 켠다. 자세한 규칙은 [AuthSessionRestorer.restore].
  Future<void> restoreSession() => _sessionRestorer.restore();

  /// 일시적 장애로 실패한 세션 복구를 다시 시도한다(상단 배너의 다시 시도).
  Future<void> retryRestoreSession() => _sessionRestorer.retry();

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
    return _actionRunner.run(
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
    return _actionRunner.run(
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
    return _actionRunner.run(
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

  /// 기기 토큰 삭제에 실패한 로그아웃이 끝낸 세션 번호. 다시 시도는 이 번호가
  /// 현재 세션일 때만 토큰을 지운다. 지울 것이 없으면 null.
  int? _pendingLocalClearSessionId;

  /// 진행 중인 기기 토큰 삭제 재시도. 겹친 호출은 이 결과를 함께 기다린다.
  Future<bool>? _ongoingLocalClearRetry;

  /// 로그아웃. 기기에 저장된 로그인 정보(토큰)를 지웠으면 true, 재시도까지 실패해 남았으면 false.
  /// 어느 경우든 화면의 인증 상태는 로그아웃으로 바뀐다.
  ///
  /// 이미 로그아웃이나 다른 인증 작업이 진행 중이면 아무것도 하지 않고 null을 돌려준다.
  /// 호출부는 이때 결과 안내를 띄우지 않는다(진행 중인 작업의 안내를 덮지 않도록).
  Future<bool?> logout() async {
    if (state.isLoading) {
      return null;
    }

    _startLoading();

    var localTokensCleared = true;

    try {
      // 서버 로그아웃은 기다리지 않으므로, 여기서 던지는 오류는 기기의 토큰 삭제가
      // 재시도까지 실패한 경우뿐이다.
      await _authRepository.logout();
    } catch (error) {
      debugPrint('로그아웃 중 기기 토큰 삭제 실패: $error');

      localTokensCleared = false;
    } finally {
      // 로그아웃이 끝낸 세션 번호. 이 세션 동안만 다시 시도로 토큰을 지운다.
      _pendingLocalClearSessionId = localTokensCleared
          ? null
          : _authRepository.sessionId;

      // AuthRepository가 로컬 토큰을 먼저 지우고 서버 로그아웃은 따로 보내므로(로컬 우선)
      // 연결 상태와 관계없이 Flutter 인증 상태도 바로 로그아웃으로 바꾼다.
      // 삭제 실패 안내는 호출부의 SnackBar가 맡으므로 오류 문구는 남기지 않는다
      // (로그인 화면 등이 읽는 errorMessage에 이전 로그아웃 오류가 보이지 않도록).
      _update((s) => s.withoutUser().copyWith(isLoading: false));
    }

    return localTokensCleared;
  }

  /// 로그아웃 때 기기에 남은 로그인 정보(토큰)를 다시 지운다.
  /// 더 지울 것이 없으면 true, 다시 실패했으면 false.
  ///
  /// 화면은 이미 로그아웃 상태다. 토큰이 남아 있으면 다음 실행 때 세션이 복구될 수
  /// 있으므로 사용자가 다시 시도할 수 있게 한다. 그 사이 새로 로그인했으면 새 세션의
  /// 토큰이므로 지우지 않는다. 진행 중인 재시도가 있으면 그 결과를 함께 기다린다.
  Future<bool> retryClearLocalTokens() {
    return _ongoingLocalClearRetry ??= _retryClearLocalTokens().whenComplete(
      () => _ongoingLocalClearRetry = null,
    );
  }

  Future<bool> _retryClearLocalTokens() async {
    final sessionId = _pendingLocalClearSessionId;

    if (sessionId == null) {
      return true;
    }

    try {
      // 그 사이 로그인으로 세션이 바뀌었으면 새 세션의 토큰이므로 지우지 않는다.
      await _authRepository.clearTokensIfSession(sessionId);
    } on TokenClearException catch (error) {
      debugPrint('기기 토큰 삭제 재시도 실패: $error');

      // 실패한 삭제도 세션 번호를 바꾸므로, 다음 재시도의 기준을 그 삭제가 바꾼 번호로
      // 옮긴다. 지금의 저장소 번호는 그 사이 대기 중이던 로그인 번호일 수 있어 쓰지 않는다.
      // 그 사이 다른 로그아웃이 기준을 바꿨으면 그대로 둔다.
      if (_pendingLocalClearSessionId == sessionId) {
        _pendingLocalClearSessionId = error.sessionId;
      }

      return false;
    } catch (error) {
      debugPrint('기기 토큰 삭제 재시도 실패: $error');

      // 삭제 실패 번호를 알 수 없는 오류. 다음 재시도의 기준을 지금 번호로 옮긴다.
      // 그 사이 다른 로그아웃이 기준을 바꿨으면 그대로 둔다.
      if (_pendingLocalClearSessionId == sessionId) {
        _pendingLocalClearSessionId = _authRepository.sessionId;
      }

      return false;
    }

    // 지웠거나 세션이 바뀌어 지울 필요가 없어졌다.
    if (_pendingLocalClearSessionId == sessionId) {
      _pendingLocalClearSessionId = null;
    }

    return true;
  }

  /// 로그인이 필요한 요청을 실행한다(장소 검색 등).
  ///
  /// 세션 만료가 확인되면 로그인 상태를 해제하고 [SessionExpiredException]을,
  /// 요청 중 세션이 바뀌면 [SessionChangedException]을 던진다.
  /// 자세한 규칙은 [AuthRequestGuard.run].
  Future<T> runAuthorizedRequest<T>(
    Future<T> Function(String authorizationHeader) request,
  ) => _requestGuard.run<T>(request);

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
