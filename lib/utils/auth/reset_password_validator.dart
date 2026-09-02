/// 비밀번호 재설정 입력값 검증 결과.
///
/// 화면에서는 이 결과를 이용해
/// 각 입력창의 오류 표시와 사용자 안내 메시지를 처리한다.
class ResetPasswordValidationResult {
  const ResetPasswordValidationResult({
    required this.isValid,
    required this.passwordHasError,
    required this.passwordConfirmHasError,
    this.message,
  });

  final bool isValid;
  final bool passwordHasError;
  final bool passwordConfirmHasError;
  final String? message;
}

/// 비밀번호 재설정 화면의 입력값을 검증한다.
class ResetPasswordValidator {
  const ResetPasswordValidator._();

  static ResetPasswordValidationResult validate({
    required String password,
    required String passwordConfirm,
  }) {
    final passwordEmpty = password.isEmpty;
    final passwordConfirmEmpty = passwordConfirm.isEmpty;

    if (passwordEmpty || passwordConfirmEmpty) {
      return ResetPasswordValidationResult(
        isValid: false,
        passwordHasError: passwordEmpty,
        passwordConfirmHasError: passwordConfirmEmpty,
        message: '새 비밀번호를 모두 입력해 주세요.',
      );
    }

    if (password.length < 8 || password.length > 100) {
      return const ResetPasswordValidationResult(
        isValid: false,
        passwordHasError: true,
        passwordConfirmHasError: false,
        message: '비밀번호는 8자 이상 100자 이하여야 합니다.',
      );
    }

    if (password != passwordConfirm) {
      return const ResetPasswordValidationResult(
        isValid: false,
        passwordHasError: true,
        passwordConfirmHasError: true,
        message: '새 비밀번호가 일치하지 않습니다.',
      );
    }

    return const ResetPasswordValidationResult(
      isValid: true,
      passwordHasError: false,
      passwordConfirmHasError: false,
    );
  }
}