import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/currency_model.dart';
import '../services/exchange_api_service.dart';
import '../models/exchange_rate_history_model.dart';
import '../widgets/exchange_rate_line_chart.dart';

// 환율 상세 화면을 구성하는 StatefulWidget
class ExchangeDetailScreen extends StatefulWidget {
  final CurrencyModel baseCurrency;
  final CurrencyModel targetCurrency;
  final double? currentRate;
  final ExchangeApiService? apiService;

  const ExchangeDetailScreen({
    super.key,
    required this.baseCurrency,
    required this.targetCurrency,
    required this.currentRate,
    this.apiService,
  });

  @override
  State<ExchangeDetailScreen> createState() => _ExchangeDetailScreenState();
}

// 환율 상세 화면의 상태를 관리하는 State 클래스
class _ExchangeDetailScreenState extends State<ExchangeDetailScreen> {
  static const int _historyPeriodDays = 14;

  late final ExchangeApiService _apiService;
  final NumberFormat _numberFormat = NumberFormat('#,##0.####');

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, double> _historicalRates = <String, double>{};

  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ExchangeApiService();
    _loadHistoricalRates();
  }

  @override
  void dispose() {
    _requestId++;
    super.dispose();
  }

  // 기준 통화와 상대 통화 간의 환율을 가져오는 메서드
  Future<void> _loadHistoricalRates() async {
    final requestId = ++_requestId;

    if (!_isLoading || _errorMessage != null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    // 최근 14일간의 환율 데이터를 가져오기 위해 API 호출
    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: _historyPeriodDays));

      final result = await _apiService.fetchHistoricalRates(
        baseCurrency: widget.baseCurrency.code,
        targetCurrency: widget.targetCurrency.code,
        startDate: start,
        endDate: now,
      );

      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _historicalRates = Map<String, double>.from(result);
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _errorMessage = '그래프 데이터를 불러오지 못했습니다.';
        _isLoading = false;
      });
    }
  }

  // 그래프 영역을 구성하는 위젯을 반환하는 메서드
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.baseCurrency.code}/${widget.targetCurrency.code}',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '현재 환율',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatCurrentRateText(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(child: _buildGraphArea()),
          ],
        ),
      ),
    );
  }

  String _formatCurrentRateText() {
    if (widget.currentRate == null) {
      return '데이터 없음';
    }

    return '1 ${widget.baseCurrency.code} = '
        '${_numberFormat.format(widget.currentRate)} '
        '${widget.targetCurrency.code}';
  }

  // 그래프 영역을 구성하는 위젯을 반환하는 메서드
  Widget _buildGraphArea() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadHistoricalRates,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_historicalRates.isEmpty) {
      return const Center(child: Text('표시할 그래프 데이터가 없습니다.'));
    }
    // 최근 환율 변동 데이터를 ExchangeRateHistoryModel 리스트로 변환하고 날짜순으로 정렬
    final historyList = _createHistoryList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '최근 환율 변동',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        ExchangeRateLineChart(history: historyList),
      ],
    );
  }

  List<ExchangeRateHistoryModel> _createHistoryList() {
    final historyList = _historicalRates.entries.map((entry) {
      return ExchangeRateHistoryModel(
        date: DateTime.parse(entry.key),
        rate: entry.value,
        baseCurrencyCode: widget.baseCurrency.code,
        targetCurrencyCode: widget.targetCurrency.code,
      );
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    return historyList;
  }
}
