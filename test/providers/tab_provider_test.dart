import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/tab_provider.dart';

void main() {
  test('처음에는 홈이 선택된다', () {
    final c = ProviderContainer.test();

    expect(c.read(tabProvider).selectedIndex, TabState.homeIndex);
    expect(c.read(tabProvider).isHomeSelected, isTrue);
  });

  test('탭을 고르면 선택되고 같은 탭을 다시 누르면 홈으로 돌아간다', () {
    final c = ProviderContainer.test();
    final notifier = c.read(tabProvider.notifier);

    notifier.selectTab(1);
    expect(c.read(tabProvider).selectedIndex, 1);
    expect(c.read(tabProvider).isSelected(1), isTrue);

    notifier.selectTab(1);
    expect(c.read(tabProvider).selectedIndex, TabState.homeIndex);
  });

  test('범위 밖 인덱스는 무시한다', () {
    final c = ProviderContainer.test();
    var count = 0;
    c.listen(tabProvider, (_, _) => count++);

    c.read(tabProvider.notifier).selectTab(3);
    c.read(tabProvider.notifier).selectTab(-1);

    expect(c.read(tabProvider).selectedIndex, TabState.homeIndex);
    expect(count, 0);
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
