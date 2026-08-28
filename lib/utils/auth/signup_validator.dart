class SignupValidationResult {
  const SignupValidationResult({
    required this.isValid,
    this.message,
    this.loginIdHasError = false,
    this.passwordHasError = false,
    this.passwordConfirmHasError = false,
  });

  final bool isValid;
  final String? message;

  final bool loginIdHasError;
  final bool passwordHasError;
  final bool passwordConfirmHasError;

  const SignupValidationResult.valid()
    : isValid = true,
      message = null,
      loginIdHasError = false,
      passwordHasError = false,
      passwordConfirmHasError = false;
}

class SignupValidator {
  const SignupValidator._();

  static SignupValidationResult validate({
    required String loginId,
    required String password,
    required String passwordConfirm,
    required String nickname,
  }) {
    final loginIdMissing = loginId.isEmpty;
    final passwordMissing = password.isEmpty;
    final passwordConfirmMissing = passwordConfirm.isEmpty;

    // 필수 입력값 검사
    if (loginIdMissing || passwordMissing || passwordConfirmMissing) {
      return SignupValidationResult(
        isValid: false,
        message: '필수 입력 항목을 입력해 주세요.',
        loginIdHasError: loginIdMissing,
        passwordHasError: passwordMissing,
        passwordConfirmHasError: passwordConfirmMissing,
      );
    }

    // 아이디 길이 검사
    if (loginId.length < 4 || loginId.length > 30) {
      return const SignupValidationResult(
        isValid: false,
        message: '아이디는 4자 이상 30자 이하여야 합니다.',
        loginIdHasError: true,
      );
    }

    // 비밀번호 길이 검사
    if (password.length < 8 || password.length > 72) {
      return const SignupValidationResult(
        isValid: false,
        message: '비밀번호는 8자 이상 72자 이하여야 합니다.',
        passwordHasError: true,
      );
    }

    // 비밀번호 확인
    if (password != passwordConfirm) {
      return const SignupValidationResult(
        isValid: false,
        message: '비밀번호가 일치하지 않습니다.',
        passwordHasError: true,
        passwordConfirmHasError: true,
      );
    }

    // 닉네임은 선택값이며 입력했을 때만 길이 검사
    if (nickname.isNotEmpty && nickname.length > 20) {
      return const SignupValidationResult(
        isValid: false,
        message: '닉네임은 20자 이하여야 합니다.',
      );
    }

    return const SignupValidationResult.valid();
  }
}
