import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'password_recovery_input_decoration.dart';

/// 이메일 인증코드 확인 영역.
///
/// 담당 UI:
/// - 6자리 숫자 인증코드 입력
/// - 인증코드 재전송
///
/// 인증코드 검증과 API 호출은 부모 화면에서 담당한다.
class PasswordRecoveryVerificationSection extends StatelessWidget {
  const PasswordRecoveryVerificationSection({
    super.key,
    required this.controller,
    required this.hasError,
    required this.isLoading,
    required this.canVerify,
    required this.onCodeChanged,
    required this.onVerifySubmitted,
    required this.onResendPressed,
  });

  final TextEditingController controller;

  final bool hasError;
  final bool isLoading;
  final bool canVerify;

  final ValueChanged<String> onCodeChanged;

  final VoidCallback onVerifySubmitted;
  final VoidCallback onResendPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            '인증확인',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),

        Expanded(
          child: TextField(
            controller: controller,
            enabled: !isLoading,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,

            // 인증코드는 숫자만 입력할 수 있다.
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],

            onChanged: onCodeChanged,

            onSubmitted: (_) {
              if (canVerify) {
                onVerifySubmitted();
              }
            },

            decoration: buildPasswordRecoveryInputDecoration(
              context,
              hintText: '6자리 인증코드',
              hasError: hasError,
            ).copyWith(counterText: ''),
          ),
        ),

        const SizedBox(width: 8),

        TextButton(
          onPressed: isLoading ? null : onResendPressed,
          child: const Text(
            '재전송',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}