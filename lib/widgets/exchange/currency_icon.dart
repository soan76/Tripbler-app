import 'package:flutter/material.dart';

import '../../presentation/exchange/display_currency.dart';

/// 국가 통화는 국기 이모지, 암호화폐는 앱에 포함된 개별 로고를 표시한다.
class CurrencyIcon extends StatelessWidget {
  const CurrencyIcon({super.key, required this.currency, this.size = 28});

  final DisplayCurrency currency;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = currency.iconAssetPath;
    final fallback = Text(currency.flagEmoji, style: TextStyle(fontSize: size));
    if (path == null) return fallback;

    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: '${currency.countryName} 로고',
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: Center(child: fallback),
      ),
    );
  }
}
