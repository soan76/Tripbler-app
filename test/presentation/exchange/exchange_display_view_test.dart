import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/crypto/services/crypto_api_service.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_response.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/presentation/exchange/exchange_display_view.dart';
import 'package:tripbler/providers/tab_provider.dart';
import 'package:tripbler/screens/exchange_screen.dart';
import 'package:tripbler/services/exchange_rate_api_service.dart';
import 'package:tripbler/services/local_storage_service.dart';

import '../../helpers/exchange_handles.dart';

/// 환율 목록 요청과 KRW 연결 환율 요청을 따로 붙잡을 수 있는 가짜 환율 API.
class HeldFiatApi extends ExchangeRateApiService {
  HeldFiatApi({this.rates = const {'USD': 0.00075, 'JPY': 0.11}});

  final Map<String, double> rates;

  /// true면 환율 목록 요청을 [rateRequests]에 쌓아 두고 응답하지 않는다.
  bool holdRates = false;

  /// true면 KRW 연결 환율 요청을 [krwRequests]에 쌓아 두고 응답하지 않는다.
  bool holdKrw = false;

  /// KRW 연결 환율 요청을 실패시킨다.
  bool failKrw = false;

  final rateRequests = <Completer<ExchangeRateResponse>>[];
  final krwRequests = <Completer<ExchangeRateResponse>>[];

  @override
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    final isKrw = targetCurrencies.length == 1 && targetCurrencies[0] == 'KRW';
    if (isKrw) {
      if (failKrw) throw Exception('offline');
      if (holdKrw) {
        final pending = Completer<ExchangeRateResponse>();
        krwRequests.add(pending);
        return pending.future;
      }
      return krw(baseCurrency, 1400);
    }
    if (holdRates) {
      final pending = Completer<ExchangeRateResponse>();
      rateRequests.add(pending);
      return pending.future;
    }
    return ExchangeRateResponse(
      baseCurrency: baseCurrency,
      rates: {for (final code in targetCurrencies) code: rates[code] ?? 1},
      rateDate: null,
      fetchedAt: DateTime.utc(2026, 10, 2),
    );
  }

  static ExchangeRateResponse krw(String base, double rate) =>
      ExchangeRateResponse(
        baseCurrency: base,
        rates: {'KRW': rate},
        rateDate: null,
        fetchedAt: DateTime.utc(2026, 10, 2),
      );
}

/// 코인 시세를 테스트가 바꿀 수 있는 가짜 암호화폐 API.
class PriceApi {
  double btcPrice = 100;

  late final CryptoApiService service = CryptoApiService(
    client: MockClient((request) async {
      if (request.url.path.endsWith('/coins')) {
        return http.Response(
          jsonEncode([
            {'symbol': 'BTC', 'name': 'Bitcoin'},
          ]),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'symbol': 'BTC',
          'currency': 'KRW',
          'price': btcPrice,
          'fetchedAt': '2026-10-02T01:00:00Z',
        }),
        200,
      );
    }),
  );
}

final usd = DisplayCurrency.fromFiat(findCurrencyByCode('USD')!);
final btc = DisplayCurrency.fromCrypto(
  const CryptoCoin(symbol: 'BTC', name: 'Bitcoin'),
);

/// 저장된 기준 통화·표시 통화·코인 선택을 넣는다.
Future<void> seed({
  String base = 'KRW',
  List<String> visible = const ['USD', 'JPY'],
  List<String> coins = const ['BTC'],
}) async {
  final storage = LocalStorageService();
  await storage.saveBaseCurrency(base);
  await storage.saveVisibleCurrencies(visible);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('crypto.selected.v1', coins);
  await prefs.setString(
    'crypto.catalog.v1',
    jsonEncode([
      {'symbol': 'BTC', 'name': 'Bitcoin'},
    ]),
  );
}

/// 지금 쌓인 비동기 작업이 끝날 때까지 기다린다.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

DisplayRowView rowOf(ExchangeHarness harness, DisplayCurrency currency) =>
    harness.container.read(exchangeDisplayViewProvider).rowOf(currency);

List<String> rowIds(ExchangeHarness harness) => [
  for (final row in harness.container.read(exchangeDisplayViewProvider).rows)
    row.currency.id,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ExchangeHarness create(HeldFiatApi fiatApi, PriceApi prices) {
    addTearDown(prices.service.dispose);
    return ExchangeHarness.create(
      fiatApi: fiatApi,
      cryptoApi: prices.service,
      storage: LocalStorageService(),
    );
  }

  test('행 목록이 그대로여도 입력 금액이 바뀌면 다른 행 금액이 갱신된다', () async {
    await seed();
    final harness = create(HeldFiatApi(), PriceApi());
    await harness.display.initialize();
    await settle();
    final jpy = DisplayCurrency.fromFiat(findCurrencyByCode('JPY')!);

    await harness.exchange.changeAmountFromCurrency(
      currencyCode: 'USD',
      amount: 1,
    );
    final idsBefore = rowIds(harness);
    final jpyBefore = rowOf(harness, jpy).amount!;
    var updates = 0;
    harness.container.listen(exchangeDisplayViewProvider, (_, _) => updates++);

    await harness.exchange.changeAmountFromCurrency(
      currencyCode: 'USD',
      amount: 2,
    );

    expect(rowIds(harness), idsBefore);
    expect(rowOf(harness, jpy).amount, closeTo(jpyBefore * 2, 1e-9));
    expect(updates, greaterThan(0));
  });

  test('코인 시세만 바뀌면 해당 코인 행 금액이 갱신된다', () async {
    await seed();
    final prices = PriceApi();
    final harness = create(HeldFiatApi(), prices);
    await harness.display.initialize();
    await harness.crypto.refresh();
    await settle();
    final usdBefore = rowOf(harness, usd).amount;
    final btcBefore = rowOf(harness, btc).amount!;
    expect(btcBefore, closeTo(10000 / 100, 1e-9));

    prices.btcPrice = 200;
    await harness.crypto.fetchPrice('BTC');

    // 수량 = 입력 금액(KRW) / 시세이므로 시세가 2배가 되면 수량은 절반이 된다.
    expect(rowOf(harness, btc).amount, closeTo(btcBefore / 2, 1e-9));
    expect(rowOf(harness, usd).amount, usdBefore);
  });

  test('입력 행을 국가 통화에서 코인으로 바꾸면 선택 표시가 옮겨 간다', () async {
    await seed();
    final harness = create(HeldFiatApi(), PriceApi());
    await harness.display.initialize();
    await settle();
    harness.display.selectInput(usd);
    expect(rowOf(harness, usd).isActive, isTrue);
    expect(rowOf(harness, btc).isActive, isFalse);

    harness.display.selectInput(btc);
    expect(rowOf(harness, btc).isActive, isTrue);
    expect(rowOf(harness, usd).isActive, isFalse);

    harness.display.selectInput(usd);
    expect(rowOf(harness, usd).isActive, isTrue);
    expect(rowOf(harness, btc).isActive, isFalse);
  });

  test('기준 통화를 바꾸면 activeCrypto와 KRW 환율이 비워진다', () async {
    await seed();
    final fiatApi = HeldFiatApi();
    final harness = create(fiatApi, PriceApi());
    await harness.display.initialize();
    await settle();
    harness.display.selectInput(btc);
    expect(harness.display.activeCrypto, 'BTC');
    expect(harness.display.krwRate, 1);

    fiatApi.holdKrw = true;
    final change = harness.exchange.changeBaseCurrency(
      findCurrencyByCode('USD')!,
    );

    expect(harness.display.activeCrypto, isNull);
    expect(harness.display.krwRate, isNull);
    await change;
    await settle();
    // 재조회 응답 전이므로 여전히 비어 있다.
    expect(fiatApi.krwRequests, isNotEmpty);
    expect(harness.display.krwRate, isNull);
  });

  test('환산을 다시 시도하면 conversionError가 지워진다', () async {
    await seed(base: 'USD', visible: const ['JPY']);
    final fiatApi = HeldFiatApi()..failKrw = true;
    final harness = create(fiatApi, PriceApi());
    await harness.display.initialize();
    await settle();
    expect(harness.display.conversionError, isNotNull);

    fiatApi
      ..failKrw = false
      ..holdKrw = true;
    final retry = harness.display.refreshConversion();

    expect(harness.display.conversionError, isNull);
    await settle();
    fiatApi.krwRequests.last.complete(HeldFiatApi.krw('USD', 1400));
    await retry;
    expect(harness.display.conversionError, isNull);
    expect(harness.display.krwRate, 1400);
  });

  test('기준 통화 변경 직후 이전 요청의 KRW 환율은 반영하지 않는다', () async {
    await seed(base: 'USD', visible: const ['JPY']);
    final fiatApi = HeldFiatApi()..holdKrw = true;
    final harness = create(fiatApi, PriceApi());
    await harness.display.initialize();
    await settle();
    expect(fiatApi.krwRequests, isNotEmpty);
    final earlier = [...fiatApi.krwRequests];

    final change = harness.exchange.changeBaseCurrency(
      findCurrencyByCode('EUR')!,
    );
    await settle();
    expect(fiatApi.krwRequests.length, earlier.length + 1);
    final latest = fiatApi.krwRequests.last;

    latest.complete(HeldFiatApi.krw('EUR', 1300));
    await settle();
    for (final request in earlier) {
      request.complete(HeldFiatApi.krw('USD', 9999));
    }
    await settle();
    await change;

    expect(harness.display.krwRate, 1300);
  });

  test('폐기 뒤 응답은 무시된다', () async {
    await seed(base: 'USD', visible: const ['JPY']);
    final fiatApi = HeldFiatApi()
      ..holdRates = true
      ..holdKrw = true;
    final harness = create(fiatApi, PriceApi());
    await harness.display.initialize();
    await settle();
    expect(fiatApi.rateRequests, isNotEmpty);
    expect(fiatApi.krwRequests, isNotEmpty);

    harness.dispose();
    for (final request in fiatApi.rateRequests) {
      request.complete(
        ExchangeRateResponse(
          baseCurrency: 'USD',
          rates: const {'JPY': 150},
          rateDate: null,
          fetchedAt: DateTime.utc(2026, 10, 2),
        ),
      );
    }
    for (final request in fiatApi.krwRequests) {
      request.complete(HeldFiatApi.krw('USD', 1400));
    }
    await settle();
  });

  testWidgets('화면을 떠난 동안 끝난 갱신도 상태에 남는다', (tester) async {
    // 실제 MainScreen은 아직 provider 패키지의 Auth·Map을 함께 요구하므로,
    // 같은 구조(탭 상태로 고르는 IndexedStack)만 따로 만든다.
    await tester.runAsync(() => seed(visible: const ['USD'], coins: const []));
    final fiatApi = HeldFiatApi()..holdRates = true;
    final prices = PriceApi();
    addTearDown(prices.service.dispose);
    final harness = ExchangeHarness.create(
      fiatApi: fiatApi,
      cryptoApi: prices.service,
      storage: LocalStorageService(),
    );
    harness.container.read(tabProvider.notifier).selectTab(0);

    await tester.pumpWidget(
      harness.scope(
        MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final index = ref.watch(tabProvider).selectedIndex;
                return IndexedStack(
                  index: index == 0 ? 0 : 1,
                  children: const [ExchangeScreen(), Text('다른 탭')],
                );
              },
            ),
          ),
        ),
      ),
    );
    // 갱신 중에는 진행 표시줄이 계속 움직이므로 정해진 시간만큼만 그린다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(fiatApi.rateRequests, hasLength(1));
    expect(harness.exchange.isLoading, isTrue);

    // 다른 탭으로 이동한 뒤 응답이 도착한다.
    harness.container.read(tabProvider.notifier).selectTab(1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('다른 탭'), findsOneWidget);
    final fetchedAt = DateTime.utc(2026, 10, 2, 3, 4);
    fiatApi.rateRequests.single.complete(
      ExchangeRateResponse(
        baseCurrency: 'KRW',
        rates: const {'USD': 0.0008},
        rateDate: null,
        fetchedAt: fetchedAt,
      ),
    );
    await tester.pumpAndSettle();

    // 환율 탭으로 돌아오면 새 값과 응답의 fetchedAt이 보인다.
    harness.container.read(tabProvider.notifier).selectTab(0);
    await tester.pumpAndSettle();
    expect(harness.exchange.rateFor('USD'), 0.0008);
    expect(harness.exchange.lastUpdated, fetchedAt);
    expect(harness.exchange.isLoading, isFalse);
    final local = fetchedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    expect(
      find.text(
        '마지막 업데이트: ${local.year}.${two(local.month)}.${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}',
      ),
      findsOneWidget,
    );
    final usdField = find.descendant(
      of: find.byKey(const ValueKey('fiat:USD')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(usdField).controller.text, '8');
  });
}
