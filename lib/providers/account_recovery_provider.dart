import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../repositories/auth/auth_repository.dart';

/// 로그인하지 않은 사용자의 계정 복구 상태와 동작을 관리한다.
///
/// 담당 기능:
/// - 아이디 찾기 이메일 인증
/// - 비밀번호 재설정 이메일 인증
/// - resetToken 기반 비밀번호 변경
class AccountRecoveryProvider extends ChangeNotifier {
  AccountRecoveryProvider({AuthRepository? authRepository})
    : _authRepository = authRepository ?? AuthRepository(),
      _ownsRepository = authRepository == null;

  final AuthRepository _authRepository;

  /// 외부에서 Repository를 주입받은 경우 Provider가 임의로 dispose하지 않는다.
  final bool _ownsRepository;

  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 아이디 찾기 인증코드를 이메일로 전송한다.
  Future<bool> sendFindIdVerificationCode({required String email}) {
    return _runBoolAction(
      action: () {
        return _authRepository.sendFindIdVerificationCode(email: email.trim());
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
        return _authRepository.verifyFindIdVerificationCode(
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
        return _authRepository.sendPasswordResetVerificationCode(
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
        return _authRepository.verifyPasswordResetVerificationCode(
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
        return _authRepository.resetPassword(
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
    if (_isLoading) {
      return false;
    }

    _errorMessage = null;
    _setLoading(true);

    try {
      await action();

      return true;
    } on ApiException catch (error) {
      debugPrint('$debugLabel: $error');

      _errorMessage = error.message;

      return false;
    } catch (error) {
      debugPrint('$debugLabel: $error');

      _errorMessage = fallbackMessage;

      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 값을 반환하는 계정 복구 요청의 공통 처리.
  Future<T?> _runValueAction<T>({
    required Future<T> Function() action,
    required String debugLabel,
    required String fallbackMessage,
  }) async {
    if (_isLoading) {
      return null;
    }

    _errorMessage = null;
    _setLoading(true);

    try {
      return await action();
    } on ApiException catch (error) {
      debugPrint('$debugLabel: $error');

      _errorMessage = error.message;

      return null;
    } catch (error) {
      debugPrint('$debugLabel: $error');

      _errorMessage = fallbackMessage;

      return null;
    } finally {
      _setLoading(false);
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }

    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_ownsRepository) {
      _authRepository.dispose();
    }

    super.dispose();
  }
}