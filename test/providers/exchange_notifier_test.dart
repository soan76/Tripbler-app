import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_response.dart';
import 'package:tripbler/providers/exchange/exchange_provider.dart';
import 'package:tripbler/services/exchange_rate_api_service.dart';
import 'package:tripbler/services/local_storage_service.dart';

/// 요청마다 Completer를 만들어 테스트가 응답 시점과 내용을 정한다.
class _Api extends ExchangeRateApiService {
  final List<({String base, List<String> targets})> requests = [];
  final List<Completer<ExchangeRateResponse>> pending = [];

  @override
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) {
    requests.add((base: baseCurrency, targets: targetCurrencies));
    final completer = Completer<ExchangeRateResponse>();
    pending.add(completer);
    return completer.future;
  }

  void respond(
    int index,
    Map<String, double> rates, {
    required DateTime fetchedAt,
    bool stale = false,
    bool fromFallbackSource = false,
  }) {
    pending[index].complete(
      ExchangeRateResponse(
        baseCurrency: requests[index].base,
        rates: rates,
        rateDate: null,
        fetchedAt: fetchedAt,
        stale: stale,
        fromFallbackSource: fromFallbackSource,
      ),
    );
  }

  void fail(int index, Object error) => pending[index].completeError(error);
}

/// 실제 저장 방식(SharedPreferences 대역)에 실패만 끼워 넣는다.
class _Storage extends LocalStorageService {
  bool failSaveCachedRates = false;
  bool failLoadCachedRates = false;
  bool failSaveVisibleCurrencies = false;

  @override
  Future<void> saveVisibleCurrencies(List<String> codes) {
    if (failSaveVisibleCurrencies) {
      return Future.error(Exception('disk full'));
    }

    return super.saveVisibleCurrencies(codes);
  }

  @override
  Future<void> saveCachedRates({
    required String baseCurrency,
    required Map<String, double> rates,
  }) {
    if (failSaveCachedRates) {
      return Future.error(Exception('disk full'));
    }

    return super.saveCachedRates(baseCurrency: baseCurrency, rates: rates);
  }

  @override
  Future<Map<String, double>?> loadCachedRates({required String baseCurrency}) {
    if (failLoadCachedRates) {
      return Future.error(Exception('read failed'));
    }

    return super.loadCachedRates(baseCurrency: baseCurrency);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Api api;
  late _Storage storage;
  late ProviderContainer container;

  ExchangeState read() => container.read(exchangeProvider);
  ExchangeNotifier notifier() => container.read(exchangeProvider.notifier);

  /// 대기 중인 비동기 작업(저장소 읽기·쓰기, 상태 반영)이 끝날 때까지 돌린다.
  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> saveCache(String base, Map<String, double> rates, DateTime at) {
    return Future.wait([
      storage.saveCachedRates(baseCurrency: base, rates: rates),
      storage.saveLastUpdated(baseCurrency: base, dateTime: at),
    ]);
  }

  /// 저장된 표시 통화로 초기화한다. 첫 조회 요청이 시작된 상태로 끝난다.
  Future<void> initializeWith(List<String> visible) async {
    await storage.saveVisibleCurrencies(visible);
    await notifier().initialize();
    await settle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = _Api();
    storage = _Storage();
    container = ProviderContainer.test(
      overrides: [
        exchangeRateApiServiceProvider.overrideWithValue(api),
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  });

  tearDown(() => api.dispose());

  group('조회 성공', () {
    test('서버 시각을 마지막 갱신 시각으로 쓰고 기기에 저장한다', () async {
      final fetchedAt = DateTime.now().subtract(const Duration(minutes: 5));
      await initializeWith(['USD', 'JPY']);

      expect(api.requests.single.base, 'KRW');
      expect(api.requests.single.targets, ['USD', 'JPY']);
      expect(read().isLoading, isTrue);

      api.respond(0, {'USD': 0.0007, 'JPY': 0.11}, fetchedAt: fetchedAt);
      await settle();

      expect(read().rates, {'USD': 0.0007, 'JPY': 0.11});
      expect(read().lastUpdated, fetchedAt);
      expect(read().errorMessage, isNull);
      expect(read().isLoading, isFalse);
      expect(await storage.loadCachedRates(baseCurrency: 'KRW'), {
        'USD': 0.0007,
        'JPY': 0.11,
      });
      expect(await storage.loadLastUpdated(baseCurrency: 'KRW'), fetchedAt);
    });

    test('서버가 지난 값을 주면(stale) 응답 지연 안내를 띄운다', () async {
      await initializeWith(['USD']);

      api.respond(0, {'USD': 0.0007}, fetchedAt: DateTime.now(), stale: true);
      await settle();

      expect(read().rates, {'USD': 0.0007});
      expect(read().errorMessage, '응답 지연으로 마지막 성공 환율을 표시합니다.');
    });

    test('기기 저장이 실패해도 받은 환율은 보여 주고 저장 실패를 알린다', () async {
      await initializeWith(['USD']);
      storage.failSaveCachedRates = true;

      api.respond(0, {'USD': 0.0007}, fetchedAt: DateTime.now());
      await settle();

      expect(read().rates, {'USD': 0.0007});
      expect(read().errorMessage, '최신 환율은 표시했지만 기기에 저장하지 못했습니다.');
      expect(read().isLoading, isFalse);
    });
  });

  group('조회 실패 시 대체', () {
    test('화면에 3일 안의 값이 있으면 그대로 두고 마지막 성공 데이터라고 알린다', () async {
      final fetchedAt = DateTime.now().subtract(const Duration(hours: 2));
      await initializeWith(['USD']);
      api.respond(0, {'USD': 0.0007}, fetchedAt: fetchedAt);
      await settle();

      final refresh = notifier().fetchRates();
      await settle();
      api.fail(1, const ApiException(message: '서버 오류'));
      await refresh;

      expect(read().rates, {'USD': 0.0007});
      expect(read().lastUpdated, fetchedAt);
      expect(read().errorMessage, '서버 오류 마지막 성공 데이터를 표시합니다.');
      expect(read().isLoading, isFalse);
    });

    test('화면 값이 없고 기기에 3일 안의 캐시가 있으면 캐시를 보여 준다', () async {
      final cachedAt = DateTime.now().subtract(const Duration(days: 1));
      await initializeWith(['USD']);
      expect(read().rates, isEmpty);

      // 요청 중에 다른 경로로 캐시가 저장된 상황.
      await saveCache('KRW', {'USD': 0.0008}, cachedAt);
      api.fail(0, Exception('연결 실패'));
      await settle();

      expect(read().rates, {'USD': 0.0008});
      expect(read().lastUpdated, cachedAt);
      expect(read().errorMessage, '연결 실패 마지막 저장 데이터를 표시합니다.');
    });

    test('쓸 수 있는 값이 없으면 환율과 시각을 비우고 오류만 알린다', () async {
      await initializeWith(['USD']);

      api.fail(0, Exception('연결 실패'));
      await settle();

      expect(read().rates, isEmpty);
      expect(read().lastUpdated, isNull);
      expect(read().errorMessage, '연결 실패');
      expect(read().isLoading, isFalse);
    });

    test('3일이 지난 기기 캐시는 대체 값으로 쓰지 않는다', () async {
      await initializeWith(['USD']);

      await saveCache('KRW', {
        'USD': 0.0008,
      }, DateTime.now().subtract(const Duration(days: 4)));
      api.fail(0, Exception('연결 실패'));
      await settle();

      expect(read().rates, isEmpty);
      expect(read().errorMessage, '연결 실패');
    });
  });

  group('초기화와 저장값', () {
    test('3일 안의 저장 환율과 입력 금액을 응답 전에 보여 준다', () async {
      final cachedAt = DateTime.now().subtract(const Duration(hours: 1));
      await saveCache('KRW', {'USD': 0.0008}, cachedAt);
      await storage.saveInputAmount(5000);

      await initializeWith(['USD']);

      expect(read().rates, {'USD': 0.0008});
      expect(read().lastUpdated, cachedAt);
      expect(read().inputAmount, 5000);
      expect(read().visibleCurrencies.map((c) => c.code), ['USD']);
      expect(read().isLoading, isTrue);
    });

    test('3일이 지난 저장 환율은 처음부터 보여 주지 않는다', () async {
      await saveCache('KRW', {
        'USD': 0.0008,
      }, DateTime.now().subtract(const Duration(days: 4)));

      await initializeWith(['USD']);

      expect(read().rates, isEmpty);
      expect(read().lastUpdated, isNull);
    });

    test('저장된 기준 통화를 쓰고, 표시 통화에서 기준 통화를 뺀다', () async {
      await storage.saveBaseCurrency('USD');

      await initializeWith(['USD', 'JPY']);

      expect(read().baseCurrency.code, 'USD');
      expect(read().visibleCurrencies.map((c) => c.code), ['JPY']);
      expect(api.requests.single.base, 'USD');
    });

    test('표시할 통화가 없으면 서버에 묻지 않는다', () async {
      await initializeWith([]);

      expect(api.requests, isEmpty);
      expect(read().isLoading, isFalse);
    });

    test('초기화를 여러 번 불러도 한 번만 조회한다', () async {
      await storage.saveVisibleCurrencies(['USD']);

      await Future.wait([notifier().initialize(), notifier().initialize()]);
      await notifier().initialize();
      await settle();

      expect(api.requests, hasLength(1));
    });

    test('조회 시작 때 기기 캐시를 못 읽어도 서버 조회는 한다', () async {
      await initializeWith(['USD']);
      api.fail(0, Exception('연결 실패'));
      await settle();

      storage.failLoadCachedRates = true;
      final refresh = notifier().fetchRates();
      await settle();

      expect(api.requests, hasLength(2));

      api.respond(1, {'USD': 0.0007}, fetchedAt: DateTime.now());
      await refresh;

      expect(read().rates, {'USD': 0.0007});
      expect(read().errorMessage, isNull);
    });
  });

  group('늦은 응답', () {
    test('기준 통화를 바꾸면 이전 기준 통화의 응답은 반영하지 않는다', () async {
      await initializeWith(['USD']);

      final change = notifier().changeBaseCurrency(findCurrencyByCode('JPY')!);
      await settle();

      expect(read().baseCurrency.code, 'JPY');
      expect(read().rates, isEmpty);
      expect(read().lastUpdated, isNull);
      expect(api.requests.last.base, 'JPY');
      expect(api.requests.last.targets, ['KRW', 'USD']);

      api.respond(0, {'USD': 0.0007}, fetchedAt: DateTime.now());
      await settle();

      expect(read().rates, isEmpty);
      expect(read().isLoading, isTrue);

      api.respond(1, {'USD': 0.0067, 'KRW': 9.1}, fetchedAt: DateTime.now());
      await change;

      expect(read().rates, {'USD': 0.0067, 'KRW': 9.1});
      expect(read().isLoading, isFalse);
    });

    test('통화를 추가하면 진행 중이던 요청의 결과는 버린다', () async {
      await initializeWith(['USD']);

      final add = notifier().addCurrency(findCurrencyByCode('JPY')!);
      await settle();

      expect(api.requests.last.targets, ['USD', 'JPY']);

      api.fail(0, Exception('연결 실패'));
      await settle();

      expect(read().errorMessage, isNull);
      expect(read().isLoading, isTrue);

      api.respond(1, {'USD': 0.0007, 'JPY': 0.11}, fetchedAt: DateTime.now());
      await add;

      expect(read().rates, {'USD': 0.0007, 'JPY': 0.11});
    });

    test('폐기된 뒤 도착한 응답은 상태를 바꾸지 않는다', () async {
      await initializeWith(['USD']);

      container.dispose();
      api.respond(0, {'USD': 0.0007}, fetchedAt: DateTime.now());
      await settle();
    });
  });

  group('통화 목록 편집', () {
    CurrencyModel currency(String code) => findCurrencyByCode(code)!;
    List<String> visibleCodes() =>
        read().visibleCurrencies.map((c) => c.code).toList();

    /// 첫 조회에 응답해 편집 전 상태를 안정시킨다.
    Future<void> ready(List<String> visible) async {
      await initializeWith(visible);
      api.respond(0, {
        for (final code in visible) code: 0.001,
      }, fetchedAt: DateTime.now());
      await settle();
    }

    test('같은 기준 통화로 바꾸면 아무것도 하지 않는다', () async {
      await ready(['USD']);
      final before = read();

      await notifier().changeBaseCurrency(currency('KRW'));

      expect(identical(read(), before), isTrue);
      expect(api.requests, hasLength(1));
    });

    test('기준 통화를 바꾸면 이전 기준 통화를 맨 앞에 넣고 저장한다', () async {
      await ready(['USD', 'JPY']);

      unawaited(notifier().changeBaseCurrency(currency('USD')));
      await settle();

      expect(read().baseCurrency.code, 'USD');
      expect(visibleCodes(), ['KRW', 'JPY']);
      expect(read().errorMessage, isNull);
      expect(await storage.loadBaseCurrency(), 'USD');
      expect(await storage.loadVisibleCurrencies(), ['KRW', 'JPY']);
      expect(api.requests.last.base, 'USD');
    });

    test('통화를 교체하면 저장하고 새 구성으로 다시 조회한다', () async {
      await ready(['USD', 'JPY']);

      unawaited(
        notifier().replaceVisibleCurrency(
          index: 0,
          newCurrency: currency('EUR'),
        ),
      );
      await settle();

      expect(visibleCodes(), ['EUR', 'JPY']);
      expect(await storage.loadVisibleCurrencies(), ['EUR', 'JPY']);
      expect(api.requests.last.targets, ['EUR', 'JPY']);
    });

    test('교체할 수 없으면 이유를 알리고 목록을 그대로 둔다', () async {
      await ready(['USD', 'JPY']);
      final cases = <(int, String, String)>[
        (2, 'EUR', '변경할 통화 위치가 올바르지 않습니다.'),
        (-1, 'EUR', '변경할 통화 위치가 올바르지 않습니다.'),
        (0, 'KRW', '기준 통화와 동일한 통화로 변경할 수 없습니다.'),
        (0, 'JPY', '이미 화면에 표시된 통화입니다.'),
      ];

      for (final (index, code, message) in cases) {
        await notifier().replaceVisibleCurrency(
          index: index,
          newCurrency: currency(code),
        );

        expect(read().errorMessage, message, reason: '$index $code');
        expect(visibleCodes(), ['USD', 'JPY']);
      }

      expect(api.requests, hasLength(1));
    });

    test('같은 자리에 같은 통화로 교체하면 아무것도 하지 않는다', () async {
      await ready(['USD', 'JPY']);
      final before = read();

      await notifier().replaceVisibleCurrency(
        index: 0,
        newCurrency: currency('USD'),
      );

      expect(identical(read(), before), isTrue);
      expect(api.requests, hasLength(1));
    });

    test('목록 적용: 순서까지 같으면 아무것도 하지 않는다', () async {
      await ready(['USD', 'JPY']);
      final before = read();

      await notifier().applyVisibleCurrencies([
        currency('USD'),
        currency('JPY'),
      ]);

      expect(identical(read(), before), isTrue);
      expect(api.requests, hasLength(1));
    });

    test('목록 적용: 순서만 바뀌면 저장만 하고 다시 조회하지 않는다', () async {
      await ready(['USD', 'JPY']);

      await notifier().applyVisibleCurrencies([
        currency('JPY'),
        currency('USD'),
      ]);

      expect(visibleCodes(), ['JPY', 'USD']);
      expect(await storage.loadVisibleCurrencies(), ['JPY', 'USD']);
      expect(api.requests, hasLength(1));
      expect(read().rates, {'USD': 0.001, 'JPY': 0.001});
    });

    test('목록 적용: 기준 통화와 중복을 빼고, 구성이 바뀌면 다시 조회한다', () async {
      await ready(['USD']);

      unawaited(
        notifier().applyVisibleCurrencies([
          currency('KRW'),
          currency('EUR'),
          currency('USD'),
          currency('EUR'),
        ]),
      );
      await settle();

      expect(visibleCodes(), ['EUR', 'USD']);
      expect(api.requests.last.targets, ['EUR', 'USD']);
    });

    test('추가할 수 없으면 이유를 알리고 목록을 그대로 둔다', () async {
      await ready(['USD']);

      await notifier().addCurrency(currency('KRW'));
      expect(read().errorMessage, '기준 통화는 표시 통화에 다시 추가할 수 없습니다.');

      await notifier().addCurrency(currency('USD'));
      expect(read().errorMessage, '이미 화면에 표시된 통화입니다.');

      expect(visibleCodes(), ['USD']);
      expect(api.requests, hasLength(1));
    });

    test('통화를 삭제하면 저장하고 남은 통화로 다시 조회한다', () async {
      await ready(['USD', 'JPY']);

      unawaited(notifier().removeCurrency(currency('USD')));
      await settle();

      expect(visibleCodes(), ['JPY']);
      expect(await storage.loadVisibleCurrencies(), ['JPY']);
      expect(api.requests.last.targets, ['JPY']);
    });

    test('기준 통화는 삭제할 수 없고, 목록에 없는 통화 삭제는 무시한다', () async {
      await ready(['USD']);

      await notifier().removeCurrency(currency('KRW'));
      expect(read().errorMessage, '기준 통화는 삭제할 수 없습니다.');

      final before = read();
      await notifier().removeCurrency(currency('EUR'));
      expect(identical(read(), before), isTrue);

      expect(visibleCodes(), ['USD']);
      expect(api.requests, hasLength(1));
    });

    test('같은 오류 문구는 다시 내보내지 않는다', () async {
      await ready(['USD']);
      await notifier().addCurrency(currency('USD'));
      var notified = 0;
      container.listen(exchangeProvider, (_, _) => notified++);

      await notifier().addCurrency(currency('USD'));

      expect(notified, 0);
    });

    test('통화 설정 저장이 실패해도 새 구성으로 다시 조회한다', () async {
      await ready(['USD']);
      storage.failSaveVisibleCurrencies = true;

      unawaited(notifier().addCurrency(currency('EUR')));
      await settle();

      expect(visibleCodes(), ['USD', 'EUR']);
      expect(api.requests.last.targets, ['USD', 'EUR']);
    });
  });

  group('대체 출처 표시', () {
    test('서버가 대체 출처 값을 주면 표시하고, 평소 출처 값이 오면 지운다', () async {
      await initializeWith(['USD']);

      api.respond(
        0,
        {'USD': 0.0007},
        fetchedAt: DateTime.now(),
        fromFallbackSource: true,
      );
      await settle();
      expect(read().usesFallbackSource, isTrue);

      final refresh = notifier().fetchRates();
      await settle();
      api.respond(1, {'USD': 0.00071}, fetchedAt: DateTime.now());
      await refresh;

      expect(read().usesFallbackSource, isFalse);
    });

    test('기준 통화를 바꿔 환율을 비우면 표시도 지운다', () async {
      await initializeWith(['USD']);
      api.respond(
        0,
        {'USD': 0.0007},
        fetchedAt: DateTime.now(),
        fromFallbackSource: true,
      );
      await settle();
      expect(read().usesFallbackSource, isTrue);

      unawaited(notifier().changeBaseCurrency(findCurrencyByCode('JPY')!));
      await settle();
      expect(read().usesFallbackSource, isFalse);
    });

    test('표시 통화를 모두 지워 환율을 비우면 표시도 지운다', () async {
      await initializeWith(['USD']);
      api.respond(
        0,
        {'USD': 0.0007},
        fetchedAt: DateTime.now(),
        fromFallbackSource: true,
      );
      await settle();
      expect(read().usesFallbackSource, isTrue);

      await notifier().removeCurrency(findCurrencyByCode('USD')!);
      await settle();

      expect(read().visibleCurrencies, isEmpty);
      expect(read().rates, isEmpty);
      expect(read().usesFallbackSource, isFalse);
      expect(api.requests, hasLength(1));
    });

    test('조회 실패로 화면 값을 유지하면 표시도 그대로 둔다', () async {
      await initializeWith(['USD']);
      api.respond(
        0,
        {'USD': 0.0007},
        fetchedAt: DateTime.now(),
        fromFallbackSource: true,
      );
      await settle();

      final refresh = notifier().fetchRates();
      await settle();
      api.fail(1, Exception('연결 실패'));
      await refresh;

      expect(read().rates, {'USD': 0.0007});
      expect(read().usesFallbackSource, isTrue);
    });
  });
}
