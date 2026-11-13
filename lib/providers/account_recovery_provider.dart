import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../core/network/api_exception.dart';
import '../repositories/auth/auth_repository.dart';

/// 계정 복구 요청에 쓰는 저장소. 로그인 상태를 다루는 AuthProvider와는 별도 인스턴스다.
final accountRecoveryRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = AuthRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

class AccountRecoveryState {
  const AccountRecoveryState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  AccountRecoveryState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return AccountRecoveryState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

/// 로그인하지 않은 사용자의 계정 복구 상태와 동작을 관리한다.
///
/// 담당 기능:
/// - 아이디 찾기 이메일 인증
/// - 비밀번호 재설정 이메일 인증
/// - resetToken 기반 비밀번호 변경
class AccountRecoveryNotifier extends Notifier<AccountRecoveryState> {
  @override
  AccountRecoveryState build() => const AccountRecoveryState();

  AuthRepository get _repository => ref.read(accountRecoveryRepositoryProvider);

  /// 아이디 찾기 인증코드를 이메일로 전송한다.
  Future<bool> sendFindIdVerificationCode({required String email}) {
    return _runBoolAction(
      action: () {
        return _repository.sendFindIdVerificationCode(email: email.trim());
      },
      debugLabel: '아이디 찾기 인증코드 전송 실패',
      fallbackMessage: '인증코드 전송 중 오류가 발생했습니다.',
    );
  }

  /// 아이디 찾기 인증코드를 검증하고 loginId를 반환한다.
  ///
  /// 실패하면 null을 반환한다.
  Future<String?> verifyFindIdVerificationCode({
    required String email,
    required String code,
  }) {
    return _runValueAction<String>(
      action: () {
        return _repository.verifyFindIdVerificationCode(
          email: email.trim(),
          code: code.trim(),
        );
      },
      debugLabel: '아이디 찾기 인증코드 확인 실패',
      fallbackMessage: '인증코드 확인 중 오류가 발생했습니다.',
    );
  }

  /// 비밀번호 재설정 인증코드를 이메일로 전송한다.
  Future<bool> sendPasswordResetVerificationCode({
    required String loginId,
    required String email,
  }) {
    return _runBoolAction(
      action: () {
        return _repository.sendPasswordResetVerificationCode(
          loginId: loginId.trim(),
          email: email.trim(),
        );
      },
      debugLabel: '비밀번호 재설정 인증코드 전송 실패',
      fallbackMessage: '인증코드 전송 중 오류가 발생했습니다.',
    );
  }

  /// 비밀번호 재설정 인증코드를 검증하고 resetToken을 반환한다.
  ///
  /// 실패하면 null을 반환한다.
  Future<String?> verifyPasswordResetVerificationCode({
    required String loginId,
    required String email,
    required String code,
  }) {
    return _runValueAction<String>(
      action: () {
        return _repository.verifyPasswordResetVerificationCode(
          loginId: loginId.trim(),
          email: email.trim(),
          code: code.trim(),
        );
      },
      debugLabel: '비밀번호 재설정 인증코드 확인 실패',
      fallbackMessage: '인증코드 확인 중 오류가 발생했습니다.',
    );
  }

  /// resetToken을 사용해 새 비밀번호로 변경한다.
  Future<bool> resetPassword({
    required String resetToken,
    required String newPassword,
  }) {
    return _runBoolAction(
      action: () {
        return _repository.resetPassword(
          resetToken: resetToken,
          newPassword: newPassword,
        );
      },
      debugLabel: '비밀번호 재설정 실패',
      fallbackMessage: '비밀번호 재설정 중 오류가 발생했습니다.',
    );
  }

  /// 반환값이 없는 계정 복구 요청의 공통 처리.
  Future<bool> _runBoolAction({
    required Future<void> Function() action,
    required String debugLabel,
    required String fallbackMessage,
  }) async {
    final result = await _runValueAction<bool>(
      action: () async {
        await action();
        return true;
      },
      debugLabel: debugLabel,
      fallbackMessage: fallbackMessage,
    );

    return result ?? false;
  }

  /// 값을 반환하는 계정 복구 요청의 공통 처리.
  Future<T?> _runValueAction<T>({
    required Future<T> Function() action,
    required String debugLabel,
    required String fallbackMessage,
  }) async {
    if (state.isLoading) {
      return null;
    }

    state = state.copyWith(isLoading: true, clearErrorMessage: true);

    String? failureMessage;

    try {
      return await action();
    } on ApiException catch (error) {
      debugPrint('$debugLabel: $error');

      failureMessage = error.message;

      return null;
    } catch (error) {
      debugPrint('$debugLabel: $error');

      failureMessage = fallbackMessage;

      return null;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isLoading: false, errorMessage: failureMessage);
      }
    }
  }

  void clearError() {
    if (state.errorMessage == null) {
      return;
    }

    state = state.copyWith(clearErrorMessage: true);
  }
}

final accountRecoveryProvider =
    NotifierProvider<AccountRecoveryNotifier, AccountRecoveryState>(
      AccountRecoveryNotifier.new,
    );
