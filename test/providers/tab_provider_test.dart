import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/tab_provider.dart';

void main() {
  test('처음에는 환율 탭이 선택된다', () {
    final c = ProviderContainer.test();

    expect(c.read(tabProvider).selectedIndex, TabState.firstTabIndex);
    expect(c.read(tabProvider).isSelected(0), isTrue);
    expect(c.read(tabProvider).isHomeSelected, isFalse);
  });

  test('같은 탭을 다시 누르면 선택과 상태를 유지한다', () {
    final c = ProviderContainer.test();
    final notifier = c.read(tabProvider.notifier);

    notifier.selectTab(1);
    expect(c.read(tabProvider).selectedIndex, 1);
    expect(c.read(tabProvider).isSelected(1), isTrue);

    var count = 0;
    c.listen(tabProvider, (_, _) => count++);
    notifier.selectTab(1);
    expect(c.read(tabProvider).selectedIndex, 1);
    expect(count, 0);
  });

  test('범위 밖 인덱스는 무시한다', () {
    final c = ProviderContainer.test();
    var count = 0;
    c.listen(tabProvider, (_, _) => count++);

    c.read(tabProvider.notifier).selectTab(TabState.tabCount);
    c.read(tabProvider.notifier).selectTab(-1);
    c.read(tabProvider.notifier).selectTab(-2);

    expect(c.read(tabProvider).selectedIndex, TabState.firstTabIndex);
    expect(count, 0);
  });

  test('일정(3)·면세(4)는 유효한 탭이고 5부터는 범위 밖이다', () {
    final c = ProviderContainer.test();
    final notifier = c.read(tabProvider.notifier);

    expect(TabState.tabCount, 5);
    notifier.selectTab(3);
    expect(c.read(tabProvider).selectedIndex, 3);
    expect(c.read(tabProvider).isSelected(3), isTrue);
    notifier.selectTab(4);
    expect(c.read(tabProvider).selectedIndex, 4);
    notifier.selectTab(5);
    expect(c.read(tabProvider).selectedIndex, 4);
    expect(c.read(tabProvider).isSelected(5), isFalse);
  });

  test('탭에서 selectHome은 홈으로 가고, 홈에서 다시 부르면 알리지 않는다', () {
    final c = ProviderContainer.test();
    var count = 0;
    c.listen(tabProvider, (_, _) => count++);
    final notifier = c.read(tabProvider.notifier);

    notifier.selectHome();
    expect(c.read(tabProvider).isHomeSelected, isTrue);
    expect(count, 1);

    notifier.selectHome();
    expect(count, 1);
  });
}
