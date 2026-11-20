import 'package:flutter/widgets.dart';

/// 카드가 새로 만들어져도(통화·기간 변경) 입력한 금액을 이어 쓰게 한다.
/// 입력칸을 만들 때와 글자가 바뀔 때만 읽으므로 의존을 만들지 않는다.
class ChartAmountScope extends InheritedWidget {
  const ChartAmountScope({
    super.key,
    required this.text,
    required this.onChanged,
    required super.child,
  });

  /// 보관 중인 입력 글자.
  final String text;
  final ValueChanged<String> onChanged;

  static ChartAmountScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChartAmountScope>();

  @override
  bool updateShouldNotify(ChartAmountScope oldWidget) => false;
}
