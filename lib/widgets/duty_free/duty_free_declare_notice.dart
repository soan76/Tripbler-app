import 'package:flutter/material.dart';

import '../../domain/duty_free/duty_free_calculator.dart';
import '../../models/duty_free/duty_free_rules.dart';
import '../../utils/duty_free/duty_free_format.dart';
import '../schedule/schedule_sheet_parts.dart';

/// 신고 안내(초과일 때만)와 펼쳐 보는 예상 세금(예시).
class DeclareNotice extends StatefulWidget {
  const DeclareNotice({
    super.key,
    required this.summary,
    required this.rules,
    required this.onOpenCustoms,
  });

  final DutyFreeSummary summary;
  final DutyFreeRules rules;
  final VoidCallback onOpenCustoms;

  @override
  State<DeclareNotice> createState() => _DeclareNoticeState();
}

class _DeclareNoticeState extends State<DeclareNotice> {
  bool _showTax = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fg = colorScheme.onErrorContainer;
    final summary = widget.summary;
    final rules = widget.rules;
    final tax = summary.tax;
    final krw = DutyFreeFormat.krw;
    final body = theme.textTheme.bodyMedium?.copyWith(color: fg);
    final small = theme.textTheme.bodySmall?.copyWith(color: fg);

    final total = theme.textTheme.titleSmall?.copyWith(
      color: fg,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget line(String a, String b, {bool bold = false}) => Padding(
      padding: EdgeInsets.only(top: bold ? 8 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(a, style: bold ? total : small)),
          const SizedBox(width: 8),
          Text(
            b,
            style: bold
                ? total
                : small?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
          ),
        ],
      ),
    );

    return Semantics(
      liveRegion: true,
      child: Container(
        color: colorScheme.errorContainer,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '입국할 때 세관 신고가 필요할 수 있어요',
              style: theme.textTheme.titleMedium?.copyWith(color: fg),
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.overReasons.join(' · ')}. 정확한 판단은 세관에서 해요.',
              style: body,
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  key: const ValueKey('duty-free-tax-toggle'),
                  style: TextButton.styleFrom(foregroundColor: fg),
                  onPressed: () => setState(() => _showTax = !_showTax),
                  child: Semantics(
                    expanded: _showTax,
                    child: Text(_showTax ? '예상 세금 접기' : '예상 세금 보기(예시)'),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: fg),
                  onPressed: widget.onOpenCustoms,
                  child: const Text('관세청 여행자 안내'),
                ),
              ],
            ),
            // 일정 카드의 펼치기와 같은 움직임으로 근거를 버튼 바로 아래에 펼친다.
            ScheduleFold(
              open: _showTax,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(color: fg.withValues(alpha: 0.2), height: 1),
                  if (tax != null) ...[
                    line(
                      '초과 금액',
                      '${DutyFreeFormat.usd(tax.overUsd)} ≈ ${krw(tax.overKrw)}',
                    ),
                    line(
                      '예시 세율 ${(rules.taxRate * 100).round()}%',
                      krw(tax.taxKrw),
                    ),
                    line(
                      '자진신고 감면 ${(rules.selfReportDiscount * 100).round()}%(예시, 한도 있음)',
                      '−${krw(tax.discountKrw)}',
                    ),
                    line('예상 세금', krw(tax.totalKrw), bold: true),
                  ],
                  if (summary.separateOver)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '별도 기준 초과분은 분류별 세율이 달라 여기서 계산하지 않아요',
                        style: small,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text(
                      '세율·환율은 예시예요. 실제 세금은 품목과 세관 환율로 정해져요.',
                      style: small,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
