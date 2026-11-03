import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/exchange_rate_history_model.dart';
import '../../presentation/charts/chart_swap_store.dart';
import '../exchange/exchange_chart_period_selector.dart';

/// 환율 차트 캐러셀 위젯
/// 이 위젯은 기본 통화와 대상 통화 목록을 받아서, 각 대상 통화에 대한 환율 차트를 페이지 뷰 형태로 보여줌.
class MarketChartCarousel extends StatefulWidget {
  final List<String> itemIds;

  /// (context, index, period, shouldLoad, swapped, onSwap)
  /// onSwap은 저장된 방향을 읽기 전까지 null이다.
  final Widget Function(
    BuildContext,
    int,
    ChartPeriod,
    bool,
    bool,
    VoidCallback?,
  )
  cardBuilder;
  final bool active;

  /// 카드 뒤에 붙는 마지막 페이지(예: 차트 추가). null이면 두지 않는다.
  final Widget? trailing;

  /// 같은 자리 카드 하나의 ID만 바뀌었을 때(통화 변경) 새 카드의 방향.
  /// 이 변경을 만든 쪽(선택창의 한쪽 통화 변경)이 알려 준 방향만 새 ID에 쓴다.
  /// 비우거나 null을 돌려주면(삭제와 추가가 한 번에 반영된 경우 등) 옛 카드의
  /// 방향을 옮기지 않고 새 카드를 정방향으로 둔다.
  final bool? Function(String oldId, String newId)? swappedAfterReplace;

  const MarketChartCarousel({
    super.key,
    required this.itemIds,
    required this.cardBuilder,
    this.active = true,
    this.trailing,
    this.swappedAfterReplace,
  });

  @override
  State<MarketChartCarousel> createState() => _MarketChartCarouselState();
}

/// 환율 차트 캐러셀 위젯 상태 클래스
class _MarketChartCarouselState extends State<MarketChartCarousel> {
  final PageController _pageController = PageController();

  int currentPage = 0;

  ChartPeriod _selectedPeriod = ChartPeriod.oneMonth;

  // 기간을 바꾸면 카드가 새로 만들어지므로 통화 방향은 캐러셀이 카드별로 보관한다.
  final _swapStore = ChartSwapStore();
  Set<String> _swappedIds = {};
  bool _swapLoaded = false;

  // 저장값을 읽기 전에 통화가 바뀐 카드의 방향(새 ID → 뒤집힘). 읽은 뒤 반영한다.
  final Map<String, bool> _pendingSwaps = {};

  @override
  void initState() {
    super.initState();
    _swapStore.read().then((ids) {
      if (!mounted) return;
      setState(() {
        // 저장값을 읽은 뒤에만 정리해 읽기 전 상태로 기존 값을 지우지 않는다.
        _swappedIds = ChartSwapStore.retained(ids, widget.itemIds);
        _swapLoaded = true;
        _pendingSwaps.forEach(_setSwap);
        _pendingSwaps.clear();
      });
      unawaited(_swapStore.retain(widget.itemIds));
    });
  }

  // 메모리와 저장값의 [id] 방향을 정한다(같은 값이어도 남은 옛 저장값을 덮어쓴다).
  void _setSwap(String id, bool swapped) {
    _swappedIds = {..._swappedIds};
    swapped ? _swappedIds.add(id) : _swappedIds.remove(id);
    unawaited(_swapStore.write(id, swapped: swapped));
  }

  // 같은 자리 카드 하나의 ID만 바뀌었으면 (옛 ID, 새 ID)를 돌려준다.
  static (String, String)? _replacedInPlace(
    List<String> oldIds,
    List<String> newIds,
  ) {
    if (oldIds.length != newIds.length) return null;
    (String, String)? replaced;
    for (var i = 0; i < oldIds.length; i++) {
      if (oldIds[i] == newIds[i]) continue;
      if (replaced != null) return null;
      replaced = (oldIds[i], newIds[i]);
    }
    if (replaced == null ||
        newIds.contains(replaced.$1) ||
        oldIds.contains(replaced.$2)) {
      return null;
    }
    return replaced;
  }

  void _toggleSwap(String id) {
    final swapped = !_swappedIds.contains(id);
    setState(() {
      _swappedIds = {..._swappedIds};
      swapped ? _swappedIds.add(id) : _swappedIds.remove(id);
    });
    unawaited(_swapStore.write(id, swapped: swapped));
  }

  @override
  void didUpdateWidget(covariant MarketChartCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 선택창에서 카드의 통화를 바꾸면 화면에 보이던 좌우가 유지되도록 알려 준
    // 방향을 새 ID에 쓴다. 알려 준 방향이 없으면 다른 쌍으로 바뀐 것이므로
    // 옛 카드의 방향을 옮기지 않고 정방향으로 둔다.
    final replaced = _replacedInPlace(oldWidget.itemIds, widget.itemIds);
    if (replaced != null) {
      final (oldId, newId) = replaced;
      if (!_swapLoaded) _pendingSwaps.remove(oldId);
      final swapped = widget.swappedAfterReplace?.call(oldId, newId) ?? false;
      if (_swapLoaded) {
        _setSwap(newId, swapped);
      } else {
        _pendingSwaps[newId] = swapped;
      }
    }

    // 삭제된 통화나 바뀐 기준 통화의 옛 조합은 방향 저장값에서 지운다.
    // 목록이 비어 있으면 retain이 아무것도 지우지 않는다.
    if (_swapLoaded && !listEquals(oldWidget.itemIds, widget.itemIds)) {
      _swappedIds = ChartSwapStore.retained(_swappedIds, widget.itemIds);
      unawaited(_swapStore.retain(widget.itemIds));
    }

    // 삭제/재정렬 후에도 보고 있던 카드를 가능한 한 유지한다. 그 카드의 통화만
    // 바뀌었거나 지워졌으면 같은 자리(없으면 마지막 카드)에 머문다. 추가 페이지에서
    // 카드를 더했으면 새 카드로 간다.
    final oldIds = oldWidget.itemIds;
    final newIds = widget.itemIds;
    int nextPage;
    if (currentPage < oldIds.length) {
      final index = newIds.indexOf(oldIds[currentPage]);
      nextPage = index >= 0 ? index : math.min(currentPage, newIds.length - 1);
    } else {
      nextPage = newIds.length > oldIds.length
          ? newIds.length - 1
          : currentPage;
    }
    nextPage = nextPage.clamp(0, math.max(0, _pageCount - 1));
    if (nextPage != currentPage || newIds.length != oldIds.length) {
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

  int get _pageCount =>
      widget.itemIds.length + (widget.trailing == null ? 0 : 1);

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
            itemCount: _pageCount,
            onPageChanged: (index) {
              setState(() {
                currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              if (index >= widget.itemIds.length) {
                return KeyedSubtree(
                  key: const ValueKey('market-chart-trailing'),
                  child: widget.trailing!,
                );
              }
              final id = widget.itemIds[index];
              return KeyedSubtree(
                key: ValueKey(id),
                child: widget.cardBuilder(
                  context,
                  index,
                  _selectedPeriod,
                  widget.active && currentPage == index,
                  _swappedIds.contains(id) || (_pendingSwaps[id] ?? false),
                  _swapLoaded ? () => _toggleSwap(id) : null,
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
    if (_pageCount <= 1) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pageCount, (index) {
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
