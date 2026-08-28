import 'package:flutter/material.dart';

InputDecoration buildSignupInputDecoration({
  required BuildContext context,
  required String hintText,
  Widget? suffixIcon,
  bool hasError = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  return InputDecoration(
    hintText: hintText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: colorScheme.surface,
    hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: hasError ? colorScheme.error : colorScheme.outlineVariant,
        width: hasError ? 1.5 : 1,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: hasError ? colorScheme.error : colorScheme.primary,
        width: 1.5,
      ),
    ),
  );
}