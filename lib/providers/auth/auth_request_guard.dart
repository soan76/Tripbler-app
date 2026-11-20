import 'package:flutter/foundation.dart';

import '../../repositories/auth/auth_repository.dart';
import 'auth_action_runner.dart';
import 'auth_state.dart';

/// 로그인이 필요한 요청을 실행하고, 세션 만료가 확인되면 로그인 상태를 해제한다.
///
/// 상태를 읽고 내보내는 일은 넘겨받은 함수가 맡는다.
/// - [readRepository]: 현재 인증 저장소를 읽는다.
/// - [isMounted]: 상태 객체가 아직 폐기되지 않았는지 확인한다.
/// - [readState]: 현재 상태를 읽는다. [isMounted]가 true일 때만 부른다.
/// - [update]: 현재 상태에 변경을 적용해 내보낸다(폐기된 뒤에는 현재 상태도 읽지 않는다).
class AuthRequestGuard {
  const AuthRequestGuard({
    required this.readRepository,
    required this.isMounted,
    required this.readState,
    required this.update,
  });

  final AuthRepository Function() readRepository;
  final bool Function() isMounted;
  final AuthState Function() readState;
  final void Function(AuthChange change) update;

  /// 매번 현재 저장소를 읽는다(Notifier의 build가 다시 실행되면 바뀔 수 있다).
  AuthRepository get _repository => readRepository();

  /// 로그인이 필요한 요청을 실행한다(장소 검색 등).
  ///
  /// 토큰 첨부, 401 재발급·재시도, 세션 확인은 [AuthRepository.authorizedRequest]가 맡는다.
  /// - 세션 만료가 확인되면([AuthRepository.isSessionExpiredError]) 요청을 시작한 세션이
  ///   아직 현재 세션이고 로그인 상태일 때만 토큰을 지우고 로그인 상태를 해제한다.
  ///   어느 경우든 [SessionExpiredException]을 던진다.
  ///   앱은 비로그인으로도 쓸 수 있으므로 화면 이동은 하지 않는다. 안내는 호출한 화면이 맡는다.
  /// - 요청 중 로그아웃·재로그인되면 [SessionChangedException]을 그대로 던진다.
  ///   호출부는 현재 화면의 데이터와 오류 문구를 그대로 두고 무시한다.
  /// - 그 밖의 오류(네트워크, 5xx 등)는 로그인 상태를 유지한 채 그대로 던진다.
  Future<T> run<T>(
    Future<T> Function(String authorizationHeader) request,
  ) async {
    final sessionId = _repository.sessionId;

    try {
      return await _repository.authorizedRequest<T>(request);
    } on SessionChangedException {
      rethrow;
    } catch (error) {
      if (!AuthRepository.isSessionExpiredError(error)) {
        rethrow;
      }

      // 폐기 여부를 먼저 확인하고, 폐기되지 않았을 때만 상태를 읽는다.
      final isSameSession =
          isMounted() &&
          readState().isAuthenticated &&
          _repository.sessionId == sessionId;

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
      cleared = await _repository.clearTokensIfSession(sessionId);
    } catch (error) {
      // 저장소 삭제가 실패해도 세션 번호는 이미 바뀌었으므로 상태는 해제한다.
      debugPrint('토큰 삭제 실패: $error');
      cleared = true;
    }

    if (!cleared) {
      return;
    }

    update((s) => s.withoutUser());
  }
}
