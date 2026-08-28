import 'package:flutter/material.dart';

class SignupFormLabel extends StatelessWidget {
  const SignupFormLabel({
    super.key,
    required this.text,
    this.isRequired = false,
  });

  final String text;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (isRequired)
            TextSpan(
              text: ' *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}