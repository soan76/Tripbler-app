import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/currency_model.dart';
import '../models/exchange_rate_history_model.dart';
import '../services/exchange_api_service.dart';
import 'exchange_rate_line_chart.dart';

/// 환율 차트 캐러셀 위젯
/// 이 위젯은 기본 통화와 대상 통화 목록을 받아서, 각 대상 통화에 대한 환율 차트를 페이지 뷰 형태로 보여줌.
class ExchangeChartCarousel extends StatefulWidget {
  final CurrencyModel baseCurrency;
  final List<CurrencyModel> targetCurrencies;

  const ExchangeChartCarousel({
    super.key,
    required this.baseCurrency,
    required this.targetCurrencies,
  });

  @override
  State<ExchangeChartCarousel> createState() => _ExchangeChartCarouselState();
}
/// 환율 차트 캐러셀 위젯 상태 클래스
class _ExchangeChartCarouselState extends State<ExchangeChartCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.92);

  int currentPage = 0;

  @override
  void didUpdateWidget(covariant ExchangeChartCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.targetCurrencies.length != oldWidget.targetCurrencies.length) {
      if (currentPage >= widget.targetCurrencies.length) {
        setState(() {
          currentPage = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.targetCurrencies.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 430,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.targetCurrencies.length,
            onPageChanged: (index) {
              setState(() {
                currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              final targetCurrency = widget.targetCurrencies[index];

              return Padding(
                padding: EdgeInsets.only(
                  right: index == widget.targetCurrencies.length - 1 ? 0 : 12,
                ),
                child: _ExchangeChartCard(
                  key: ValueKey(
                    '${widget.baseCurrency.code}-${targetCurrency.code}',
                  ),
                  baseCurrency: widget.baseCurrency,
                  targetCurrency: targetCurrency,

                  // 현재 차트와 양옆 차트를 미리 불러옴.
                  shouldLoad: currentPage == index,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildPageIndicator(),
      ],
    );
  }
  // 페이지 인디케이터를 빌드하는 메서드
  Widget _buildPageIndicator() {
    if (widget.targetCurrencies.length <= 1) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.targetCurrencies.length, (index) {
        final isSelected = currentPage == index;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isSelected ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
/// 환율 차트 카드 위젯
class _ExchangeChartCard extends StatefulWidget {
  final CurrencyModel baseCurrency;
  final CurrencyModel targetCurrency;
  final bool shouldLoad;

  const _ExchangeChartCard({
    super.key,
    required this.baseCurrency,
    required this.targetCurrency,
    required this.shouldLoad,
  });

  @override
  State<_ExchangeChartCard> createState() => _ExchangeChartCardState();
}
/// 환율 차트 카드 위젯 상태 클래스
class _ExchangeChartCardState extends State<_ExchangeChartCard>
    with AutomaticKeepAliveClientMixin {
  final ExchangeApiService _apiService = ExchangeApiService();

  bool isLoading = false;
  bool hasLoaded = false;
  String? errorMessage;
  List<ExchangeRateHistoryModel> history = [];
  double? currentRate;

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
  void didUpdateWidget(covariant _ExchangeChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final isCurrencyChanged =
        oldWidget.baseCurrency.code != widget.baseCurrency.code ||
        oldWidget.targetCurrency.code != widget.targetCurrency.code;

    if (isCurrencyChanged) {
      hasLoaded = false;
      history = [];
      currentRate = null;
      errorMessage = null;
    }

    final becameVisible = !oldWidget.shouldLoad && widget.shouldLoad;

    if (becameVisible || isCurrencyChanged) {
      if (widget.shouldLoad) {
        _loadChartDataIfNeeded();
      }
    }
  }
  // 차트 데이터를 불러와야 하는지 확인하고 필요하면 불러오는 메서드  
  Future<void> _loadChartDataIfNeeded() async {
    if (hasLoaded || isLoading) {
      return;
    }

    await _loadChartData();
  }
  // 차트 데이터를 불러오는 메서드
  Future<void> _loadChartData() async {
    if (isLoading) {
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // 최신 환율을 먼저 불러옴.
      final historicalRates = await _apiService
          .fetchHistoricalRates(
            baseCurrencyCode: widget.baseCurrency.code,
            targetCurrencyCode: widget.targetCurrency.code,
            period: ChartPeriod.oneMonth,
          )
          // 차트 요청 시간이 초과되면 예외를 발생시키도록 설정.
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw Exception('차트 요청 시간이 초과되었습니다.');
            },
          );

      if (!mounted) {
        return;
      }
      // 데이터를 성공적으로 불러왔으므로 상태를 업데이트.
      setState(() {
        history = historicalRates;
        currentRate = historicalRates.isEmpty
            ? null
            : historicalRates.last.rate;
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final latestDate = history.isEmpty ? null : history.last.date;
    // 카드 전체를 감싸는 컨테이너
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(latestDate),
          const SizedBox(height: 16),
          _buildCurrentRateArea(),
          const SizedBox(height: 18),
          Expanded(child: _buildChartArea()),
        ],
      ),
    );
  }
  // 카드 헤더를 빌드하는 메서드
  Widget _buildCardHeader(DateTime? latestDate) {
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
              const Text(
                '환율 차트',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.baseCurrency.code} / ${widget.targetCurrency.code}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (latestDate != null) ...[
                const SizedBox(height: 2),
                Text(
                  '업데이트: ${DateFormat('yyyy.MM.dd').format(latestDate)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
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
  // 현재 환율 영역을 빌드하는 메서드
  Widget _buildCurrentRateArea() {
    if (!widget.shouldLoad && !hasLoaded) {
      return const Text(
        '차트를 넘기면 데이터를 불러옵니다.',
        style: TextStyle(color: Colors.black54),
      );
    }

    if (currentRate == null) {
      return const Text('현재 환율 정보 없음', style: TextStyle(color: Colors.black54));
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            '1 ${widget.baseCurrency.code}',
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Flexible(
          flex: 2,
          child: Text(
            '${_formatRate(currentRate!)} ${widget.targetCurrency.code}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartArea() {
    if (!widget.shouldLoad && !hasLoaded) {
      return const Center(
        child: Text(
          '이 차트는 아직 불러오지 않았습니다.',
          style: TextStyle(color: Colors.black54),
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
            Text(errorMessage!, style: const TextStyle(color: Colors.black54)),
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
      return const Center(
        child: Text(
          '표시할 차트 데이터가 없습니다.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return ExchangeRateLineChart(history: history);
  }

  String _formatRate(double value) {
    final formatter = NumberFormat('#,##0.######');
    return formatter.format(value);
  }
}
