import 'package:flutter/material.dart';

import 'signup_form_label.dart';
import 'signup_input_decoration.dart';

class SignupPasswordFields extends StatelessWidget {
  const SignupPasswordFields({
    super.key,
    required this.passwordController,
    required this.passwordConfirmController,
    required this.obscurePassword,
    required this.obscurePasswordConfirm,
    required this.passwordHasError,
    required this.passwordConfirmHasError,
    required this.onPasswordChanged,
    required this.onPasswordConfirmChanged,
    required this.onTogglePasswordVisibility,
    required this.onTogglePasswordConfirmVisibility,
  });

  final TextEditingController passwordController;
  final TextEditingController passwordConfirmController;

  final bool obscurePassword;
  final bool obscurePasswordConfirm;

  final bool passwordHasError;
  final bool passwordConfirmHasError;

  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onPasswordConfirmChanged;

  final VoidCallback onTogglePasswordVisibility;
  final VoidCallback onTogglePasswordConfirmVisibility;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SignupFormLabel(text: '비밀번호', isRequired: true),

        const SizedBox(height: 6),

        TextField(
          controller: passwordController,
          obscureText: obscurePassword,
          textInputAction: TextInputAction.next,
          onChanged: onPasswordChanged,
          decoration: buildSignupInputDecoration(
            context: context,
            hintText: '비밀번호를 입력하세요',
            hasError: passwordHasError,
            suffixIcon: IconButton(
              onPressed: onTogglePasswordVisibility,
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),

        const SignupFormLabel(text: '비밀번호 확인', isRequired: true),

        const SizedBox(height: 6),

        TextField(
          controller: passwordConfirmController,
          obscureText: obscurePasswordConfirm,
          textInputAction: TextInputAction.next,
          onChanged: onPasswordConfirmChanged,
          decoration: buildSignupInputDecoration(
            context: context,
            hintText: '비밀번호를 다시 입력하세요',
            hasError: passwordConfirmHasError,
            suffixIcon: IconButton(
              onPressed: onTogglePasswordConfirmVisibility,
              icon: Icon(
                obscurePasswordConfirm
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
