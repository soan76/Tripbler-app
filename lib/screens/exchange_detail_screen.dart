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

  const ExchangeDetailScreen({
    super.key,
    required this.baseCurrency,
    required this.targetCurrency,
    required this.currentRate,
  });

  @override
  State<ExchangeDetailScreen> createState() => _ExchangeDetailScreenState();
}

// 환율 상세 화면의 상태를 관리하는 State 클래스
class _ExchangeDetailScreenState extends State<ExchangeDetailScreen> {
  final ExchangeApiService _apiService = ExchangeApiService();

  bool isLoading = true;
  String? errorMessage;
  Map<String, double> historicalRates = {};

  @override
  void initState() {
    super.initState();
    _loadHistoricalRates();
  }
  // 기준 통화와 상대 통화 간의 환율을 가져오는 메서드
  Future<void> _loadHistoricalRates() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    // 최근 14일간의 환율 데이터를 가져오기 위해 API 호출
    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 14));

      final result = await _apiService.fetchHistoricalRates(
        baseCurrency: widget.baseCurrency.code,
        targetCurrency: widget.targetCurrency.code,
        startDate: start,
        endDate: now,
      );

      setState(() {
        historicalRates = result;
      });
    } catch (e) {
      setState(() {
        errorMessage = '그래프 데이터를 불러오지 못했습니다.';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }
  // 그래프 영역을 구성하는 위젯을 반환하는 메서드
  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat('#,##0.####');
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
                    widget.currentRate == null
                        ? '데이터 없음'
                        : '1 ${widget.baseCurrency.code} = ${numberFormat.format(widget.currentRate)} ${widget.targetCurrency.code}',
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

  // 그래프 영역을 구성하는 위젯을 반환하는 메서드
  Widget _buildGraphArea() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadHistoricalRates,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (historicalRates.isEmpty) {
      return const Center(child: Text('표시할 그래프 데이터가 없습니다.'));
    }
    // 최근 환율 변동 데이터를 ExchangeRateHistoryModel 리스트로 변환하고 날짜순으로 정렬
    final List<ExchangeRateHistoryModel> historyList =
        historicalRates.entries.map((entry) {
          return ExchangeRateHistoryModel(
            date: DateTime.parse(entry.key),
            rate: entry.value,
            baseCurrencyCode: widget.baseCurrency.code,
            targetCurrencyCode: widget.targetCurrency.code,
          );
        }).toList()..sort((a, b) => a.date.compareTo(b.date));

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
}
