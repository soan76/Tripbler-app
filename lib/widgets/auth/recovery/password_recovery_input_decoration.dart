import 'package:flutter/material.dart';

/// 비밀번호 복구 화면에서 사용하는 공통 입력창 스타일.
///
/// 아이디, 이메일, 인증코드 입력창이 같은 디자인을 사용하므로
/// 각 위젯에서 InputDecoration 코드를 중복 작성하지 않도록 분리한다.
InputDecoration buildPasswordRecoveryInputDecoration(
  BuildContext context, {
  required String hintText,
  required bool hasError,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
    filled: true,
    fillColor: colorScheme.surface,
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
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    ),
  );
}