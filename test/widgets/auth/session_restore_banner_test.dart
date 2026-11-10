import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/auth/session_restore_banner.dart';

Widget _wrap(
  Widget child, {
  double width = 400,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('안내 문구와 다시 시도 버튼을 보여주고 누르면 onRetry를 부른다', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      _wrap(
        SessionRestoreBanner(isRetrying: false, onRetry: () => retryCount++),
      ),
    );

    expect(find.text('로그인 정보를 확인하지 못했습니다'), findsOneWidget);
    expect(find.text(sessionRestoreBannerDetail), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    expect(retryCount, 1);
  });

  testWidgets('다시 시도 버튼의 터치 영역은 48dp 이상이다', (tester) async {
    await tester.pumpWidget(
      _wrap(SessionRestoreBanner(isRetrying: false, onRetry: () {})),
    );

    final size = tester.getSize(find.byType(TextButton));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('다시 시도 중이면 버튼을 막고 진행 표시를 보여준다', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      _wrap(
        SessionRestoreBanner(isRetrying: true, onRetry: () => retryCount++),
      ),
    );

    expect(find.text('다시 시도'), findsNothing);
    expect(find.text('확인 중'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    expect(retryCount, 0);
  });

  for (final width in [320.0, 360.0]) {
    for (final retrying in [false, true]) {
      testWidgets('폭 $width, 다시 시도 중=$retrying에서 넘치지 않는다', (tester) async {
        await tester.pumpWidget(
          _wrap(
            SessionRestoreBanner(isRetrying: retrying, onRetry: () {}),
            width: width,
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('글자를 크게 키우면 버튼을 문구 아래로 내리고 넘치지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SessionRestoreBanner(isRetrying: false, onRetry: () {}),
        width: 320,
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);

    final titleBottom = tester
        .getBottomLeft(find.text('로그인 정보를 확인하지 못했습니다'))
        .dy;
    final buttonTop = tester.getTopLeft(find.byType(TextButton)).dy;
    expect(buttonTop, greaterThanOrEqualTo(titleBottom));
  });

  testWidgets('다크 모드에서도 넘치지 않고 그려진다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SessionRestoreBanner(isRetrying: false, onRetry: () {}),
        width: 320,
        brightness: Brightness.dark,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
