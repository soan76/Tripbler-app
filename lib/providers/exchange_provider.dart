import 'package:flutter/material.dart';

import '../models/currency_model.dart';
import '../services/exchange_api_service.dart';
import '../services/local_storage_service.dart';

// 환율 화면에서 사용하는 상태와 동작을 관리
class ExchangeProvider extends ChangeNotifier {
  // 최신 환율 데이터를 서버에서 받아오는 API 서비스
  final ExchangeApiService _apiService = ExchangeApiService();
  // 선택 통화, 입력 금액, 캐시 환율 등을 기기에 저장하는 로컬 저장소 서비스
  final LocalStorageService _localStorageService = LocalStorageService();

  // 환율 계산의 기준이 되는 통화
  // 앱을 처음 실행할 때는 대한민국 원화(KRW)를 기본값으로 사용
  CurrencyModel _baseCurrency = findCurrencyByCode('KRW');

  // 기준 통화를 제외하고 화면에 표시할 상대 통화 목록
  List<CurrencyModel> _visibleCurrencies = [];

  // 사용자가 입력한 기준 통화 금액
  // 기본값은 10,000원
  double _inputAmount = 10000;
  // 통화 코드별 환율을 저장하는 Map
  Map<String, double> _rates = {};
  bool _isLoading = false;
  // API 요청 실패나 잘못된 동작이 발생했을 때 표시할 오류 메시지
  String? _errorMessage;
  DateTime? _lastUpdated;

  bool _hasInitialized = false;
  
  CurrencyModel get baseCurrency => _baseCurrency;
  List<CurrencyModel> get visibleCurrencies => _visibleCurrencies;
  double get inputAmount => _inputAmount;
  Map<String, double> get rates => _rates;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;

  // 기준 통화를 포함한 모든 화면에 표시할 통화 목록
  List<CurrencyModel> get allRows {
    return [_baseCurrency, ..._visibleCurrencies];
  }

  // 앱 초기화 시 로컬 저장소에서 이전 상태를 불러오고 최신 환율을 가져오는 메서드
  Future<void> initialize() async {
    if (_hasInitialized) {
      return;
    }

    _hasInitialized = true;

    await _loadSavedState();
    await fetchRates();
  }

  // 로컬 저장소에서 이전 상태를 불러오는 메서드
  Future<void> _loadSavedState() async {
    final savedBaseCode = await _localStorageService.loadBaseCurrency();
    final savedVisibleCodes = await _localStorageService
        .loadVisibleCurrencies();
    final savedRates = await _localStorageService.loadCachedRates();
    final savedLastUpdated = await _localStorageService.loadLastUpdated();
    final savedAmount = await _localStorageService.loadInputAmount();

    // 로컬 저장소에서 불러온 기준 통화 코드가 존재하면 해당 통화를 기준 통화로 설정
    if (savedBaseCode != null) {
      _baseCurrency = findCurrencyByCode(savedBaseCode);
    }

    // 기준 통화를 제외한 화면에 표시할 통화 목록을 로컬 저장소에서 불러옴
    if (savedVisibleCodes != null && savedVisibleCodes.isNotEmpty) {
      _visibleCurrencies = savedVisibleCodes
          .where((code) => code != _baseCurrency.code)
          .map(findCurrencyByCode)
          .toList();
    }

    /// 로컬 저장소에서 불러온 환율 데이터와 마지막 업데이트 시간을 상태에 반영
    if (savedRates != null) {
      _rates = savedRates;
    }

    if (savedLastUpdated != null) {
      _lastUpdated = savedLastUpdated;
    }

    if (savedAmount != null) {
      _inputAmount = savedAmount;
    }

    notifyListeners();
  }

  // 서버에서 최신 환율 데이터를 가져오는 메서드
  Future<void> fetchRates() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final targetCodes = _visibleCurrencies.map((e) => e.code).toList();

      final latestRates = await _apiService.fetchLatestRates(
        baseCurrency: _baseCurrency.code,
        targetCurrencies: targetCodes,
      );

      _rates = latestRates;
      _lastUpdated = DateTime.now();

      await _localStorageService.saveCachedRates(_rates);
      await _localStorageService.saveLastUpdated(_lastUpdated!);
    } catch (e) {
      final cachedRates = await _localStorageService.loadCachedRates();

      if (cachedRates != null && cachedRates.isNotEmpty) {
        _rates = cachedRates;
        _errorMessage = '최신 환율을 불러오지 못했습니다. 마지막 저장 데이터를 표시합니다.';
      } else {
        _errorMessage = '환율 데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 사용자가 입력한 기준 통화 금액을 변경하는 메서드
  Future<void> changeAmount(double amount) async {
    _inputAmount = amount;
    await _localStorageService.saveInputAmount(amount);
    notifyListeners();
  }

  // 기준 통화를 변경하는 메서드
  Future<void> changeBaseCurrency(CurrencyModel currency) async {
    if (_baseCurrency.code == currency.code) {
      return;
    }

    // 기준 통화를 변경할 때, 기존 기준 통화를 화면에 표시할 상대 통화 목록에 추가
    final oldBase = _baseCurrency;
    // 기존 기준 통화가 화면에 표시할 상대 통화 목록에 있으면 제거
    _visibleCurrencies.removeWhere((item) => item.code == currency.code);

    // 기존 기준 통화가 화면에 표시할 상대 통화 목록에 없으면 추가
    if (!_visibleCurrencies.any((item) => item.code == oldBase.code)) {
      _visibleCurrencies.insert(0, oldBase);
    }

    _baseCurrency = currency;

    await _saveCurrencyState();
    await fetchRates();
  }

  // 화면에 표시할 상대 통화를 교체하는 메서드
  Future<void> replaceVisibleCurrency({
    required int index,
    required CurrencyModel newCurrency,
  }) async {
    if (newCurrency.code == _baseCurrency.code) {
      return;
    }
    // 중복된 통화가 이미 화면에 표시되고 있는지 확인
    final duplicateIndex = _visibleCurrencies.indexWhere(
      (item) => item.code == newCurrency.code,
    );

    // 중복된 통화가 이미 화면에 표시되고 있고, 교체하려는 위치와 다르면 교체하지 않음
    if (duplicateIndex != -1 && duplicateIndex != index) {
      return;
    }

    _visibleCurrencies[index] = newCurrency;

    await _saveCurrencyState();
    await fetchRates();
  }

  // 화면에 표시할 상대 통화 목록을 새로 적용하는 메서드
  Future<void> applyVisibleCurrencies(List<CurrencyModel> currencies) async {
    _visibleCurrencies = currencies
        .where((currency) => currency.code != _baseCurrency.code)
        .toList();

    await _saveCurrencyState();
    await fetchRates();
  }

  // 화면에 표시할 상대 통화를 추가하는 메서드
  Future<void> addCurrency(CurrencyModel currency) async {
    if (currency.code == _baseCurrency.code) {
      return;
    }

    if (_visibleCurrencies.any((item) => item.code == currency.code)) {
      return;
    }

    _visibleCurrencies.add(currency);

    await _saveCurrencyState();
    await fetchRates();
  }

  // 화면에 표시할 상대 통화를 제거하는 메서드
  Future<void> removeCurrency(CurrencyModel currency) async {
    if (currency.code == _baseCurrency.code) {
      _errorMessage = '기준 통화는 삭제할 수 없습니다.';
      notifyListeners();
      return;
    }

    _visibleCurrencies.removeWhere((item) => item.code == currency.code);

    await _saveCurrencyState();
    await fetchRates();
  }

  // 기준 통화 금액을 입력받아 상대 통화 금액으로 변환하는 메서드
  double convertedAmount(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return _inputAmount;
    }

    final rate = _rates[targetCode];

    if (rate == null) {
      return 0;
    }

    return _inputAmount * rate;
  }
  // 기준 통화와 상대 통화 간의 환율을 가져오는 메서드
  double? rateFor(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return 1;
    }

    return _rates[targetCode];
  }
  // 기준 통화와 상대 통화 간의 환율을 가져오는 메서드
  Future<void> _saveCurrencyState() async {
    await _localStorageService.saveBaseCurrency(_baseCurrency.code);
    await _localStorageService.saveVisibleCurrencies(
      _visibleCurrencies.map((e) => e.code).toList(),
    );

    notifyListeners();
  }
}
