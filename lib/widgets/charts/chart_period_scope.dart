import 'package:flutter/widgets.dart';

import '../../models/exchange_rate_history_model.dart';

/// 차트 카드들이 함께 쓰는 조회 기간.
///
/// 기간 버튼은 각 카드 안 그래프 바로 아래에 그리지만, 기간은 카드끼리 같다.
/// 캐러셀이 이 값을 들고 있고, 카드는 버튼을 그릴 때 여기서 읽는다.
/// 위에 없으면(카드를 따로 쓰는 경우) 카드는 기간 버튼을 그리지 않는다.
class ChartPeriodScope extends InheritedWidget {
  const ChartPeriodScope({
    super.key,
    required this.period,
    required this.onChanged,
    this.focusSelected = false,
    required super.child,
  });

  final ChartPeriod period;

  /// 기간 버튼을 눌렀을 때. [focused]는 누른 버튼에 초점이 있었는지(키보드로 눌렀는지)다.
  final void Function(ChartPeriod period, {required bool focused}) onChanged;

  /// 키보드로 기간을 바꿔 새로 만든 카드가 선택된 기간 버튼에 초점을 줘야 하는지.
  /// 바꾼 직후 한 프레임 동안만 true다.
  final bool focusSelected;

  static ChartPeriodScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChartPeriodScope>();

  @override
  bool updateShouldNotify(ChartPeriodScope oldWidget) =>
      period != oldWidget.period ||
      onChanged != oldWidget.onChanged ||
      focusSelected != oldWidget.focusSelected;
}
