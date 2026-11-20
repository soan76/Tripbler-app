import 'dart:async';
import '../../services/market_snapshot_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../crypto/providers/crypto_provider.dart';
import '../../models/currency_model.dart';
import '../../providers/exchange/exchange_provider.dart';
import 'display_currency.dart';

/// 국가 통화와 코인을 한 목록으로 보여 줄 때 이 계층만 가진 값.
class ExchangeDisplayState {
  const ExchangeDisplayState({
    this.order = const <String>[],
    this.activeCrypto,
    this.krwRate,
    this.conversionError,
  });

  // 사용자가 정한 행 순서(DisplayCurrency.id)
  final List<String> order;

  // 입력 행으로 고른 코인. 국가 통화를 입력 중이면 null.
  final String? activeCrypto;

  // 기준 통화 → KRW 연결 환율. 코인 시세(KRW)를 기준 통화로 환산할 때 쓴다.
  final double? krwRate;
  final String? conversionError;

  /// 기준 통화가 바뀌면 이전 기준의 코인 입력과 KRW 환율을 버린다.
  ExchangeDisplayState resetForBase() =>
      copyWith(clearActiveCrypto: true, clearKrwRate: true);

  ExchangeDisplayState copyWith({
    List<String>? order,
    String? activeCrypto,
    bool clearActiveCrypto = false,
    double? krwRate,
    bool clearKrwRate = false,
    String? conversionError,
    bool clearConversionError = false,
  }) {
    return ExchangeDisplayState(
      order: order == null ? this.order : List<String>.unmodifiable(order),
      activeCrypto: clearActiveCrypto
          ? null
          : (activeCrypto ?? this.activeCrypto),
      krwRate: clearKrwRate ? null : (krwRate ?? this.krwRate),
      conversionError: clearConversionError
          ? null
          : (conversionError ?? this.conversionError),
    );
  }
}

/// 두 도메인의 상태를 화면에서만 조합한다. KRW 연결 환율도 이 계층에서 조회한다.
/// 화면에 보여 줄 행 목록·금액·선택 여부는 `exchangeDisplayViewProvider`가 계산한다.
class ExchangeDisplayNotifier extends Notifier<ExchangeDisplayState> {
  final _snapshots = MarketSnapshotStore();
  // 가장 최근에 시작한 KRW 환율 요청 번호
  int _request = 0;
  bool _initialized = false;
  Future<void>? _initialization;

  ExchangeNotifier get _exchange => ref.read(exchangeProvider.notifier);
  CryptoNotifier get _crypto => ref.read(cryptoProvider.notifier);

  @override
  ExchangeDisplayState build() {
    // 기준 통화가 바뀌면 이전 기준의 코인 입력과 KRW 환율을 비우고 다시 조회한다.
    ref.listen(exchangeProvider.select((s) => s.baseCurrency.code), (_, _) {
      state = state.resetForBase();
      unawaited(refreshConversion());
    });
    return const ExchangeDisplayState();
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      state = state.copyWith(
        order: prefs.getStringList('exchange.displayOrder.v1') ?? [],
      );
      await Future.wait([_exchange.initialize(), _crypto.initialize()]);
      if (!ref.mounted) return;
      unawaited(refreshConversion());
      _initialized = true;
    } finally {
      _initialization = null;
    }
  }

  Future<void> apply(List<DisplayCurrency> rows) async {
    final order = rows.map((row) => row.id).toSet().toList();
    final activeCrypto = state.activeCrypto;
    state = state.copyWith(
      order: order,
      clearActiveCrypto: !rows.any(
        (row) => row.isCrypto && row.code == activeCrypto,
      ),
    );
    final cryptoUpdate = _crypto.select(
      rows.where((row) => row.isCrypto).map((row) => row.code).toList(),
    );
    final fiatUpdate = _exchange.applyVisibleCurrencies(
      rows.map((row) => row.fiat).whereType<CurrencyModel>().toList(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('exchange.displayOrder.v1', order);
    await Future.wait([
      cryptoUpdate,
      fiatUpdate,
      if (ref.mounted) refreshConversion(),
    ]);
  }

  Future<void> refresh() async {
    await Future.wait([
      _exchange.fetchRates(),
      _crypto.refresh(),
      refreshConversion(),
    ]);
  }

  Future<void> refreshConversion() async {
    final request = ++_request;
    final baseCode = ref.read(exchangeProvider).baseCurrency.code;
    if (state.conversionError != null) {
      state = state.copyWith(clearConversionError: true);
    }
    if (baseCode == 'KRW' || ref.read(cryptoProvider).selected.isEmpty) {
      final krwRate = baseCode == 'KRW' ? 1.0 : null;
      if (state.krwRate != krwRate) {
        state = state.copyWith(krwRate: krwRate, clearKrwRate: krwRate == null);
      }
      return;
    }
    final fiatApi = ref.read(exchangeRateApiServiceProvider);
    try {
      if (state.krwRate == null) {
        final cached = await _snapshots.read(
          'conversion.$baseCode.KRW',
          const Duration(days: 3),
        );
        if (!_isCurrent(request)) return;
        final rate = (cached?['rate'] as num?)?.toDouble();
        if (rate != null && rate.isFinite && rate > 0) {
          state = state.copyWith(krwRate: rate);
        }
      }
      final response = await fiatApi.fetchLatestRatesResponse(
        baseCurrency: baseCode,
        targetCurrencies: ['KRW'],
      );
      final rate = response.rates['KRW'];
      if (rate == null || !rate.isFinite || rate <= 0) {
        throw const FormatException();
      }
      if (_isCurrent(request)) {
        state = state.copyWith(
          krwRate: rate,
          conversionError: response.stale ? '마지막 성공 KRW 환율로 환산하고 있습니다.' : null,
        );
        await _snapshots.write('conversion.$baseCode.KRW', {
          'rate': rate,
          'fetchedAt': response.fetchedAt.toIso8601String(),
        });
      }
    } catch (_) {
      if (_isCurrent(request)) {
        state = state.copyWith(
          conversionError: state.krwRate == null
              ? '암호화폐 환산에 필요한 KRW 환율을 불러오지 못했습니다.'
              : '갱신 지연으로 마지막 성공 KRW 환율로 환산합니다.',
        );
      }
    }
  }

  bool _isCurrent(int request) => ref.mounted && request == _request;

  void selectInput(DisplayCurrency row) {
    final activeCrypto = row.isCrypto ? row.code : null;
    if (state.activeCrypto != activeCrypto) {
      state = state.copyWith(
        activeCrypto: activeCrypto,
        clearActiveCrypto: activeCrypto == null,
      );
    }
    if (!row.isCrypto) _exchange.selectInputCurrency(row.code);
  }

  Future<void> changeAmount(DisplayCurrency row, double value) async {
    if (!value.isFinite || value < 0) return;
    selectInput(row);
    if (!row.isCrypto) {
      await _exchange.changeAmountFromCurrency(
        currencyCode: row.code,
        amount: value,
      );
      return;
    }
    final exchange = ref.read(exchangeProvider);
    final price = ref.read(cryptoProvider).priceFor(row.code)?.price;
    final rate = exchange.baseCurrency.code == 'KRW' ? 1.0 : state.krwRate;
    if (price == null || rate == null) return;
    final amount = value * price / rate;
    if (amount.isFinite) {
      await _exchange.changeAmountFromCurrency(
        currencyCode: exchange.baseCurrency.code,
        amount: amount,
      );
    }
  }
}

final exchangeDisplayProvider =
    NotifierProvider<ExchangeDisplayNotifier, ExchangeDisplayState>(
      ExchangeDisplayNotifier.new,
    );
