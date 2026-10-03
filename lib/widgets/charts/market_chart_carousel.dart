import 'package:flutter/material.dart';

import '../../models/exchange_rate_history_model.dart';
import '../exchange/exchange_chart_period_selector.dart';

/// 환율 차트 캐러셀 위젯
/// 이 위젯은 기본 통화와 대상 통화 목록을 받아서, 각 대상 통화에 대한 환율 차트를 페이지 뷰 형태로 보여줌.
class MarketChartCarousel extends StatefulWidget {
  final List<String> itemIds;
  final Widget Function(BuildContext, int, ChartPeriod, bool) cardBuilder;
  final bool active;

  const MarketChartCarousel({
    super.key,
    required this.itemIds,
    required this.cardBuilder,
    this.active = true,
  });

  @override
  State<MarketChartCarousel> createState() => _MarketChartCarouselState();
}

/// 환율 차트 캐러셀 위젯 상태 클래스
class _MarketChartCarouselState extends State<MarketChartCarousel> {
  final PageController _pageController = PageController();

  int currentPage = 0;

  ChartPeriod _selectedPeriod = ChartPeriod.oneMonth;

  @override
  void didUpdateWidget(covariant MarketChartCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 삭제/재정렬 후에도 보고 있던 코인을 가능한 한 유지한다.
    final previousId = currentPage < oldWidget.itemIds.length
        ? oldWidget.itemIds[currentPage]
        : null;
    var nextPage = previousId == null ? 0 : widget.itemIds.indexOf(previousId);
    if (nextPage < 0) nextPage = 0;
    if (nextPage != currentPage ||
        widget.itemIds.length != oldWidget.itemIds.length) {
      currentPage = nextPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _pageController.hasClients &&
            widget.itemIds.isNotEmpty) {
          _pageController.jumpToPage(currentPage);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemIds.isEmpty) {
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
            itemCount: widget.itemIds.length,
            onPageChanged: (index) {
              setState(() {
                currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              return KeyedSubtree(
                key: ValueKey(widget.itemIds[index]),
                child: widget.cardBuilder(
                  context,
                  index,
                  _selectedPeriod,
                  widget.active && currentPage == index,
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
    if (widget.itemIds.length <= 1) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.itemIds.length, (index) {
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
