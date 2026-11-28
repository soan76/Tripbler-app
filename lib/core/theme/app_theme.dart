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

/// 주의(한도 근접·오래된 값·확인 필요) 색. colorScheme에 주황 계열이 없어 테마에서 함께 정의한다.
/// 오류(error)보다 한 단계 약한 상태에 쓴다. 값은 Material 3 주황 색조(라이트 40/90/10, 다크 80/30/90)다.
extension WarningColors on ColorScheme {
  /// 글자·막대처럼 표면색 위에 바로 놓는 주의색.
  Color get warning => brightness == Brightness.light
      ? const Color(0xFF8A4B00)
      : const Color(0xFFFFB870);

  /// 주의 띠·꼬리표 배경.
  Color get warningContainer => brightness == Brightness.light
      ? const Color(0xFFFFDDB8)
      : const Color(0xFF693800);

  /// [warningContainer] 위의 글자색.
  Color get onWarningContainer => brightness == Brightness.light
      ? const Color(0xFF2C1600)
      : const Color(0xFFFFDDB8);
}

class AppTheme {
  AppTheme._();

  static const Color _seedColor = Colors.blue;

  /// 버튼·입력창 모서리 둥글기. 앱 전체를 4로 맞춘다(사용자 결정, 2026-11-21).
  /// 위젯에서 모양을 따로 지정하지 않으면 이 값을 쓴다.
  static const double cornerRadius = 4;

  static const BorderRadius _cornerRadius = BorderRadius.all(
    Radius.circular(cornerRadius),
  );

  static const ButtonStyle _buttonStyle = ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: _cornerRadius),
    ),
  );

  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
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

      filledButtonTheme: const FilledButtonThemeData(style: _buttonStyle),
      elevatedButtonTheme: const ElevatedButtonThemeData(style: _buttonStyle),
      outlinedButtonTheme: const OutlinedButtonThemeData(style: _buttonStyle),
      textButtonTheme: const TextButtonThemeData(style: _buttonStyle),

      // 외곽선 입력창으로 통일한다. 채움색까지 두면 떠오른 라벨이 채움 경계에 걸쳐
      // 어색하므로 채우지 않는다. 테두리 색은 Material 3 기본값(평소 outline, 포커스
      // primary 2dp, 오류 error)을 써서 밝은 야외에서도 입력칸 경계가 보이게 한다.
      // 채움이 필요한 입력창은 위젯에서 filled·fillColor를 직접 지정한다.
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: _cornerRadius),
      ),
    );
  }
}
