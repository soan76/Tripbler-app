import 'package:flutter/material.dart';

import '../../presentation/exchange/display_currency.dart';
import '../exchange/currency_icon.dart';
import 'chart_swap_motion.dart';

/// 통화쌍의 한쪽: [아이콘] 코드, [onPick]이 있으면 눌러서 통화를 고르는 ▾까지.
class CurrencyPairSide extends StatelessWidget {
  const CurrencyPairSide({
    super.key,
    required this.currency,
    required this.onPick,
  });

  final DisplayCurrency currency;

  /// null이면 누를 수 없고 드롭다운 표시(▾)도 두지 않는다.
  final VoidCallback? onPick;

  static const _iconBox = 24.0;

  @override
  Widget build(BuildContext context) {
    final onPick = this.onPick;
    final colorScheme = Theme.of(context).colorScheme;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 국기 이모지(Text)는 글꼴 줄 높이 때문에 이미지 로고보다 커 보여서
        // 같은 정사각형 안에 맞춰 두 종류의 크기와 기준선을 맞춘다.
        SizedBox.square(
          dimension: _iconBox,
          child: FittedBox(child: CurrencyIcon(currency: currency, size: 24)),
        ),
        const SizedBox(width: 6),
        // 좁은 화면이나 4자리 심볼(DOGE)은 잘라내지 않고 글자를 줄여 맞춘다.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              currency.code,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
              ),
              maxLines: 1,
            ),
          ),
        ),
        if (onPick != null)
          Icon(Icons.arrow_drop_down, size: 22, color: colorScheme.onSurface),
      ],
    );
    if (onPick == null) return content;
    // 배경 없이 아이콘·코드·▾만 둔다. 누를 수 있다는 표시는 코드와 같은 색의
    // ▾가 맡고, 강조색 아이콘인 스왑 버튼과 구분된다. 높이는 스왑 버튼과 같은
    // 48dp라 줄 높이는 늘지 않고 터치 영역은 충분하다.
    return Semantics(
      button: true,
      label: '${currency.code} 다른 통화로 바꾸기',
      // excludeSemantics가 InkWell의 탭 동작까지 가리므로 여기서 직접 알린다.
      onTap: onPick,
      excludeSemantics: true,
      child: _CurrencyPickButton(
        tapKey: ValueKey('market-chart-pick-${currency.id}'),
        onTap: onPick,
        child: content,
      ),
    );
  }
}

/// 배경 없는 통화 선택 버튼. 누르는 동안 칸 모양이 드러나지 않도록 물결과
/// 강조를 그리지 않고 내용만 살짝 흐리게 한다.
class _CurrencyPickButton extends StatefulWidget {
  const _CurrencyPickButton({
    required this.tapKey,
    required this.onTap,
    required this.child,
  });

  final Key tapKey;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_CurrencyPickButton> createState() => _CurrencyPickButtonState();
}

class _CurrencyPickButtonState extends State<_CurrencyPickButton> {
  static const _pressedOpacity = 0.55;
  static const _pressDuration = Duration(milliseconds: 100);
  static const _releaseDuration = Duration(milliseconds: 160);

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotionOf(context)
        ? Duration.zero
        : (_pressed ? _pressDuration : _releaseDuration);
    // InkWell이 그릴 표면만 두는 투명 Material이다.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: widget.tapKey,
        onTap: widget.onTap,
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Theme.of(
          context,
        ).colorScheme.surface.withValues(alpha: 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          // 왼쪽 여백이 없어 아이콘이 위 제목과 같은 선에서 시작한다.
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 2),
            child: AnimatedOpacity(
              opacity: _pressed ? _pressedOpacity : 1,
              duration: duration,
              curve: Curves.easeOut,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
