import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import 'signup_form_label.dart';
import 'signup_input_decoration.dart';

class SignupLoginIdField extends StatelessWidget {
  const SignupLoginIdField({
    super.key,
    required this.controller,
    required this.hasError,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool hasError;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SignupFormLabel(text: '아이디', isRequired: true),

        const SizedBox(height: 6),

        Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enabled: !authProvider.isLoading,
                    onChanged: (value) {
                      authProvider.resetLoginIdAvailability();
                      onChanged(value);
                    },
                    decoration: buildSignupInputDecoration(
                      context: context,
                      hintText: '아이디를 입력하세요',
                      hasError: hasError,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed:
                        authProvider.isCheckingLoginId || authProvider.isLoading
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();

                            authProvider.checkLoginIdAvailability(
                              controller.text,
                            );
                          },
                    child: authProvider.isCheckingLoginId
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '중복확인',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            );
          },
        ),

        Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            final message = authProvider.loginIdCheckMessage;

            if (message == null) {
              return const SizedBox.shrink();
            }

            final isAvailable = authProvider.isLoginIdAvailable == true;

            return Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isAvailable ? colorScheme.primary : colorScheme.error,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}