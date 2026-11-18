import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/map/current_location_button.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('로딩 표시는 버튼 배경에 맞는 테마 색을 쓴다($brightness)', (tester) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Stack(
              children: [
                CurrentLocationButton(
                  isLoading: true,
                  bottom: 24,
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      );

      final colorScheme = theme.colorScheme;
      final button = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );

      expect(button.backgroundColor, colorScheme.primaryContainer);
      expect(indicator.color, colorScheme.onPrimaryContainer);
      expect(indicator.color, isNot(Colors.white));
    });
  }
}
