import 'package:flutter/material.dart';

/// 값의 증감을 나타내는 색. colorScheme에 초록 계열이 없어 테마에서 함께 정의한다.
extension ChangeColors on ColorScheme {
  /// 늘어난 값. 표면색 위 대비를 [loss]와 비슷하게(라이트 약 6:1, 다크 약 10:1) 맞춘다.
  Color get gain => brightness == Brightness.light
      ? const Color(0xFF146C2E)
      : const Color(0xFF7BD88F);

  /// 줄어든 값.
  Color get loss => error;
}

class AppTheme {
  AppTheme._();

  static const Color _seedColor = Colors.blue;

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,

      scaffoldBackgroundColor: colorScheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),

      drawerTheme: DrawerThemeData(backgroundColor: colorScheme.surface),

      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,

      scaffoldBackgroundColor: colorScheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),

      drawerTheme: DrawerThemeData(backgroundColor: colorScheme.surface),

      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }
}
