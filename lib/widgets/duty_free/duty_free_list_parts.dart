import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/duty_free/duty_free_item.dart';
import '../../models/duty_free/duty_free_rules.dart';
import '../../utils/duty_free/duty_free_format.dart';

/// 면세 화면의 줄들: 기준 줄, 안내 띠, 산 물건 한 줄(docs/mockups/duty-free.md 2절 1·6번).

/// 면세 화면의 SegmentedButton(분류·구매처·나이·영수증 넣는 방식) 모양.
///
/// 앱 규칙대로 모서리 4를 쓰고(Material 3 기본은 알약 모양), 누르는 높이를 48로 맞춘다.
/// 폭 320 화면에서 칸이 좁아도 글자가 들어가도록 좌우 여백을 줄이고, 넘치면 두 줄로 감싼다.
ButtonStyle dutyFreeSegmentStyle(BuildContext context) {
  final theme = Theme.of(context);
  return SegmentedButton.styleFrom(
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    textStyle: theme.textTheme.labelLarge,
    selectedBackgroundColor: theme.colorScheme.primaryContainer,
    selectedForegroundColor: theme.colorScheme.onPrimaryContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppTheme.cornerRadius)),
    ),
  );
}

/// 기준 줄: "한국 입국 기준 · 만 19세 이상"과 변경.
class DutyFreeBasisRow extends StatelessWidget {
  const DutyFreeBasisRow({
    super.key,
    required this.country,
    required this.adult,
    required this.onChange,
  });

  final String country;
  final bool adult;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.surfaceContainerHighest),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$country 입국 기준',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  TextSpan(text: ' · ${adult ? '만 19세 이상' : '만 19세 미만'}'),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('duty-free-basis-change'),
            onPressed: onChange,
            child: const Text('변경'),
          ),
        ],
      ),
    );
  }
}

/// 경고(환율 오래됨)·오류(계산 불가) 띠.
class DutyFreeNotice extends StatelessWidget {
  const DutyFreeNotice({
    super.key,
    required this.text,
    this.error = false,
    this.action,
    this.onAction,
  });

  final String text;
  final bool error;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bg = error
        ? colorScheme.errorContainer
        : colorScheme.warningContainer;
    final fg = error
        ? colorScheme.onErrorContainer
        : colorScheme.onWarningContainer;
    final action = this.action;
    // 글자를 키워도 버튼이 글자를 밀어내지 않게, 버튼은 글자 아래 오른쪽에 둔다.
    return Semantics(
      liveRegion: true,
      child: Container(
        color: bg,
        padding: EdgeInsets.fromLTRB(20, 12, action == null ? 20 : 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(right: action == null ? 0 : 12),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ),
            if (action != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: onAction,
                  child: Text(action),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 산 물건 한 줄: 이름·분류·확인 필요, 구매처·날짜·수량, 현지 금액과 달러 환산.
class DutyFreeItemRow extends StatelessWidget {
  const DutyFreeItemRow({
    super.key,
    required this.item,
    required this.rules,
    required this.onTap,
  });

  final DutyFreeItem item;
  final DutyFreeRules? rules;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sub = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final usd = rules?.toUsd(item.amount, item.currency);

    Widget tag(String text, {bool warn = false}) => Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: warn
            ? colorScheme.warningContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: warn
              ? colorScheme.onWarningContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.surfaceContainerHighest),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(item.name, style: theme.textTheme.titleMedium),
                      tag(item.category.label),
                      if (item.needsCheck) tag('확인 필요', warn: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.place.label} · ${DutyFreeFormat.day(item.purchasedAt)}${DutyFreeFormat.quantity(item)}',
                    style: sub,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 큰 금액·큰 글자에서도 상품명 자리를 남기도록 금액 칸은 화면 폭의 45%까지만 쓰고 줄바꿈한다.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.45,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DutyFreeFormat.money(item.amount, item.currency),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    usd == null ? '환산 불가' : '≈ ${DutyFreeFormat.usd(usd)}',
                    textAlign: TextAlign.end,
                    style: sub,
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
