import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../../repositories/auth/auth_repository.dart';
import '../../core/network/api_exception.dart';
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
