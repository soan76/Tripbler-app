import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
// 분리한 파일을 직접 가져오지 않는다. 기존 import 경로 하나로 생성자와 애니메이션 정책을
// 모두 쓸 수 있어야 한다.
import 'package:tripbler/widgets/charts/currency_swap_pair.dart';

const swapKeyValue = 'market-chart-swap';
const usdPick = 'market-chart-pick-fiat:USD';
const krwPick = 'market-chart-pick-fiat:KRW';

final swapButton = find.byKey(const ValueKey(swapKeyValue));
final usdButton = find.byKey(const ValueKey(usdPick));
final krwButton = find.byKey(const ValueKey(krwPick));
final usdSide = find.byKey(const ValueKey('pair-fiat:USD'));
final krwSide = find.byKey(const ValueKey('pair-fiat:KRW'));

Future<void> pumpPair(
  WidgetTester tester, {
  bool swapped = false,
  VoidCallback? onSwap,
  VoidCallback? onLeft,
  VoidCallback? onRight,
  bool reduceMotion = false,
  bool instant = false,
}) => tester.pumpWidget(
  MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Scaffold(
      body: InstantSwapScope(
        instant: instant,
        child: CurrencySwapPair(
          baseCurrency: DisplayCurrency.fromFiat(findCurrencyByCode('USD')!),
          targetCurrency: DisplayCurrency.fromFiat(findCurrencyByCode('KRW')!),
          swapped: swapped,
          onSwap: onSwap,
          onPickShownBase: onLeft,
          onPickShownTarget: onRight,
        ),
      ),
    ),
  ),
);

/// 지금 초점이 있는 스왑·통화 선택 버튼의 키.
String? focusedButton() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? found;
  void check(Element element) {
    final key = element.widget.key;
    if (key is ValueKey<String> &&
        (key.value == swapKeyValue ||
            key.value.startsWith('market-chart-pick-'))) {
      found = key.value;
    }
  }

  check(context as Element);
  context.visitAncestorElements((element) {
    if (found == null) check(element);
    return found == null;
  });
  return found;
}

Future<List<String?>> tabThrough(WidgetTester tester, int count) async {
  final order = <String?>[];
  for (var i = 0; i < count; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    order.add(focusedButton());
  }
  return order;
}

void main() {
  group('swap', () {
    testWidgets('tapping asks once and the parent decides the direction', (
      tester,
    ) async {
      var swaps = 0;
      await pumpPair(tester, onSwap: () => swaps++);
      final usdBefore = tester.getRect(usdSide);
      final krwBefore = tester.getRect(krwSide);
      expect(usdBefore.left, lessThan(krwBefore.left));

      await tester.tap(swapButton);
      await tester.pumpAndSettle();
      // 부모가 swapped를 바꾸기 전에는 자리가 그대로다.
      expect(swaps, 1);
      expect(tester.getRect(usdSide), usdBefore);

      await pumpPair(tester, swapped: true, onSwap: () => swaps++);
      await tester.pumpAndSettle();
      expect(tester.getRect(krwSide).left, usdBefore.left);
      expect(tester.getRect(usdSide).right, krwBefore.right);
      expect(swaps, 1);
    });

    testWidgets('the tooltip names the currency that becomes the base', (
      tester,
    ) async {
      await pumpPair(tester, onSwap: () {});
      expect(find.byTooltip('KRW 기준으로 바꾸기'), findsOneWidget);

      await pumpPair(tester, swapped: true, onSwap: () {});
      await tester.pumpAndSettle();
      expect(find.byTooltip('USD 기준으로 바꾸기'), findsOneWidget);
      expect(find.byTooltip('KRW 기준으로 바꾸기'), findsNothing);
    });

    testWidgets('currencies move for 300ms and pass each other', (
      tester,
    ) async {
      await pumpPair(tester, onSwap: () {});
      final usdStart = tester.getRect(usdSide);

      await pumpPair(tester, swapped: true, onSwap: () {});
      await tester.pump(const Duration(milliseconds: 150));
      final usdMiddle = tester.getRect(usdSide);
      final krwMiddle = tester.getRect(krwSide);
      expect(usdMiddle.left, greaterThan(usdStart.left));
      // 겹치지 않게 위아래로 비켜 지나간다.
      expect(usdMiddle.center.dy, lessThan(krwMiddle.center.dy));

      await tester.pump(const Duration(milliseconds: 149));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester.getRect(usdSide).center.dy,
        tester.getRect(krwSide).center.dy,
      );
    });

    for (final (name, reduceMotion, instant, wasEnabled) in const [
      ('reduced motion', true, false, true),
      ('an instant scope', false, true, true),
      ('a button that was off', false, false, false),
    ]) {
      testWidgets('$name shows the new direction at once', (tester) async {
        await pumpPair(
          tester,
          onSwap: wasEnabled ? () {} : null,
          reduceMotion: reduceMotion,
          instant: instant,
        );
        await pumpPair(
          tester,
          swapped: true,
          onSwap: () {},
          reduceMotion: reduceMotion,
          instant: instant,
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(
          tester.getRect(krwSide).left,
          lessThan(tester.getRect(usdSide).left),
        );
      });
    }

    testWidgets('without onSwap the button is off and hides the tooltip', (
      tester,
    ) async {
      await pumpPair(tester);
      expect(tester.widget<IconButton>(swapButton).onPressed, isNull);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('the motion policy is reachable from the existing import', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        InstantSwapScope(
          instant: false,
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(InstantSwapScope.of(context), isFalse);
      expect(reduceMotionOf(context), isFalse);
      expect(animatesSwap(context, wasEnabled: true), isTrue);
      expect(animatesSwap(context, wasEnabled: false), isFalse);
    });
  });

  group('currency pick', () {
    testWidgets('each side calls the callback of where it is shown', (
      tester,
    ) async {
      final picks = <String>[];
      void left() => picks.add('left');
      void right() => picks.add('right');

      await pumpPair(tester, onSwap: () {}, onLeft: left, onRight: right);
      await tester.tap(usdButton);
      await tester.tap(krwButton);
      expect(picks, ['left', 'right']);

      picks.clear();
      await pumpPair(
        tester,
        swapped: true,
        onSwap: () {},
        onLeft: left,
        onRight: right,
      );
      await tester.pumpAndSettle();
      await tester.tap(usdButton);
      await tester.tap(krwButton);
      expect(picks, ['right', 'left']);
    });

    testWidgets('without a callback a side has no button and no arrow', (
      tester,
    ) async {
      await pumpPair(tester, onSwap: () {}, onRight: () {});
      expect(usdButton, findsNothing);
      expect(krwButton, findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
    });

    testWidgets('a touch on the moving button swaps instead of picking', (
      tester,
    ) async {
      var swaps = 0;
      var picks = 0;
      void onSwap() => swaps++;
      void onPick() => picks++;
      await pumpPair(tester, onSwap: onSwap, onLeft: onPick, onRight: onPick);
      await pumpPair(
        tester,
        swapped: true,
        onSwap: onSwap,
        onLeft: onPick,
        onRight: onPick,
      );
      await tester.pump(const Duration(milliseconds: 150));

      await tester.tapAt(tester.getCenter(swapButton));
      await tester.pumpAndSettle();
      expect(swaps, 1);
      expect(picks, 0);
    });
  });

  group('keyboard focus', () {
    testWidgets('Tab follows what is shown, left to right', (tester) async {
      await pumpPair(tester, onSwap: () {}, onLeft: () {}, onRight: () {});
      expect(await tabThrough(tester, 3), [usdPick, swapKeyValue, krwPick]);

      await pumpPair(
        tester,
        swapped: true,
        onSwap: () {},
        onLeft: () {},
        onRight: () {},
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(await tabThrough(tester, 3), [krwPick, swapKeyValue, usdPick]);
    });

    testWidgets('Shift+Tab goes back', (tester) async {
      await pumpPair(tester, onSwap: () {}, onLeft: () {}, onRight: () {});
      await tabThrough(tester, 3);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(focusedButton(), swapKeyValue);
    });

    testWidgets('Tab skips the swap button while it is off', (tester) async {
      await pumpPair(tester, onLeft: () {}, onRight: () {});
      expect(await tabThrough(tester, 2), [usdPick, krwPick]);
    });

    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      testWidgets('${key.keyLabel} on swap asks once and keeps focus', (
        tester,
      ) async {
        var swaps = 0;
        void onSwap() => swaps++;
        await pumpPair(tester, onSwap: onSwap, onLeft: () {}, onRight: () {});
        await tabThrough(tester, 2);
        final node = FocusManager.instance.primaryFocus;
        expect(focusedButton(), swapKeyValue);

        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(swaps, 1);

        // 양옆 통화가 자리를 맞바꿔도 버튼이 새로 만들어지지 않는다.
        await pumpPair(
          tester,
          swapped: true,
          onSwap: onSwap,
          onLeft: () {},
          onRight: () {},
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(FocusManager.instance.primaryFocus, same(node));
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(node));
        expect(focusedButton(), swapKeyValue);
      });

      testWidgets('${key.keyLabel} on a currency calls its side', (
        tester,
      ) async {
        final picks = <String>[];
        await pumpPair(
          tester,
          onSwap: () {},
          onLeft: () => picks.add('left'),
          onRight: () => picks.add('right'),
        );
        await tabThrough(tester, 1);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(picks, ['left']);
        expect(focusedButton(), usdPick);
      });
    }

    testWidgets('focus stays with the currency when it changes sides', (
      tester,
    ) async {
      final picks = <String>[];
      void left() => picks.add('left');
      void right() => picks.add('right');
      await pumpPair(tester, onSwap: () {}, onLeft: left, onRight: right);
      await tabThrough(tester, 1);
      final node = FocusManager.instance.primaryFocus;
      expect(focusedButton(), usdPick);

      await pumpPair(
        tester,
        swapped: true,
        onSwap: () {},
        onLeft: left,
        onRight: right,
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(node));
      expect(focusedButton(), usdPick);

      // 자리를 옮긴 뒤에는 지금 있는 쪽의 동작을 한다.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picks, ['right']);
    });
  });
}
