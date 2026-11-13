import 'dart:async';
import '../../services/market_snapshot_store.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_exception.dart';
import '../models/crypto_coin.dart';
import '../models/crypto_price.dart';
import '../services/crypto_api_service.dart';

/// 서버 암호화폐 API를 호출하는 서비스.
final cryptoApiServiceProvider = Provider<CryptoApiService>((ref) {
  final service = CryptoApiService();
  ref.onDispose(service.dispose);
  return service;
});

/// 암호화폐 목록·선택·현재가. 화면이 읽는 값만 담는다.
class CryptoState {
  const CryptoState({
    this.coins = const <CryptoCoin>[],
    this.selected = const <String>[],
    this.prices = const <String, CryptoPrice>{},
    this.errors = const <String, String>{},
    this.cachedPrices = const <String>{},
    this.pendingSymbols = const <String>{},
    this.loading = false,
    this.catalogError,
  });

  // 서버(또는 저장된 목록)에서 받은 지원 코인
  final List<CryptoCoin> coins;

  // 사용자가 고른 코인 심볼(순서 유지)
  final List<String> selected;

  final Map<String, CryptoPrice> prices;

  // 심볼별 마지막 현재가 조회 오류
  final Map<String, String> errors;

  // 기기에 저장된 값을 보여 주고 있는 심볼
  final Set<String> cachedPrices;

  // 현재가를 조회 중인 심볼
  final Set<String> pendingSymbols;

  // 코인 목록을 조회 중인지
  final bool loading;
  final String? catalogError;

  List<CryptoCoin> get selectedCoins => selected
      .map(
        (symbol) =>
            coins.where((coin) => coin.symbol == symbol).firstOrNull ??
            CryptoCoin(symbol: symbol, name: symbol),
      )
      .toList();
  CryptoPrice? priceFor(String symbol) => prices[symbol];
  bool isStale(String symbol) =>
      cachedPrices.contains(symbol) ||
      errors.containsKey(symbol) ||
      (prices[symbol]?.stale ?? false);
  String? errorFor(String symbol) => errors[symbol];
  bool isLoading(String symbol) => pendingSymbols.contains(symbol);

  CryptoState copyWith({
    List<CryptoCoin>? coins,
    List<String>? selected,
    Map<String, CryptoPrice>? prices,
    Map<String, String>? errors,
    Set<String>? cachedPrices,
    Set<String>? pendingSymbols,
    bool? loading,
    String? catalogError,
    bool clearCatalogError = false,
  }) {
    return CryptoState(
      coins: coins == null ? this.coins : List.unmodifiable(coins),
      selected: selected == null ? this.selected : List.unmodifiable(selected),
      prices: prices == null ? this.prices : Map.unmodifiable(prices),
      errors: errors == null ? this.errors : Map.unmodifiable(errors),
      cachedPrices: cachedPrices == null
          ? this.cachedPrices
          : Set.unmodifiable(cachedPrices),
      pendingSymbols: pendingSymbols == null
          ? this.pendingSymbols
          : Set.unmodifiable(pendingSymbols),
      loading: loading ?? this.loading,
      catalogError: clearCatalogError
          ? null
          : (catalogError ?? this.catalogError),
    );
  }
}

/// 암호화폐 목록/선택/현재가만 관리하며 Exchange에는 의존하지 않는다.
class CryptoNotifier extends Notifier<CryptoState> {
  final _snapshots = MarketSnapshotStore();
  // 진행 중인 현재가 요청. 같은 심볼의 요청을 하나로 합친다.
  final Map<String, Future<void>> _pending = {};
  bool _initialized = false;
  Future<void>? _initialization;
  Future<void>? _catalogRequest;

  CryptoApiService get _api => ref.read(cryptoApiServiceProvider);

  @override
  CryptoState build() => const CryptoState();

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      final selected = prefs.getStringList('crypto.selected.v1') ?? [];
      var coins = state.coins;
      try {
        final cached = prefs.getString('crypto.catalog.v1');
        if (cached != null) {
          coins = (jsonDecode(cached) as List)
              .map((e) => CryptoCoin.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {
        /* 손상된 목록 캐시는 서버에서 복구. */
      }
      state = state.copyWith(selected: selected, coins: coins);
      await Future.wait(selected.map(_restorePrice));
      if (!ref.mounted) return;
      _initialized = true;
      unawaited(refresh());
    } finally {
      _initialization = null;
    }
  }

  Future<void> refreshCatalog() => _catalogRequest ??= _loadCatalog();

  Future<void> _loadCatalog() async {
    state = state.copyWith(loading: true, clearCatalogError: true);
    try {
      final coins = await _api.fetchCoins();
      if (!ref.mounted) return;
      state = state.copyWith(coins: coins);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'crypto.catalog.v1',
        jsonEncode(coins.map((e) => e.toJson()).toList()),
      );
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          catalogError: error is ApiException
              ? error.message
              : '암호화폐 목록을 불러오지 못했습니다.',
        );
      }
    } finally {
      _catalogRequest = null;
      if (ref.mounted) state = state.copyWith(loading: false);
    }
  }

  Future<void> select(List<String> symbols) async {
    final current = state;
    final allowed = {
      ...current.coins.map((e) => e.symbol),
      ...current.selected,
    };
    final selected = symbols.where(allowed.contains).toSet().toList();
    state = current.copyWith(selected: selected);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('crypto.selected.v1', selected);
    if (ref.mounted) await refreshPrices();
  }

  Future<void> refresh() async {
    await Future.wait([refreshCatalog(), refreshPrices()]);
  }

  Future<void> _restorePrice(String symbol) async {
    if (state.prices.containsKey(symbol)) return;
    final json = await _snapshots.read(
      'crypto.price.$symbol.KRW',
      const Duration(minutes: 15),
    );
    if (!ref.mounted || json == null || state.prices.containsKey(symbol)) {
      return;
    }
    try {
      final price = CryptoPrice.fromJson(json);
      if (price.symbol != symbol) return;
      state = state.copyWith(
        prices: {...state.prices, symbol: price},
        cachedPrices: {...state.cachedPrices, symbol},
      );
    } catch (_) {
      /* 손상된 캐시는 무시한다. */
    }
  }

  Future<void> refreshPrices() =>
      Future.wait(state.selected.map(fetchPrice)).then((_) {});

  Future<void> fetchPrice(String symbol) {
    final existing = _pending[symbol];
    if (existing != null) return existing;
    final request = _loadPrice(symbol);
    _pending[symbol] = request;
    state = state.copyWith(pendingSymbols: _pending.keys.toSet());
    return request;
  }

  Future<void> _loadPrice(String symbol) async {
    try {
      await _restorePrice(symbol);
      if (!ref.mounted) return;
      final price = await _api.fetchPrice(symbol);
      if (!ref.mounted) return;
      state = state.copyWith(
        prices: {...state.prices, symbol: price},
        errors: Map.of(state.errors)..remove(symbol),
        cachedPrices: state.cachedPrices.difference({symbol}),
      );
      await _snapshots.write('crypto.price.$symbol.KRW', price.toJson());
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          errors: {
            ...state.errors,
            symbol: error is ApiException ? error.message : '현재가를 불러오지 못했습니다.',
          },
        );
      }
    } finally {
      _pending.remove(symbol);
      if (ref.mounted) {
        state = state.copyWith(pendingSymbols: _pending.keys.toSet());
      }
    }
  }
}

final cryptoProvider = NotifierProvider<CryptoNotifier, CryptoState>(
  CryptoNotifier.new,
);
