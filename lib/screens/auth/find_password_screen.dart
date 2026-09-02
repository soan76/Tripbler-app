import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/account_recovery_provider.dart';
import '../../widgets/auth/recovery/password_recovery_account_form.dart';
import '../../widgets/auth/recovery/password_recovery_verification_section.dart';
import 'reset_password_screen.dart';

class FindPasswordScreen extends StatefulWidget {
  const FindPasswordScreen({super.key});

  @override
  State<FindPasswordScreen> createState() => _FindPasswordScreenState();
}

class _FindPasswordScreenState extends State<FindPasswordScreen> {
  /// Tripbler 로그인 아이디 입력 컨트롤러.
  final TextEditingController _loginIdController = TextEditingController();

  /// 사용자에게 연동된 이메일 입력 컨트롤러.
  final TextEditingController _emailController = TextEditingController();

  /// 이메일로 전달받은 6자리 인증코드 입력 컨트롤러.
  final TextEditingController _verificationCodeController =
      TextEditingController();

  bool _loginIdHasError = false;
  bool _emailHasError = false;
  bool _verificationCodeHasError = false;

  /// 인증코드 발송에 성공한 경우 true.
  ///
  /// true일 때 인증코드 입력 영역을 화면에 표시한다.
  bool _verificationCodeSent = false;

  @override
  void dispose() {
    _loginIdController.dispose();
    _emailController.dispose();
    _verificationCodeController.dispose();

    super.dispose();
  }

  /// 화면 하단에 사용자 안내 메시지를 표시한다.
  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.clearSnackBars();

    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 이메일의 기본 형식을 검사한다.
  ///
  /// 실제 계정 연동 여부와 이메일 유효성은 백엔드에서 다시 검증한다.
  bool _isValidEmail(String email) {
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    return emailPattern.hasMatch(email);
  }

  /// 인증코드 발송 전에 아이디와 이메일 입력값을 검사한다.
  bool _validateAccountInfo() {
    final loginId = _loginIdController.text.trim();
    final email = _emailController.text.trim();

    final loginIdHasError = loginId.isEmpty;
    final emailHasError = email.isEmpty || !_isValidEmail(email);

    setState(() {
      _loginIdHasError = loginIdHasError;
      _emailHasError = emailHasError;
    });

    if (loginIdHasError) {
      _showMessage('아이디를 입력해 주세요.');
      return false;
    }

    if (email.isEmpty) {
      _showMessage('이메일을 입력해 주세요.');
      return false;
    }

    if (!_isValidEmail(email)) {
      _showMessage('올바른 이메일 형식을 입력해 주세요.');
      return false;
    }

    return true;
  }

  /// 사용자가 아이디를 변경하면 기존 인증 상태를 초기화한다.
  ///
  /// 인증코드가 발송된 뒤 아이디를 변경할 경우
  /// 이전 인증코드를 그대로 사용할 수 없도록 한다.
  void _handleLoginIdChanged(String _) {
    if (!_loginIdHasError && !_verificationCodeSent) {
      return;
    }

    setState(() {
      _loginIdHasError = false;
      _resetVerificationState();
    });
  }

  /// 사용자가 이메일을 변경하면 기존 인증 상태를 초기화한다.
  void _handleEmailChanged(String _) {
    if (!_emailHasError && !_verificationCodeSent) {
      return;
    }

    setState(() {
      _emailHasError = false;
      _resetVerificationState();
    });
  }

  /// 아이디 또는 이메일 변경 시 기존 이메일 인증 상태를 제거한다.
  void _resetVerificationState() {
    if (!_verificationCodeSent) {
      return;
    }

    _verificationCodeSent = false;
    _verificationCodeHasError = false;
    _verificationCodeController.clear();
  }

  /// 인증코드 입력값이 변경되면 오류 표시를 제거하고
  /// 확인 버튼 활성화 상태를 다시 계산한다.
  void _handleVerificationCodeChanged(String _) {
    setState(() {
      _verificationCodeHasError = false;
    });
  }

  /// 비밀번호 재설정 인증코드를 이메일로 발송한다.
  ///
  /// 재전송인 경우 기존 인증코드 입력값을 초기화한다.
  Future<void> _sendVerificationCode({bool isResend = false}) async {
    if (!_validateAccountInfo()) {
      return;
    }

    FocusScope.of(context).unfocus();

    final recoveryProvider = context.read<AccountRecoveryProvider>();

    final success = await recoveryProvider.sendPasswordResetVerificationCode(
      loginId: _loginIdController.text.trim(),
      email: _emailController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(recoveryProvider.errorMessage ?? '인증코드 전송에 실패했습니다.');
      return;
    }

    setState(() {
      _verificationCodeSent = true;
      _verificationCodeHasError = false;

      if (isResend) {
        _verificationCodeController.clear();
      }
    });

    if (isResend) {
      _showMessage('인증코드를 다시 전송했습니다.');
    } else {
      _showMessage('입력한 정보가 일치하면 인증코드가 이메일로 전송됩니다.');
    }
  }

  /// 입력한 인증코드를 백엔드에서 검증한다.
  ///
  /// 인증 성공 시 resetToken을 받아
  /// 실제 비밀번호 변경 화면으로 이동한다.
  Future<void> _verifyCode() async {
    if (!_verificationCodeSent) {
      return;
    }

    final verificationCode = _verificationCodeController.text.trim();

    if (verificationCode.isEmpty) {
      setState(() {
        _verificationCodeHasError = true;
      });

      _showMessage('인증코드를 입력해 주세요.');
      return;
    }

    if (verificationCode.length != 6) {
      setState(() {
        _verificationCodeHasError = true;
      });

      _showMessage('인증코드는 6자리 숫자여야 합니다.');
      return;
    }

    setState(() {
      _verificationCodeHasError = false;
    });

    FocusScope.of(context).unfocus();

    final recoveryProvider = context.read<AccountRecoveryProvider>();

    final resetToken = await recoveryProvider
        .verifyPasswordResetVerificationCode(
          loginId: _loginIdController.text.trim(),
          email: _emailController.text.trim(),
          code: verificationCode,
        );

    if (!mounted) {
      return;
    }

    if (resetToken == null) {
      _showMessage(recoveryProvider.errorMessage ?? '인증코드 확인에 실패했습니다.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(resetToken: resetToken),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final recoveryProvider = context.watch<AccountRecoveryProvider>();

    final isLoading = recoveryProvider.isLoading;

    /// 인증코드가 정확히 6자리 입력된 경우에만
    /// 확인 버튼을 활성화한다.
    final canVerify =
        _verificationCodeSent &&
        _verificationCodeController.text.trim().length == 6 &&
        !isLoading;

    return Scaffold(
      backgroundColor: colorScheme.surface,

      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: isLoading
              ? null
              : () {
                  Navigator.of(context).pop();
                },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          '비밀번호 찾기',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),

                  // 화면 제목
                  Text(
                    '비밀번호 찾기',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 비밀번호 복구 안내 문구
                  Text(
                    '가입한 아이디와 연동된 이메일을 인증하여\n비밀번호를 재설정하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // 아이디 + 이메일 + 인증하기 버튼 영역
                  PasswordRecoveryAccountForm(
                    loginIdController: _loginIdController,
                    emailController: _emailController,
                    loginIdHasError: _loginIdHasError,
                    emailHasError: _emailHasError,
                    isLoading: isLoading,
                    showSendLoading: isLoading && !_verificationCodeSent,
                    onLoginIdChanged: _handleLoginIdChanged,
                    onEmailChanged: _handleEmailChanged,
                    onSendPressed: () {
                      _sendVerificationCode();
                    },
                  ),

                  // 인증코드 발송 성공 후에만
                  // 인증코드 입력 및 재전송 영역을 표시한다.
                  if (_verificationCodeSent) ...[
                    const SizedBox(height: 16),

                    PasswordRecoveryVerificationSection(
                      controller: _verificationCodeController,
                      hasError: _verificationCodeHasError,
                      isLoading: isLoading,
                      canVerify: canVerify,
                      onCodeChanged: _handleVerificationCodeChanged,
                      onVerifySubmitted: _verifyCode,
                      onResendPressed: () {
                        _sendVerificationCode(isResend: true);
                      },
                    ),
                  ],

                  const SizedBox(height: 40),

                  Divider(color: colorScheme.outlineVariant),

                  const SizedBox(height: 24),

                  // 인증코드 확인 버튼
                  Center(
                    child: SizedBox(
                      width: 180,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: canVerify ? _verifyCode : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          disabledBackgroundColor:
                              colorScheme.surfaceContainerHighest,
                          disabledForegroundColor: colorScheme.onSurfaceVariant,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isLoading && _verificationCodeSent
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '확인',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}