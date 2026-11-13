import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

        Consumer(
          builder: (context, ref, child) {
            final auth = ref.watch(authProvider);
            final notifier = ref.read(authProvider.notifier);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enabled: !auth.isLoading,
                    onChanged: (value) {
                      notifier.resetLoginIdAvailability();
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
                    onPressed: auth.isCheckingLoginId || auth.isLoading
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();

                            notifier.checkLoginIdAvailability(controller.text);
                          },
                    child: auth.isCheckingLoginId
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

        Consumer(
          builder: (context, ref, child) {
            final auth = ref.watch(authProvider);
            final message = auth.loginIdCheckMessage;

            if (message == null) {
              return const SizedBox.shrink();
            }

            final isAvailable = auth.isLoginIdAvailable == true;

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
