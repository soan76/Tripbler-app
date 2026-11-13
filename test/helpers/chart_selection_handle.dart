import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, ProviderScope, ProviderSubscription;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/presentation/charts/chart_selection_provider.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';

/// 테스트에서 컨테이너에 있는 차트 선택 상태를 읽고 바꾼다.
class ChartSelectionHandle {
  ChartSelectionHandle(this._containerOf);

  /// 화면이 그려진 [tester]의 [ProviderScope] 컨테이너를 쓴다.
  ChartSelectionHandle.of(WidgetTester tester)
    : this(
        () => ProviderScope.containerOf(
          tester.element(find.byType(Scaffold).first),
        ),
      );

  final ProviderContainer Function() _containerOf;

  ProviderContainer get container => _containerOf();

  ChartSelectionNotifier get notifier =>
      container.read(chartSelectionProvider.notifier);

  ChartSelectionState get state => container.read(chartSelectionProvider);

  List<ChartPair> get pairs => state.pairs;

  ChartPair? add() => notifier.add();

  void remove(int index) => notifier.remove(index);

  bool get loaded => state.loaded;
  bool get canAdd => state.canAdd;
  bool get canRemove => state.canRemove;

  Future<void> initialize() => notifier.initialize();

  ChartPairChange replace(int index, ChartPair next) =>
      notifier.replace(index, next);

  ChartPairChange replaceSide(
    int index, {
    required ChartPair expected,
    required bool base,
    required bool swapped,
    required DisplayCurrency currency,
  }) => notifier.replaceSide(
    index,
    expected: expected,
    base: base,
    swapped: swapped,
    currency: currency,
  );

  bool? swappedAfterReplace(String fromId, String toId) =>
      notifier.swappedAfterReplace(fromId, toId);

  ({String id, bool swapped})? swappedAfterExchange(
    String firstId,
    String secondId,
  ) => notifier.swappedAfterExchange(firstId, secondId);
}

/// [ChartSelectionHandle]에 상태가 바뀔 때 알려 주는 [Listenable]을 더한 것.
class ChartSelectionListenable extends ChartSelectionHandle
    with ChangeNotifier {
  ChartSelectionListenable(ProviderContainer container)
    : super(() => container) {
    _subscription = container.listen(
      chartSelectionProvider,
      (_, _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<ChartSelectionState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
