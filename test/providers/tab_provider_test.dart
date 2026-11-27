import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/tab_provider.dart';

void main() {
  test('처음에는 홈이 선택된다', () {
    final c = ProviderContainer.test();

    expect(c.read(tabProvider).selectedIndex, TabState.homeIndex);
    expect(c.read(tabProvider).isHomeSelected, isTrue);
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

    expect(c.read(tabProvider).selectedIndex, TabState.homeIndex);
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

  test('홈에서 selectHome은 알리지 않고, 탭에서는 홈으로 돌아간다', () {
    final c = ProviderContainer.test();
    var count = 0;
    c.listen(tabProvider, (_, _) => count++);
    final notifier = c.read(tabProvider.notifier);

    notifier.selectHome();
    expect(count, 0);

    notifier.selectTab(2);
    notifier.selectHome();
    expect(c.read(tabProvider).isHomeSelected, isTrue);
    expect(count, 2);
  });
}
