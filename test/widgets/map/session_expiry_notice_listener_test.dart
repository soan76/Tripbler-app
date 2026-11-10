import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/map/session_expiry_notice_listener.dart';

class _Notice {
  bool hasNotice = true;
  int consumeCount = 0;
  int loginCount = 0;

  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  Widget build({required bool isActive}) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      home: Scaffold(
        body: SessionExpiryNoticeListener(
          isActive: isActive,
          hasNotice: hasNotice,
          onConsume: () {
            consumeCount++;
            hasNotice = false;
          },
          onLogin: () => loginCount++,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('지도 탭이 활성이면 안내를 한 번 표시하고 소비한다', (tester) async {
    final notice = _Notice();

    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pump();

    expect(find.text(SessionExpiryNoticeListener.message), findsOneWidget);
    expect(notice.consumeCount, 1);

    // SnackBar가 다 나타난 뒤 로그인 버튼을 누른다.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('로그인'));
    expect(notice.loginCount, 1);
  });

  testWidgets('다른 탭에 있는 동안에는 표시·소비하지 않고 지도 탭으로 돌아오면 한 번 표시한다', (tester) async {
    final notice = _Notice();

    // 검색 직후 다른 탭(번역 등)으로 이동한 상태
    await tester.pumpWidget(notice.build(isActive: false));
    await tester.pump();

    expect(find.text(SessionExpiryNoticeListener.message), findsNothing);
    expect(notice.consumeCount, 0);

    // 지도 탭으로 돌아옴
    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pump();

    expect(find.text(SessionExpiryNoticeListener.message), findsOneWidget);
    expect(notice.consumeCount, 1);

    // 탭을 다시 오가도 반복 표시하지 않는다.
    await tester.pumpWidget(notice.build(isActive: false));
    await tester.pump();
    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pump();

    expect(notice.consumeCount, 1);
  });

  testWidgets('다른 탭으로 이동하면 표시 중인 만료 안내를 닫는다', (tester) async {
    final notice = _Notice();

    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(SessionExpiryNoticeListener.message), findsOneWidget);

    await tester.pumpWidget(notice.build(isActive: false));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(SessionExpiryNoticeListener.message), findsNothing);
    // 지도 탭으로 돌아와도 다시 띄우지 않는다(한 번만 표시).
    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pumpAndSettle();
    expect(find.text(SessionExpiryNoticeListener.message), findsNothing);
    expect(notice.consumeCount, 1);
  });

  testWidgets('만료 안내가 다른 SnackBar로 바뀐 뒤 탭을 옮기면 그 SnackBar는 닫지 않는다', (
    tester,
  ) async {
    final notice = _Notice();

    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 지도 화면의 다른 안내가 만료 안내를 대신한다.
    notice.messengerKey.currentState!
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('다른 안내'), duration: Duration(seconds: 6)),
      );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text(SessionExpiryNoticeListener.message), findsNothing);
    expect(find.text('다른 안내'), findsOneWidget);

    await tester.pumpWidget(notice.build(isActive: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('다른 안내'), findsOneWidget);
  });

  testWidgets('만료 안내가 이미 닫힌 뒤 탭을 옮기면 다른 SnackBar는 그대로 둔다', (tester) async {
    final notice = _Notice();

    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pump();
    // 표시 시간이 지나 저절로 닫힘
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(SessionExpiryNoticeListener.displayDuration);
    await tester.pumpAndSettle();
    expect(find.text(SessionExpiryNoticeListener.message), findsNothing);

    notice.messengerKey.currentState!.showSnackBar(
      const SnackBar(content: Text('다른 안내'), duration: Duration(seconds: 6)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pumpWidget(notice.build(isActive: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('다른 안내'), findsOneWidget);
  });

  testWidgets('만료 안내가 대기열에 있을 때 탭을 옮기면 차례가 오는 대로 닫는다', (
    tester,
  ) async {
    final notice = _Notice();

    // 다른 SnackBar가 떠 있는 상태에서 지도 탭으로 와 만료 안내가 대기열에 들어간다.
    await tester.pumpWidget(notice.build(isActive: false));
    notice.messengerKey.currentState!.showSnackBar(
      const SnackBar(content: Text('다른 안내'), duration: Duration(seconds: 6)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pump();
    expect(notice.consumeCount, 1);

    // 앞의 SnackBar(만료 안내를 띄우며 닫는 중)가 사라지는 동안 탭을 옮긴다.
    await tester.pumpWidget(notice.build(isActive: false));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(SessionExpiryNoticeListener.message), findsNothing);
    expect(find.text('다른 안내'), findsNothing);
    // 6초 표시 시간을 기다리지 않고 이미 닫혔다.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('지도 탭으로 돌아오기 전에 안내가 무효가 되면(재로그인) 표시하지 않는다', (tester) async {
    final notice = _Notice();

    await tester.pumpWidget(notice.build(isActive: false));
    await tester.pump();

    notice.hasNotice = false;
    await tester.pumpWidget(notice.build(isActive: true));
    await tester.pump();

    expect(find.text(SessionExpiryNoticeListener.message), findsNothing);
    expect(notice.consumeCount, 0);
  });
}
