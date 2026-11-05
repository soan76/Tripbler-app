import 'package:flutter/material.dart';

import '../../presentation/exchange/display_currency.dart';
import 'chart_swap_motion.dart';
import 'currency_pair_side.dart';
import 'swap_pair_layout.dart';

// 이 경로로 애니메이션 정책을 쓰는 곳이 그대로 동작하게 한다.
export 'chart_swap_motion.dart';

/// [기준 아이콘] 기준 코드 ⇄ [대상 아이콘] 대상 코드.
/// [swapped]가 바뀌면 두 통화가 서로의 자리로 옮겨 가고 아이콘이 반 바퀴 돈다.
/// [baseCurrency]와 [targetCurrency]는 뒤집기 전의 원래 방향이다.
class CurrencySwapPair extends StatefulWidget {
  const CurrencySwapPair({
    super.key,
    required this.baseCurrency,
    required this.targetCurrency,
    required this.swapped,
    required this.onSwap,
    this.onPickShownBase,
    this.onPickShownTarget,
  });

  final DisplayCurrency baseCurrency;
  final DisplayCurrency targetCurrency;
  final bool swapped;

  /// 저장된 방향을 읽기 전에는 null이며, 이때 버튼은 비활성이다.
  final VoidCallback? onSwap;

  /// 화면 왼쪽(현재 기준)·오른쪽(현재 대상) 통화명을 눌렀을 때. null이면 누를 수 없고
  /// 드롭다운 표시(▾)도 두지 않는다.
  final VoidCallback? onPickShownBase;
  final VoidCallback? onPickShownTarget;

  @override
  State<CurrencySwapPair> createState() => _CurrencySwapPairState();
}

class _CurrencySwapPairState extends State<CurrencySwapPair>
    with SingleTickerProviderStateMixin {
  // 0이면 원래 방향, 1이면 뒤집은 방향의 배치. 사용자가 누를 때만 움직인다.
  late final AnimationController _motion;
  late final Animation<double> _turns;

  DisplayCurrency get _shownBase =>
      widget.swapped ? widget.targetCurrency : widget.baseCurrency;

  DisplayCurrency get _shownTarget =>
      widget.swapped ? widget.baseCurrency : widget.targetCurrency;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: chartSwapDuration,
      value: widget.swapped ? 1 : 0,
    );
    _turns = _motion.drive(Tween(begin: 0, end: 0.5));
  }

  @override
  void didUpdateWidget(covariant CurrencySwapPair oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.swapped == widget.swapped) return;
    final target = widget.swapped ? 1.0 : 0.0;
    if (animatesSwap(context, wasEnabled: oldWidget.onSwap != null)) {
      _motion.animateTo(target, curve: chartSwapCurve);
    } else {
      _motion.value = target;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 평소에는 배경 없이 강조색 아이콘만 두고, 누르는 동안에만 예전 톤 배경
    // 원을 보여 준다. 기본 밀도로 48dp 터치 영역을 유지한다.
    // tooltip은 길게 누를 때와 화면 낭독기에서 누르면 어느 통화 기준이
    // 되는지 알려 준다. 비활성일 때는 저장된 방향을 읽기 전이라 문구가
    // 틀릴 수 있어 tooltip을 숨기고, 방향 없는 라벨만 화면 낭독기에 준다.
    // 양옆 통화는 방향이 바뀌면 자리를 맞바꾼다. 키가 없으면 버튼만 새로 만들어져 키보드로
    // 누른 뒤 초점을 잃고, 그 초점이 전에 쓴 입력칸으로 돌아가 키보드가 뜬다.
    final swapButton = Padding(
      key: const ValueKey('market-chart-swap-slot'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: IconButton(
        key: const ValueKey('market-chart-swap'),
        onPressed: widget.onSwap,
        tooltip: widget.onSwap == null ? null : '${_shownTarget.code} 기준으로 바꾸기',
        iconSize: 24,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colorScheme.onSurface.withValues(alpha: 0.38)
                : colorScheme.primary,
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.secondaryContainer;
            }
            if (states.contains(WidgetState.hovered)) {
              return colorScheme.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.focused)) {
              return colorScheme.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
        // 통화 이동과 같은 진행값으로 아이콘을 반 바퀴 돌려 눌렀다는 반응과
        // 현재 방향이 바뀌었음을 함께 보여 준다.
        icon: RotationTransition(
          turns: _turns,
          child: Icon(
            Icons.swap_horiz,
            semanticLabel: widget.onSwap == null ? '기준 통화 바꾸기' : null,
          ),
        ),
      ),
    );

    // 화면 낭독기와 포커스 순서가 보이는 순서(왼쪽 → 버튼 → 오른쪽)를 따르도록
    // 자식은 현재 방향 순서로 넘기고, 위치는 [_motion]에 맞춰 배치한다.
    return SwapPairLayout(
      progress: _motion,
      swapped: widget.swapped,
      children: [
        KeyedSubtree(
          key: ValueKey('pair-${_shownBase.id}'),
          child: CurrencyPairSide(
            currency: _shownBase,
            onPick: widget.onPickShownBase,
          ),
        ),
        swapButton,
        KeyedSubtree(
          key: ValueKey('pair-${_shownTarget.id}'),
          child: CurrencyPairSide(
            currency: _shownTarget,
            onPick: widget.onPickShownTarget,
          ),
        ),
      ],
    );
  }
}
