import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import '../../repositories/auth/auth_repository.dart';
import 'auth_state.dart';

/// 인증 작업이 끝났을 때 상태에 반영할 변경.
typedef AuthChange = AuthState Function(AuthState state);

/// 인증 관련 단일 작업의 로딩 상태와 예외 처리를 공통으로 관리한다.
///
/// 상태를 읽고 내보내는 일은 넘겨받은 함수가 맡는다.
/// - [readState]: 현재 상태를 읽는다.
/// - [emit]: 상태를 내보낸다(상태 객체가 폐기됐는지 확인하고 세션 번호를 넣는다).
/// - [update]: 현재 상태에 변경을 적용해 내보낸다(폐기된 뒤에는 현재 상태도 읽지 않는다).
class AuthActionRunner {
  const AuthActionRunner({
    required this.readState,
    required this.emit,
    required this.update,
  });

  final AuthState Function() readState;
  final void Function(AuthState next) emit;
  final void Function(AuthChange change) update;

  /// 로딩을 켜고 이전 오류 문구를 지운다.
  void startLoading() {
    emit(readState().copyWith(isLoading: true, clearErrorMessage: true));
  }

  /// [action]을 실행한다. 이미 로딩 중이거나 [canRun]이 false면 실행하지 않는다.
  ///
  /// [action]과 [onFailure]는 반영할 상태 변경을 돌려준다.
  /// 변경은 작업 종료 시 로딩 해제와 함께 한 번에 내보낸다.
  Future<bool> run({
    required Future<AuthChange?> Function() action,
    required String logPrefix,
    required String fallbackErrorMessage,
    AuthChange? onFailure,
    bool canRun = true,
  }) async {
    if (readState().isLoading || !canRun) {
      return false;
    }

    startLoading();

    AuthChange? outcome;

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

      update(
        (s) => (change == null ? s : change(s)).copyWith(isLoading: false),
      );
    }
  }
}
