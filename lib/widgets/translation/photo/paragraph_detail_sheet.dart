import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.cornerRadius),
      ),
    ),
    builder: (_) => ParagraphDetailSheet(paragraph: paragraph),
  );
}

/// 문단 하나의 원문(보정된 원문)·번역·한글 발음·가격과, 불확실·대체 번역이면 그 이유를 보여 준다.
///
/// 번역을 가장 크게 두고, 이유는 번역 바로 아래에 상자 표시와 같은 아이콘으로 붙인다.
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
    final fallback = paragraph.source == PhotoTranslationSource.ocrText;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Section(
                label: '번역',
                child: Text(
                  paragraph.translated,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              // 상자의 표시 아이콘(⚠ 불확실, ⓘ 대체)과 같은 아이콘으로 이유를 붙인다.
              if (paragraph.uncertain)
                const _ReasonLine(
                  icon: Icons.warning_amber_rounded,
                  text: uncertainReason,
                ),
              if (fallback)
                const _ReasonLine(
                  icon: Icons.info_outline,
                  text: fallbackReason,
                ),
              _Section(
                label: '원문',
                child: Text(
                  paragraph.original,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (pronunciation != null)
                _Section(
                  label: '한글 발음',
                  child: Text(pronunciation, style: theme.textTheme.bodyLarge),
                ),
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
  // 원화 금액이 이 시트에서 가장 먼저 찾는 값이라 강조색으로 둔다.
  Widget _priceLine(ThemeData theme, PhotoPrice price) {
    final colorScheme = theme.colorScheme;
    final krw = price.krwAmount;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(price.text, style: theme.textTheme.bodyLarge),
          if (!price.confirmed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(unconfirmedPriceLabel, style: muted),
              ),
            )
          else if (krw != null) ...[
            Text(
              '≈ ${_krwFormat.format(krw)}원',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
              ),
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
      padding: const EdgeInsets.only(top: 16),
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
  const _ReasonLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
