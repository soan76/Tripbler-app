import 'dart:async';
import '../../presentation/charts/chart_snapshot_store.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../presentation/exchange/display_currency.dart';
import '../../models/chart_point.dart';
import '../../presentation/charts/chart_data_source.dart';
import '../../models/exchange_rate_history_model.dart';
import '../exchange/currency_icon.dart';
import '../exchange/exchange_rate_line_chart.dart';

/// 하나의 기준 통화/대상 통화 조합에 대한
/// 현재 환율과 기간별 환율 차트를 표시하는 카드.
class MarketChartCard extends StatefulWidget {
  final DisplayCurrency iconCurrency;
  final String baseCode;
  final String targetCode;
  final String title;
  final String errorText;
  final String requestKey;
  final ChartDataSource Function() createDataSource;
  final int? maxXAxisLabels;
  final ChartPeriod period;
  final bool shouldLoad;

  const MarketChartCard({
    super.key,
    required this.iconCurrency,
    required this.baseCode,
    required this.targetCode,
    required this.title,
    required this.errorText,
    required this.requestKey,
    required this.createDataSource,
    this.maxXAxisLabels,
    required this.period,
    required this.shouldLoad,
  });

  @override
  State<MarketChartCard> createState() => _MarketChartCardState();
}

class _MarketChartCardState extends State<MarketChartCard>
    with AutomaticKeepAliveClientMixin {
  late ChartDataSource _dataSource;
  int _requestGeneration = 0;
  final _snapshots = ChartSnapshotStore();
  bool _stale = false;
  bool _historicalRate = false;

  bool isLoading = false;
  bool hasLoaded = false;
  String? errorMessage;

  List<ChartPoint> history = [];

  double? currentRate;
  DateTime? historyFetchedAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.createDataSource();

    if (widget.shouldLoad) {
      _loadChartDataIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant MarketChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final requestChanged = oldWidget.requestKey != widget.requestKey;
    final periodChanged = oldWidget.period != widget.period;
    if (requestChanged || periodChanged) {
      _requestGeneration++;
      if (requestChanged) {
        _dataSource.dispose();
        _dataSource = widget.createDataSource();
      }
      isLoading = false;
      hasLoaded = false;
      history = [];
      currentRate = null;
      historyFetchedAt = null;
      errorMessage = null;
    }
    if (widget.shouldLoad &&
        (!oldWidget.shouldLoad || requestChanged || periodChanged)) {
      _loadChartDataIfNeeded();
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

    final generation = ++_requestGeneration;
    final snapshotKey = '${widget.requestKey}/${widget.period.name}';
    final unsupported =
        widget.iconCurrency.isCrypto &&
        (widget.period == ChartPeriod.twoYears ||
            widget.period == ChartPeriod.fiveYears);
    try {
      if (history.isEmpty && !unsupported) {
        final cached = await _snapshots.read(
          snapshotKey,
          crypto: widget.iconCurrency.isCrypto,
        );
        if (!mounted || generation != _requestGeneration) return;
        if (cached != null) {
          setState(() {
            history = cached.history;
            currentRate = cached.currentRate;
            historyFetchedAt = cached.fetchedAt;
            hasLoaded = true;
            _stale = true;
            _historicalRate = cached.historicalRate;
          });
        }
      }
      final data = await _dataSource.load(widget.period);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        history = data.history;
        _stale = data.stale;
        _historicalRate = data.historicalRate;
        currentRate = data.currentRate;
        historyFetchedAt = data.fetchedAt;
        hasLoaded = true;
        isLoading = false;
      });
      unawaited(_snapshots.write(snapshotKey, data));
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        errorMessage = widget.errorText;
        hasLoaded = history.isNotEmpty;
        _stale = hasLoaded;
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
        CurrencyIcon(currency: widget.iconCurrency, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.baseCode} / '
                '${widget.targetCode}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (history.isNotEmpty &&
                  (isLoading || _stale || errorMessage != null))
                Text(
                  isLoading ? '저장된 데이터 · 갱신 중' : '마지막 성공 데이터 · 갱신 지연',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            '${_historicalRate ? '최근 기록 · ' : ''}1 ${widget.baseCode}',
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
            '${widget.targetCode}',
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

    if (isLoading && history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null && history.isEmpty) {
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

    return ExchangeRateLineChart(
      history: history,
      period: widget.period,
      maxXAxisLabels: widget.maxXAxisLabels,
    );
  }

  String _formatRate(double value) {
    final formatter = NumberFormat('#,##0.######');

    return formatter.format(value);
  }

  @override
  void dispose() {
    _requestGeneration++;
    _dataSource.dispose();
    super.dispose();
  }
}
