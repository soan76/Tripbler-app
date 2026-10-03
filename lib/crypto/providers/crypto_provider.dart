import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_exception.dart';
import '../models/crypto_coin.dart';
import '../models/crypto_price.dart';
import '../services/crypto_api_service.dart';

/// 암호화폐 목록/선택/현재가만 관리하며 Exchange에는 의존하지 않는다.
class CryptoProvider extends ChangeNotifier {
  CryptoProvider({CryptoApiService? api})
    : _api = api ?? CryptoApiService(),
      _ownsApi = api == null;
  final CryptoApiService _api;
  final bool _ownsApi;
  List<CryptoCoin> _coins = [];
  List<String> _selected = [];
  final Map<String, CryptoPrice> _prices = {};
  final Map<String, String> _errors = {};
  final Map<String, Future<void>> _pending = {};
  bool _disposed = false;
  bool _initialized = false;
  bool loading = false;
  String? catalogError;
  Future<void>? _initialization;
  Future<void>? _catalogRequest;

  List<CryptoCoin> get coins => List.unmodifiable(_coins);
  List<CryptoCoin> get selectedCoins => _selected
      .map(
        (symbol) =>
            _coins.where((coin) => coin.symbol == symbol).firstOrNull ??
            CryptoCoin(symbol: symbol, name: symbol),
      )
      .toList();
  CryptoPrice? priceFor(String symbol) =>
      _errors.containsKey(symbol) ? null : _prices[symbol];
  String? errorFor(String symbol) => _errors[symbol];
  bool isLoading(String symbol) => _pending.containsKey(symbol);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _selected = prefs.getStringList('crypto.selected.v1') ?? [];
      try {
        final cached = prefs.getString('crypto.catalog.v1');
        if (cached != null) {
          _coins = (jsonDecode(cached) as List)
              .map((e) => CryptoCoin.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {
        /* 손상된 목록 캐시는 서버에서 복구. */
      }
      _notify();
      await refresh();
      _initialized = true;
    } finally {
      _initialization = null;
    }
  }

  Future<void> refreshCatalog() => _catalogRequest ??= _loadCatalog();

  Future<void> _loadCatalog() async {
    loading = true;
    catalogError = null;
    _notify();
    try {
      final coins = await _api.fetchCoins();
      if (_disposed) return;
      _coins = coins;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'crypto.catalog.v1',
        jsonEncode(coins.map((e) => e.toJson()).toList()),
      );
    } catch (error) {
      if (!_disposed) {
        catalogError = error is ApiException
            ? error.message
            : '암호화폐 목록을 불러오지 못했습니다.';
      }
    } finally {
      loading = false;
      _catalogRequest = null;
      _notify();
    }
  }

  Future<void> select(List<String> symbols) async {
    final allowed = {..._coins.map((e) => e.symbol), ..._selected};
    _selected = symbols.where(allowed.contains).toSet().toList();
    _notify();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('crypto.selected.v1', _selected);
    if (!_disposed) await refreshPrices();
  }

  Future<void> refresh() async {
    await refreshCatalog();
    if (!_disposed) await refreshPrices();
  }

  Future<void> refreshPrices() =>
      Future.wait(_selected.map(fetchPrice)).then((_) {});

  Future<void> fetchPrice(String symbol) {
    final existing = _pending[symbol];
    if (existing != null) return existing;
    final request = _loadPrice(symbol);
    _pending[symbol] = request;
    _notify();
    return request;
  }

  Future<void> _loadPrice(String symbol) async {
    try {
      final price = await _api.fetchPrice(symbol);
      if (_disposed) return;
      _prices[symbol] = price;
      _errors.remove(symbol);
    } catch (error) {
      if (!_disposed) {
        _errors[symbol] = error is ApiException
            ? error.message
            : '현재가를 불러오지 못했습니다.';
      }
    } finally {
      _pending.remove(symbol);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsApi) _api.dispose();
    super.dispose();
  }
}
