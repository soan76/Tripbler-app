import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/currency_model.dart';
import '../../models/exchange_rate_history_model.dart';
import '../../services/exchange_rate_api_service.dart';
import 'exchange_rate_line_chart.dart';

/// 하나의 기준 통화/대상 통화 조합에 대한
/// 현재 환율과 기간별 환율 차트를 표시하는 카드.
class ExchangeChartCard extends StatefulWidget {
  final CurrencyModel baseCurrency;
  final CurrencyModel targetCurrency;
  final ChartPeriod period;
  final bool shouldLoad;

  const ExchangeChartCard({
    super.key,
    required this.baseCurrency,
    required this.targetCurrency,
    required this.period,
    required this.shouldLoad,
  });

  @override
  State<ExchangeChartCard> createState() => _ExchangeChartCardState();
}

class _ExchangeChartCardState extends State<ExchangeChartCard>
    with AutomaticKeepAliveClientMixin {
  final ExchangeRateApiService _apiService = ExchangeRateApiService();

  bool isLoading = false;
  bool hasLoaded = false;
  String? errorMessage;

  List<ExchangeRateHistoryModel> history = [];

  double? currentRate;
  DateTime? historyFetchedAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    if (widget.shouldLoad) {
      _loadChartDataIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant ExchangeChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final isCurrencyChanged =
        oldWidget.baseCurrency.code != widget.baseCurrency.code ||
        oldWidget.targetCurrency.code != widget.targetCurrency.code;

    if (isCurrencyChanged) {
      hasLoaded = false;
      history = [];
      currentRate = null;
      historyFetchedAt = null;
      errorMessage = null;
    }

    final becameVisible = !oldWidget.shouldLoad && widget.shouldLoad;

    if (becameVisible || isCurrencyChanged) {
      if (widget.shouldLoad) {
        _loadChartDataIfNeeded();
      }
    }
  }

  Future<void> _loadChartDataIfNeeded() async {
    if (hasLoaded || isLoading) {
      return;
    }

    await _loadChartData();
  }

  Future<void> _loadChartData() async {
    if (isLoading) {
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // 현재 환율은 최신 환율 API에서 조회한다.
      final latestRatesResponse = await _apiService.fetchLatestRatesResponse(
        baseCurrency: widget.baseCurrency.code,
        targetCurrencies: [widget.targetCurrency.code],
      );

      // 사용자가 선택한 기간을 기준으로
      // 차트 조회 시작일을 계산한다.
      final endDate = DateTime.now();
      final startDate = widget.period.startDateFrom(endDate);

      // 기간별 환율과 조회 시각을 가져온다.
      final historyResponse = await _apiService.fetchHistoricalRatesResponse(
        baseCurrencyCode: widget.baseCurrency.code,
        targetCurrencyCode: widget.targetCurrency.code,
        startDate: startDate,
        endDate: endDate,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        history = historyResponse.rates;

        currentRate = latestRatesResponse.rates[widget.targetCurrency.code];

        historyFetchedAt = historyResponse.fetchedAt;

        hasLoaded = true;
        isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('차트 로딩 실패: $e');
      debugPrint('차트 로딩 실패 위치: $stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = '환율 차트를 불러오지 못했습니다.';
        hasLoaded = false;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: _buildCardHeader(),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _buildCurrentRateArea(),
          ),

          const SizedBox(height: 18),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: _buildChartArea(),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCardHeader() {
    return Row(
      children: [
        Text(
          widget.targetCurrency.flagEmoji,
          style: const TextStyle(fontSize: 30),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '환율 차트',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.baseCurrency.code} / '
                '${widget.targetCurrency.code}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (historyFetchedAt != null) ...[
                const SizedBox(height: 2),
                Text(
                  '업데이트: '
                  '${DateFormat('yyyy.MM.dd HH:mm').format(historyFetchedAt!.toLocal())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          onPressed: isLoading
              ? null
              : () {
                  hasLoaded = false;
                  _loadChartData();
                },
          icon: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildCurrentRateArea() {
    if (!widget.shouldLoad && !hasLoaded) {
      return Text(
        '차트를 넘기면 데이터를 불러옵니다.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }

    if (currentRate == null) {
      return Text(
        '현재 환율 정보 없음',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            '1 ${widget.baseCurrency.code}',
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Flexible(
          flex: 2,
          child: Text(
            '${_formatRate(currentRate!)} '
            '${widget.targetCurrency.code}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartArea() {
    if (!widget.shouldLoad && !hasLoaded) {
      return Center(
        child: Text(
          '이 차트는 아직 불러오지 않았습니다.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _loadChartData,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (history.isEmpty) {
      return Center(
        child: Text(
          '표시할 차트 데이터가 없습니다.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ExchangeRateLineChart(history: history, period: widget.period);
  }

  String _formatRate(double value) {
    final formatter = NumberFormat('#,##0.######');

    return formatter.format(value);
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }
}
