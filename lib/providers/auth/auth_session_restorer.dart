import 'package:flutter/foundation.dart';

import '../../repositories/auth/auth_repository.dart';
import 'auth_action_runner.dart';
import 'auth_state.dart';

/// 저장된 토큰으로 로그인 상태를 복구한다.
///
/// 상태를 읽고 내보내는 일은 넘겨받은 함수가 맡는다.
/// - [readRepository]: 현재 인증 저장소를 읽는다.
/// - [readState]: 현재 상태를 읽는다.
/// - [update]: 현재 상태에 변경을 적용해 내보낸다(폐기된 뒤에는 현재 상태도 읽지 않는다).
/// - [startLoading]: 로딩을 켜고 이전 오류 문구를 지운다.
class AuthSessionRestorer {
  const AuthSessionRestorer({
    required this.readRepository,
    required this.readState,
    required this.update,
    required this.startLoading,
  });

  final AuthRepository Function() readRepository;
  final AuthState Function() readState;
  final void Function(AuthChange change) update;
  final void Function() startLoading;

  /// 매번 현재 저장소를 읽는다(Notifier의 build가 다시 실행되면 바뀔 수 있다).
  AuthRepository get _repository => readRepository();

  /// 앱 시작 시 저장된 토큰으로 로그인 상태를 복구한다. 이미 초기화됐으면 하지 않는다.
  ///
  /// - 세션 만료가 확인되면([AuthRepository.isSessionExpiredError]) 토큰을 지운다.
  /// - 그 밖의 실패(네트워크 오류, 5xx, 403, 재발급 뒤 401, 예상하지 못한 오류 등)는
  ///   토큰을 남기고 [AuthState.sessionRestoreFailed]를 켠다. 화면은 상단 배너로
  ///   [retry]를 안내한다.
  /// - 복구 중 다른 계정으로 로그인되면 늦게 온 복구 결과는 버린다.
  /// - 끝나면 결과와 `isInitialized: true`, `isLoading: false`를 한 번에 내보낸다.
  Future<void> restore() async {
    if (readState().isInitialized) {
      return;
    }

    await _restoreFromStorage();
  }

  /// 일시적 장애로 실패한 세션 복구를 다시 시도한다(상단 배너의 다시 시도).
  /// 복구 실패 상태가 아니거나 로딩 중이면 하지 않는다.
  Future<void> retry() async {
    final state = readState();

    if (!state.sessionRestoreFailed || state.isLoading) {
      return;
    }

    await _restoreFromStorage();
  }

  Future<void> _restoreFromStorage() async {
    startLoading();

    final sessionId = _repository.sessionId;
    AuthChange? outcome;

    try {
      final hasTokens = await _repository.hasTokens();

      if (_repository.sessionId != sessionId) {
        return;
      }

      if (!hasTokens) {
        outcome = (s) => s.withoutUser();
        return;
      }

      // 401이면 getCurrentUser 안에서 같은 세션으로 재발급·재시도한다.
      final user = await _repository.getCurrentUser();

      if (_repository.sessionId != sessionId) {
        return;
      }

      outcome = (s) => s.withUser(user);
    } on SessionChangedException {
      // 복구 중 로그아웃·재로그인됨: 늦게 온 복구 응답은 버린다.
    } catch (error) {
      debugPrint('인증 상태 복구 실패: $error');

      if (_repository.sessionId != sessionId) {
        return;
      }

      if (AuthRepository.isSessionExpiredError(error)) {
        // 세션 만료가 확인된 경우에만 토큰을 지운다.
        try {
          await _repository.clearTokensIfSession(sessionId);
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

      update(
        (s) => (change == null ? s : change(s)).copyWith(
          isInitialized: true,
          isLoading: false,
        ),
      );
    }
  }
}
