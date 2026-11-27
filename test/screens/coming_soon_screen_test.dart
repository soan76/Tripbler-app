import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/screens/coming_soon_screen.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
        '폭 320·글자 배율 $scale·$brightness에서 넘치지 않고 다른 화면으로 가는 방법을 알린다',
        (tester) async {
          tester.view.physicalSize = const Size(320, 480);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(320, 480),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const Scaffold(body: ComingSoonScreen(title: '면세')),
              ),
            ),
          );

          expect(find.text(ComingSoonScreen.message), findsOneWidget);
          expect(find.textContaining('아래 가운데 점을 눌러'), findsOneWidget);
          expect(find.textContaining('면세 화면은'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
