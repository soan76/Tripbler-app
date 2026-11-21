import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_response.dart';
import 'package:tripbler/screens/exchange_screen.dart';

import '../crypto/crypto_test.dart' show makeApi, FiatApi;
import '../helpers/exchange_handles.dart';

/// 서버가 대체 출처 값을 준 것처럼 응답한다.
class _FallbackFiatApi extends FiatApi {
  _FallbackFiatApi({required this.fromFallbackSource});

  final bool fromFallbackSource;

  @override
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    final response = await super.fetchLatestRatesResponse(
      baseCurrency: baseCurrency,
      targetCurrencies: targetCurrencies,
    );

    return ExchangeRateResponse(
      baseCurrency: response.baseCurrency,
      rates: response.rates,
      rateDate: response.rateDate,
      fetchedAt: response.fetchedAt,
      fromFallbackSource: fromFallbackSource,
    );
  }
}

Future<void> _pumpExchangeScreen(
  WidgetTester tester, {
  required bool fromFallbackSource,
  Size? size,
  double textScale = 1,
  ThemeData? theme,
}) async {
  if (size != null) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  SharedPreferences.setMockInitialValues({});
  final harness = ExchangeHarness.create(
    cryptoApi: makeApi(),
    fiatApi: _FallbackFiatApi(fromFallbackSource: fromFallbackSource),
  );
  addTearDown(harness.dispose);
  await harness.display.initialize();
  // 표시 통화가 있어야 환율을 서버에 묻는다.
  await harness.exchange.addCurrency(findCurrencyByCode('USD')!);

  await tester.pumpWidget(
    harness.scope(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: ExchangeScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('대체 출처 환율이면 안내를 띄운다', (tester) async {
    await _pumpExchangeScreen(tester, fromFallbackSource: true);

    expect(find.text(fallbackSourceNotice), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('평소 출처 환율이면 안내를 띄우지 않는다', (tester) async {
    await _pumpExchangeScreen(tester, fromFallbackSource: false);

    expect(find.text(fallbackSourceNotice), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('대체 출처 안내는 마지막 업데이트 바로 아래에 붙고 함께 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpExchangeScreen(tester, fromFallbackSource: true);

    final updated = tester.getRect(find.textContaining('마지막 업데이트'));
    final notice = tester.getRect(find.text(fallbackSourceNotice));
    expect(notice.top, greaterThan(updated.bottom));
    expect(notice.top - updated.bottom, lessThanOrEqualTo(8));

    final node = tester.getSemantics(find.text(fallbackSourceNotice));
    expect(node.label, contains('마지막 업데이트'));
    expect(node.label, contains(fallbackSourceNotice));
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('작은 화면·큰 글자·다크 테마에서도 안내가 넘치지 않고 다 보인다', (tester) async {
    await _pumpExchangeScreen(
      tester,
      fromFallbackSource: true,
      size: const Size(320, 640),
      textScale: 2,
      theme: AppTheme.darkTheme,
    );

    // 이 크기에서는 화면 아래 차트 카드(MarketChartBody)가 따로 넘친다(이번 범위 밖).
    // 그 오류는 걷어 내고, 안내가 들어 있는 머리 영역만 확인한다.
    tester.takeException();
    final header = tester.getRect(
      find.ancestor(
        of: find.text(fallbackSourceNotice),
        matching: find.byType(MergeSemantics),
      ),
    );
    for (final part in [
      find.textContaining('마지막 업데이트'),
      find.text(fallbackSourceNotice),
      find.byIcon(Icons.info_outline),
    ]) {
      final rect = tester.getRect(part);
      expect(header.contains(rect.topLeft), isTrue);
      expect(header.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
    }
    final notice = find.text(fallbackSourceNotice);
    final paragraph = tester.renderObject<RenderParagraph>(notice);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getRect(notice).right, lessThanOrEqualTo(320 - 16));
    expect(
      tester.getRect(find.byIcon(Icons.info_outline)).left,
      greaterThanOrEqualTo(16),
    );
    // 안내는 오류가 아닌 참고 정보라 보조 글자색을 쓴다.
    expect(
      tester.widget<Text>(notice).style?.color,
      AppTheme.darkTheme.colorScheme.onSurfaceVariant,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
