import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/duty_free/duty_free_calculator.dart';
import '../../models/duty_free/duty_free_rules.dart';
import '../../utils/duty_free/duty_free_format.dart';

/// 면세 화면 요약 칸들(docs/mockups/duty-free.md 2절 2~5번).
class DutyFreeSection extends StatelessWidget {
  const DutyFreeSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.surfaceContainerHighest),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: label),
                ),
              ),
              if (trailing != null) Text(trailing!, style: label),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// 일반 물품 한도: 남은 한도 또는 초과 금액, 현지 통화 환산, 진행 막대.
class GeneralLimitSection extends StatelessWidget {
  const GeneralLimitSection({
    super.key,
    required this.summary,
    required this.rules,
    required this.localCurrency,
  });

  final GeneralLimitSummary summary;
  final DutyFreeRules rules;

  /// 남은 한도를 바꿔 보일 통화(가장 많이 산 현지 통화).
  final String localCurrency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final over = summary.over;
    final barColor = over
        ? colorScheme.error
        : summary.near
        ? colorScheme.warning
        : colorScheme.primary;
    final sub = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    final local = rules.fromUsd(summary.remainingUsd, localCurrency);
    final subText = over
        ? '초과한 금액에 세금이 붙을 수 있어요'
        : [
            if (local != null && localCurrency != 'USD')
              '현지 통화로 약 ${DutyFreeFormat.symbol(localCurrency)}${DutyFreeFormat.number(local.roundToDouble())}',
            if (summary.near) '한도의 90%를 넘었어요',
          ].join(' · ');

    return DutyFreeSection(
      title: '일반 물품 한도',
      trailing: rules.isExample ? '예시 기준' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            over
                ? '한도 초과 ${DutyFreeFormat.usd(summary.overUsd)}'
                : '남은 한도 ${DutyFreeFormat.usd(summary.remainingUsd)}',
            key: const ValueKey('duty-free-general-headline'),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: over ? colorScheme.error : colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (subText.isNotEmpty) Text(subText, style: sub),
          if (summary.unconvertible > 0)
            Text('환율이 없는 물건 ${summary.unconvertible}개는 빼고 계산했어요', style: sub),
          const SizedBox(height: 12),
          Semantics(
            label: '일반 물품 한도 사용률',
            value: '${(summary.ratio * 100).clamp(0, 100).round()}%',
            // 물건을 넣고 빼면 막대가 새 값까지 짧게 움직여 무엇이 바뀌었는지 보인다.
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: summary.ratio.clamp(0, 1).toDouble()),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: barColor,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 큰 금액·큰 글자에서는 줄을 바꿔 두 값이 겹치거나 넘치지 않게 한다.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              Text('지금까지 ${DutyFreeFormat.usd(summary.spentUsd)}', style: sub),
              Text('한도 ${DutyFreeFormat.usd(summary.limitUsd)}', style: sub),
            ],
          ),
        ],
      ),
    );
  }
}

/// 별도 기준(주류·담배·향수): 줄마다 없음 / 이내 / 초과.
class SeparateLimitsSection extends StatelessWidget {
  const SeparateLimitsSection({
    super.key,
    required this.summary,
    required this.rules,
    required this.adult,
  });

  final DutyFreeSummary summary;
  final DutyFreeRules rules;
  final bool adult;

  @override
  Widget build(BuildContext context) {
    const minor = '만 19세 미만은 면세 안 됨';
    final l = summary.liquor;
    final usd = DutyFreeFormat.usd;
    final n = DutyFreeFormat.number;
    return DutyFreeSection(
      title: '별도 기준 (일반 한도와 따로 계산)',
      child: Column(
        children: [
          _LimitRow(
            name: '주류',
            value: adult
                ? '${l.bottles}병 / ${rules.liquorBottles}병 · ${l.liters.toStringAsFixed(1)}L / ${n(rules.liquorLiters)}L · ${usd(l.usd)} / ${usd(rules.liquorUsd)}'
                      '${l.unconvertible > 0 ? '\n환율이 없는 주류 ${l.unconvertible}개는 금액에서 뺐어요' : ''}'
                : minor,
            status: l.status,
          ),
          _LimitRow(
            name: '담배',
            value: adult
                ? '${summary.tobacco.packs}갑 / ${rules.tobaccoPacks}갑'
                : minor,
            status: summary.tobacco.status,
          ),
          _LimitRow(
            name: '향수',
            value: '${n(summary.perfume.ml)}mL / ${n(rules.perfumeMl)}mL',
            status: summary.perfume.status,
          ),
        ],
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.name,
    required this.value,
    required this.status,
  });

  final String name;
  final String value;
  final SeparateLimitStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (String label, Color? bg, Color fg) = switch (status) {
      SeparateLimitStatus.none => ('없음', null, colorScheme.onSurfaceVariant),
      SeparateLimitStatus.within => (
        '이내',
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
      SeparateLimitStatus.over => (
        '초과',
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
    };
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(name, style: theme.textTheme.titleSmall),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style:
                    (status == SeparateLimitStatus.over
                            ? theme.textTheme.labelLarge
                            : theme.textTheme.labelMedium)
                        ?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 기준 정보 한 줄: 기준일, 환율 참고 안내, 확인 시각, 관세청 링크.
class DutyFreeRulesInfoRow extends StatelessWidget {
  const DutyFreeRulesInfoRow({
    super.key,
    required this.rules,
    required this.now,
    required this.onOpenCustoms,
  });

  final DutyFreeRules rules;
  final DateTime now;
  final VoidCallback onOpenCustoms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checked = now.difference(rules.checkedAt).inMinutes < 1
        ? '방금'
        : DutyFreeFormat.dateTime(rules.checkedAt);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.surfaceContainerHighest),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${rules.isExample ? '예시 기준 · ' : ''}기준일 ${DutyFreeFormat.isoDay(rules.basisDate)} · 환율은 참고용(세관 환율과 다를 수 있음) · 확인 $checked',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onOpenCustoms, child: const Text('관세청')),
        ],
      ),
    );
  }
}
