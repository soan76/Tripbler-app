import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/widgets/charts/market_chart_body.dart';
import 'package:tripbler/widgets/charts/market_chart_card.dart';
import 'package:tripbler/widgets/exchange/exchange_rate_line_chart.dart';

import '../../helpers/memory_chart_snapshots.dart';

const emptyText = '표시할 차트 데이터가 없습니다.';

class PendingSource implements ChartDataSource {
  final List<Completer<ChartData>> requests = [];

  @override
  Future<ChartData> load(ChartPeriod period) {
    final request = Completer<ChartData>();
    requests.add(request);
    return request.future;
  }

  @override
  void dispose() {}
}

/// 뒤집으면 값이 하나도 남지 않는 기록.
ChartData uninvertibleData() => ChartData(
  history: [
    for (var i = 0; i < 3; i++)
      ChartSample(
        date: DateTime(2026, 1, 1 + i),
        rate: 0,
        baseCurrencyCode: 'USD',
        targetCurrencyCode: 'KRW',
      ),
  ],
  currentRate: 0,
  fetchedAt: DateTime(2026, 1, 3),
);

Widget card(PendingSource source) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: 430,
      child: MarketChartCard(
        baseCurrency: DisplayCurrency.fromFiat(findCurrencyByCode('USD')!),
        targetCurrency: DisplayCurrency.fromFiat(findCurrencyByCode('KRW')!),
        swapped: true,
        title: '차트',
        errorText: '실패',
        requestKey: 'fiat:USD/KRW',
        createDataSource: () => source,
        period: ChartPeriod.oneMonth,
        shouldLoad: true,
        snapshotStore: MemorySnapshots(),
      ),
    ),
  ),
);

// 헤더의 새로고침 버튼도 조회 중에 같은 표시를 쓰므로 본문 안에서만 찾는다.
final bodySpinner = find.descendant(
  of: find.byType(MarketChartBody),
  matching: find.byType(CircularProgressIndicator),
);

void main() {
  testWidgets(
    'a flipped card with only uninvertible history says it has nothing to show, '
    'even while refreshing or after a failed refresh',
    (tester) async {
      final source = PendingSource();
      await tester.pumpWidget(card(source));
      await tester.pump();

      // 처음 조회 중에는 아직 기록이 없어 로딩을 보여 준다.
      expect(bodySpinner, findsOneWidget);

      source.requests.single.complete(uninvertibleData());
      await tester.pumpAndSettle();
      expect(find.text(emptyText), findsOneWidget);
      expect(find.byType(ExchangeRateLineChart), findsNothing);

      // 새로고침 중에도 원본 기록은 있으므로 로딩으로 되돌아가지 않는다.
      await tester.tap(find.byTooltip('새로고침'));
      await tester.pump();
      expect(source.requests, hasLength(2));
      expect(bodySpinner, findsNothing);
      expect(find.text(emptyText), findsOneWidget);

      // 갱신에 실패해도 원본 기록이 있으므로 다시 시도 화면을 보여 주지 않는다.
      source.requests.last.completeError(Exception('실패'));
      await tester.pumpAndSettle();
      expect(find.text('다시 시도'), findsNothing);
      expect(find.text(emptyText), findsOneWidget);
    },
  );
}
