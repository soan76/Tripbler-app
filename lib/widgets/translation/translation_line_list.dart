import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/translation/line_translation_result.dart';

/// 찍기 모드 결과: 찍은 사진 요약, 줄마다 번역·원화 가격·원문·한글 발음, 안내 문구.
class TranslationLineList extends StatelessWidget {
  const TranslationLineList({
    super.key,
    required this.result,
    required this.imagePath,
    required this.omittedLineCount,
  });

  final LineTranslationResult result;
  final String? imagePath;
  final int omittedLineCount;

  static final NumberFormat _rateFormat = NumberFormat('#,##0.##');
  static final Map<int, NumberFormat> _smallRateFormats = {};
  static final DateFormat _timeFormat = DateFormat('MM.dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ratePrices = result.firstConvertedPricePerCurrency;
    final prices = [
      for (final line in result.lines)
        if (line.price != null) line.price!,
    ];
    final hasStaleRate = prices.any(
      (price) => price.krwAmount != null && price.rateStale,
    );
    // 원화 가격이 아닌데 원화로 바꾸지 못한 가격(환율 실패).
    final hasUnconvertedPrice = prices.any(
      (price) => price.krwAmount == null && price.currency != 'KRW',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 요약: 사진 썸네일, 줄 수, 환율 기준
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imagePath != null) ...[
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    File(imagePath!),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 56, height: 56),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.lines.isEmpty
                        ? '번역할 글자를 찾지 못했어요'
                        : '${result.lines.length}줄을 번역했어요',
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  // 통화마다 한 줄. 저장된 환율로 계산한 통화는 그 줄에 표시한다.
                  for (final price in ratePrices) ...[
                    const SizedBox(height: 4),
                    Text(
                      _rateText(price),
                      style: textTheme.bodySmall?.copyWith(
                        color: price.rateStale
                            ? colorScheme.tertiary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (hasStaleRate) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.history,
                          size: 16,
                          color: colorScheme.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '최신 환율을 받지 못해 저장된 환율로 계산했어요',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.tertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final line in result.lines) ...[
          TranslationLineTile(line: line),
          Divider(height: 1, color: colorScheme.outlineVariant),
        ],
        const SizedBox(height: 12),
        if (omittedLineCount > 0)
          _Note(
            icon: Icons.info_outline,
            text: '글자가 많아 아래쪽 $omittedLineCount줄은 번역하지 않았어요. 나눠서 찍어 보세요.',
          ),
        if (hasUnconvertedPrice) const _Note(text: '환율을 받지 못한 가격은 원래 가격만 보여요.'),
        if (result.hasPronunciation)
          const _Note(text: '발음은 참고용이에요. 가게 이름 같은 고유명사는 다를 수 있어요.'),
        if (result.lines.isNotEmpty) const _Note(text: '줄을 길게 누르면 번역을 복사해요.'),
      ],
    );
  }

  static String _rateText(LinePrice price) {
    final rate = formatRate(price.krwRate ?? 0);
    final fetchedAt = price.rateFetchedAt;
    // 환율 화면과 같이 기기 시각으로 보여 준다.
    final time = fetchedAt == null
        ? ''
        : ' (${_timeFormat.format(fetchedAt.toLocal())} 기준)';
    final stale = price.rateStale ? ' · 저장된 환율' : '';

    return '1 ${price.currency} = $rate원$time$stale';
  }

  /// 1원 이상이면 소수 둘째 자리까지, 1원보다 작으면(예: VND 0.055) 유효 숫자 3자리까지 보여 준다.
  @visibleForTesting
  static String formatRate(num rate) {
    if (rate >= 1 || rate <= 0) {
      return _rateFormat.format(rate);
    }

    // 소수점 아래 첫 유효 숫자 위치 + 2자리. 0.055 → 4자리, 0.5 → 3자리.
    final decimals = ((-math.log(rate) / math.ln10).floor() + 3).clamp(3, 8);
    final format = _smallRateFormats.putIfAbsent(
      decimals,
      () => NumberFormat('#,##0.${'#' * decimals}'),
    );

    return format.format(rate);
  }
}

/// 한 줄: 위에 번역과 원화 가격, 아래에 원문·한글 발음과 원래 가격.
///
/// 길게 누르면 번역을 복사한다. 낭독기는 한 줄을 번역, 원화, 원문, 발음,
/// 원래 가격 순서의 한 문장으로 읽는다.
class TranslationLineTile extends StatelessWidget {
  const TranslationLineTile({super.key, required this.line});

  final TranslatedLine line;

  static final NumberFormat _krwFormat = NumberFormat('#,##0');

  /// 오른쪽 가격 칸이 가질 수 있는 최대 폭 비율. 넘으면 가격이 줄을 바꾼다.
  static const double _priceMaxWidthFactor = 0.45;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final price = line.price;
    final krwAmount = price?.krwAmount;
    final krwText = krwAmount == null
        ? null
        : '약 ${_krwFormat.format(krwAmount)}원';
    final pronunciation = line.pronunciation;
    // 원문과 번역 언어가 같아 번역이 원문 그대로면 원문을 다시 보여 주지 않는다.
    final showOriginal = line.original != line.translated;
    final hasDetailRow = showOriginal || pronunciation != null || price != null;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: _semanticsLabel(krwText),
      onLongPressHint: '번역 복사',
      onLongPress: () => _copyTranslation(context),
      child: InkWell(
        onLongPress: () => _copyTranslation(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final priceMaxWidth = constraints.maxWidth * _priceMaxWidthFactor;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PairRow(
                    priceMaxWidth: priceMaxWidth,
                    main: Text(
                      line.translated,
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    trailing: krwText == null
                        ? null
                        : Text(
                            krwText,
                            textAlign: TextAlign.end,
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                  ),
                  if (hasDetailRow) ...[
                    const SizedBox(height: 4),
                    _PairRow(
                      priceMaxWidth: priceMaxWidth,
                      main: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showOriginal)
                            Text(
                              line.original,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (pronunciation != null)
                            Text(
                              pronunciation,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                        ],
                      ),
                      trailing: price == null
                          ? null
                          : Text(
                              price.text,
                              textAlign: TextAlign.end,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _semanticsLabel(String? krwText) {
    final price = line.price;

    return [
      line.translated,
      ?krwText,
      if (line.original != line.translated) '원문 ${line.original}',
      if (line.pronunciation != null) '발음 ${line.pronunciation}',
      if (price != null) '원래 가격 ${price.text}',
    ].join(', ');
  }

  void _copyTranslation(BuildContext context) {
    Clipboard.setData(ClipboardData(text: line.translated));
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('번역을 복사했어요')));
  }
}

/// 왼쪽 내용은 남은 폭을 모두 쓰고, 오른쪽 가격은 [priceMaxWidth]까지만 차지한다.
/// 가격이 길면 오른쪽 칸 안에서 줄을 바꿔, 번역과 겹치거나 잘리지 않게 한다.
class _PairRow extends StatelessWidget {
  const _PairRow({
    required this.main,
    required this.trailing,
    required this.priceMaxWidth,
  });

  final Widget main;
  final Widget? trailing;
  final double priceMaxWidth;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: priceMaxWidth),
            child: trailing,
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.icon});

  final String text;

  /// 다음 행동이 필요한 안내에만 붙인다.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);
    final icon = this.icon;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
