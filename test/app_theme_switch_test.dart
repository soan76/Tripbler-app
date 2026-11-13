import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/main.dart';
import 'package:tripbler/providers/settings_provider.dart';

void main() {
  testWidgets('설정에서 테마를 바꾸면 앱의 themeMode가 다크로 바뀐다', (tester) async {
    await tester.pumpWidget(
      buildAppScope(child: const TripblerApp(home: SizedBox())),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    container.read(settingsProvider.notifier).toggleTheme();
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
