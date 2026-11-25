import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/translation/photo_translation_result.dart';

/// 문단 상세를 아래 시트로 띄운다.
Future<void> showParagraphDetailSheet(
  BuildContext context,
  TranslatedParagraph paragraph,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ParagraphDetailSheet(paragraph: paragraph),
  );
}

/// 문단 하나의 원문(보정된 원문)·번역·한글 발음·가격과, 불확실·대체 번역이면 그 이유를 보여 준다.
class ParagraphDetailSheet extends StatelessWidget {
  const ParagraphDetailSheet({super.key, required this.paragraph});

  final TranslatedParagraph paragraph;

  static const String uncertainReason = '일부 글자를 확실히 읽지 못해 번역이 정확하지 않을 수 있어요.';
  static const String fallbackReason = '사진을 쓰지 못해 인식된 글자만으로 번역했어요.';
  static const String unconfirmedPriceLabel = '확인되지 않은 가격';
  static const String staleRateLabel = '지난 환율 기준';

  static final NumberFormat _krwFormat = NumberFormat('#,##0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pronunciation = paragraph.pronunciation;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (paragraph.uncertain) _ReasonLine(text: uncertainReason),
              if (paragraph.source == PhotoTranslationSource.ocrText)
                _ReasonLine(text: fallbackReason),
              _Section(
                label: '번역',
                child: Text(
                  paragraph.translated,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _Section(label: '원문', child: Text(paragraph.original)),
              if (pronunciation != null)
                _Section(label: '한글 발음', child: Text(pronunciation)),
              if (paragraph.prices.isNotEmpty)
                _Section(
                  label: '가격',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final price in paragraph.prices)
                        _priceLine(theme, price),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 확정하지 못한 가격은 원문 가격만 보이고 표시를 붙인다. 확정했지만 환율이 없으면 가격만 보인다.
  Widget _priceLine(ThemeData theme, PhotoPrice price) {
    final krw = price.krwAmount;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(price.text),
          if (!price.confirmed)
            Text(unconfirmedPriceLabel, style: muted)
          else if (krw != null) ...[
            Text(
              '≈ ${_krwFormat.format(krw)}원',
              style: theme.textTheme.titleSmall,
            ),
            if (price.rateStale) Text(staleRateLabel, style: muted),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _ReasonLine extends StatelessWidget {
  const _ReasonLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
