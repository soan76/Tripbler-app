import 'package:flutter/material.dart';

import 'password_recovery_input_decoration.dart';

/// 비밀번호 복구를 위한 계정 정보 입력 영역.
///
/// 담당 UI:
/// - Tripbler 아이디 입력
/// - 연동 이메일 입력
/// - 이메일 인증코드 발송 버튼
///
/// 실제 API 호출이나 상태 변경은 화면에서 담당하고,
/// 이 위젯은 전달받은 callback만 실행한다.
class PasswordRecoveryAccountForm extends StatelessWidget {
  const PasswordRecoveryAccountForm({
    super.key,
    required this.loginIdController,
    required this.emailController,
    required this.loginIdHasError,
    required this.emailHasError,
    required this.isLoading,
    required this.showSendLoading,
    required this.onLoginIdChanged,
    required this.onEmailChanged,
    required this.onSendPressed,
  });

  final TextEditingController loginIdController;
  final TextEditingController emailController;

  final bool loginIdHasError;
  final bool emailHasError;

  final bool isLoading;

  /// 인증코드 최초 발송 중 로딩 아이콘 표시 여부.
  final bool showSendLoading;

  final ValueChanged<String> onLoginIdChanged;
  final ValueChanged<String> onEmailChanged;

  final VoidCallback onSendPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildLoginIdField(context),

        const SizedBox(height: 16),

        _buildEmailField(context),
      ],
    );
  }

  /// 아이디 입력 행
  Widget _buildLoginIdField(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildLabel(context, '아이디'),

        Expanded(
          child: TextField(
            controller: loginIdController,
            enabled: !isLoading,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            onChanged: onLoginIdChanged,
            decoration: buildPasswordRecoveryInputDecoration(
              context,
              hintText: '아이디를 입력하세요',
              hasError: loginIdHasError,
            ),
          ),
        ),
      ],
    );
  }

  /// 이메일 입력 및 인증코드 발송 행
  Widget _buildEmailField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildLabel(context, '이메일'),

        Expanded(
          child: TextField(
            controller: emailController,
            enabled: !isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onChanged: onEmailChanged,
            onSubmitted: (_) {
              if (!isLoading) {
                onSendPressed();
              }
            },
            decoration: buildPasswordRecoveryInputDecoration(
              context,
              hintText: '연동된 이메일을 입력하세요',
              hasError: emailHasError,
            ),
          ),
        ),

        const SizedBox(width: 8),

        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: isLoading ? null : onSendPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              disabledBackgroundColor: colorScheme.surfaceContainerHighest,
              disabledForegroundColor: colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: showSendLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '인증하기',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  /// 입력창 왼쪽 공통 라벨.
  Widget _buildLabel(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 60,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}