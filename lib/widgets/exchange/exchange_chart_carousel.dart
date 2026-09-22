import 'package:flutter/material.dart';

import '../../models/currency_model.dart';
import '../../models/exchange_rate_history_model.dart';
import 'exchange_chart_card.dart';
import 'exchange_chart_period_selector.dart';

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
  final PageController _pageController = PageController();

  int currentPage = 0;

  ChartPeriod _selectedPeriod = ChartPeriod.oneMonth;

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
        ExchangeChartPeriodSelector(
          selectedPeriod: _selectedPeriod,
          onPeriodChanged: (period) {
            setState(() {
              _selectedPeriod = period;
            });
          },
        ),
        const SizedBox(height: 12),

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

              return ExchangeChartCard(
                key: ValueKey(
                  '${widget.baseCurrency.code}-'
                  '${targetCurrency.code}-'
                  '${_selectedPeriod.name}',
                ),
                baseCurrency: widget.baseCurrency,
                targetCurrency: targetCurrency,
                period: _selectedPeriod,

                // 현재 화면에 표시 중인 차트만 필요할 때 데이터를 불러온다.
                shouldLoad: currentPage == index,
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

    final colorScheme = Theme.of(context).colorScheme;

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
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
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