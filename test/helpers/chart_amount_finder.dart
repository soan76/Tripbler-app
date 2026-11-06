import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 왼쪽 통화가 [code]인 차트 금액 입력칸.
/// 입력칸에 보이는 글자가 없어 화면 낭독기 라벨로 찾는다.
Finder amountField(String code) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == '$code 금액',
  ),
  matching: find.byType(TextField),
);
