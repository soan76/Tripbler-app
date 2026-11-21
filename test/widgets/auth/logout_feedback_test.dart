import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/widgets/auth/logout_feedback.dart';

/// 로그인 여부와 다시 시도 결과만 흉내 내는 대역.
class _FakeAuth extends AuthNotifier {
  _FakeAuth({this.retryResults = const []});

  /// 다시 시도마다 차례로 돌려줄 결과. 다 쓰면 true.
  final List<bool> retryResults;
  int retryCount = 0;

  /// 새로 로그인한 것처럼 로그인 상태로 바꾼다.
  void signIn() {
    state = state.copyWith(isAuthenticated: true);
  }

  @override
  AuthState build() => const AuthState(isInitialized: true);

  @override
  Future<bool> retryClearLocalTokens() async {
    final index = retryCount++;
    return index < retryResults.length ? retryResults[index] : true;
  }
}

const _otherMessage = '다른 안내';

void main() {
  late _FakeAuth fake;
  late GlobalKey<ScaffoldMessengerState> messengerKey;

  Widget app({required bool withMessenger}) {
    return ProviderScope(
      overrides: [authProvider.overrideWith(() => fake)],
      child: withMessenger
          ? MaterialApp(
              scaffoldMessengerKey: messengerKey,
              home: const Scaffold(body: SizedBox.shrink()),
            )
          : const SizedBox.shrink(),
    );
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    List<bool> retryResults = const [],
  }) {
    fake = _FakeAuth(retryResults: retryResults);
    messengerKey = GlobalKey<ScaffoldMessengerState>();

    return tester.pumpWidget(app(withMessenger: true));
  }

  void showFailure() {
    showLogoutResult(
      messenger: messengerKey.currentState!,
      notifier: fake,
      localTokensCleared: false,
    );
  }

  tearDown(() {
    // 테스트마다 안내 구독이 남지 않아야 한다.
    expect(debugLogoutFeedbackSubscriptionCount, 0);
  });

  testWidgets('안내가 보이는 동안 로그인하면 실패 안내를 닫는다', (tester) async {
    await pumpApp(tester);
    showFailure();
    await tester.pumpAndSettle();
    expect(find.text(localTokenClearFailedMessage), findsOneWidget);
    expect(debugLogoutFeedbackSubscriptionCount, 1);

    fake.signIn();
    await tester.pumpAndSettle();

    expect(find.text(localTokenClearFailedMessage), findsNothing);
  });

  testWidgets(
    '다른 SnackBar 뒤에서 대기 중에 로그인하면 다른 SnackBar는 그대로 두고, 실패 안내가 보이면 닫는다',
    (tester) async {
      await pumpApp(tester);
      final other = messengerKey.currentState!.showSnackBar(
        const SnackBar(content: Text(_otherMessage), persist: true),
      );
      await tester.pumpAndSettle();

      SnackBarClosedReason? otherReason;
      other.closed.then((reason) => otherReason = reason);

      // 실패 안내는 다른 안내가 내려가는 동안 대기열에서 기다린다.
      showFailure();
      await tester.pump();
      fake.signIn();
      await tester.pump(const Duration(milliseconds: 50));

      // 다른 안내는 아직 내려가는 중이며, 실패 안내는 그려지지 않았다.
      expect(tester.takeException(), isNull);
      expect(find.text(_otherMessage), findsOneWidget);
      expect(find.text(localTokenClearFailedMessage), findsNothing);

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(otherReason, SnackBarClosedReason.hide);
      expect(find.text(_otherMessage), findsNothing);
      expect(find.text(localTokenClearFailedMessage), findsNothing);
    },
  );

  testWidgets('안내가 닫힌 뒤 로그인하면 다른 SnackBar를 건드리지 않는다', (tester) async {
    await pumpApp(tester);
    showFailure();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text(localTokenClearFailedMessage), findsNothing);
    expect(debugLogoutFeedbackSubscriptionCount, 0);

    messengerKey.currentState!.showSnackBar(
      const SnackBar(content: Text(_otherMessage), persist: true),
    );
    await tester.pumpAndSettle();

    fake.signIn();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_otherMessage), findsOneWidget);
  });

  testWidgets('다시 시도가 실패하면 안내를 다시 띄우고 구독은 하나만 남긴다', (tester) async {
    await pumpApp(tester, retryResults: [false]);
    showFailure();
    await tester.pumpAndSettle();

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fake.retryCount, 1);
    expect(find.text(localTokenClearFailedMessage), findsOneWidget);
    expect(debugLogoutFeedbackSubscriptionCount, 1);

    fake.signIn();
    await tester.pumpAndSettle();

    expect(find.text(localTokenClearFailedMessage), findsNothing);
  });

  testWidgets('ScaffoldMessenger가 폐기된 뒤 로그인하면 구독을 정리한다', (tester) async {
    await pumpApp(tester);
    showFailure();
    await tester.pumpAndSettle();
    expect(debugLogoutFeedbackSubscriptionCount, 1);

    // 상태 컨테이너는 그대로 두고 ScaffoldMessenger만 없앤다.
    await tester.pumpWidget(app(withMessenger: false));
    expect(debugLogoutFeedbackSubscriptionCount, 1);

    fake.signIn();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(debugLogoutFeedbackSubscriptionCount, 0);
  });
}
