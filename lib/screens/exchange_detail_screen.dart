import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/currency_model.dart';
import '../services/exchange_api_service.dart';
import '../models/exchange_rate_history_model.dart';
import '../widgets/exchange_rate_line_chart.dart';

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

  Future<void> _loadHistoricalRates() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

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
