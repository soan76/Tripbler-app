import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/duty_free/duty_free_item.dart';
import '../../models/duty_free/duty_free_rules.dart';
import '../../providers/duty_free/duty_free_provider.dart';
import '../../utils/duty_free/duty_free_format.dart';
import '../schedule/schedule_sheet_parts.dart';
import 'duty_free_dialogs.dart';
import 'duty_free_item_fields.dart';
import 'duty_free_list_parts.dart';

/// 산 물건 추가·수정 카드(docs/mockups/duty-free.md 3절). 일정 입력 카드와 같은 판을 쓴다.
///
/// 저장·삭제를 마치면 화면에 보일 알림 글자를 돌려주며 닫는다.
class DutyFreeItemSheet extends ConsumerStatefulWidget {
  const DutyFreeItemSheet({super.key, this.initial, this.rules});

  /// 수정할 물건. null이면 추가.
  final DutyFreeItem? initial;

  /// 달러 환산에 쓰는 규칙. null이면 환산하지 못한다고 보인다.
  final DutyFreeRules? rules;

  static Future<String?> open(
    BuildContext context, {
    DutyFreeItem? initial,
    DutyFreeRules? rules,
  }) {
    return ScheduleSheetFrame.show<String>(
      context,
      (_) => DutyFreeItemSheet(initial: initial, rules: rules),
    );
  }

  @override
  ConsumerState<DutyFreeItemSheet> createState() => _DutyFreeItemSheetState();
}

class _DutyFreeItemSheetState extends ConsumerState<DutyFreeItemSheet> {
  late DutyFreeCategory _category;
  late String _currency;
  late PurchasePlace _place;
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _volume;
  late final TextEditingController _amount;
  bool _nameError = false;
  bool _quantityError = false;
  bool _amountError = false;
  bool _volumeError = false;
  bool _saving = false;
  String? _saveError;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _category = item?.category ?? DutyFreeCategory.general;
    _currency = item?.currency ?? 'JPY';
    _place = item?.place ?? PurchasePlace.local;
    _name = TextEditingController(text: item?.name ?? '');
    _quantity = TextEditingController(text: '${item?.quantity ?? 1}');
    _volume = TextEditingController(
      text: item != null && item.category.hasVolume
          ? DutyFreeFormat.editable(item.volume)
          : '',
    );
    // 칸에는 반올림하지 않은 값을 채워, 고치지 않고 저장하면 값이 그대로 남게 한다.
    _amount = TextEditingController(
      text: item == null ? '' : DutyFreeFormat.editable(item.amount),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _volume.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// 수량 칸 값. 1 이상의 정수가 아니면 null.
  static int? _quantityValue(String text) {
    final value = DutyFreeFormat.parseNumber(text);
    if (value == null || value < 1 || value != value.truncateToDouble()) {
      return null;
    }
    return value.toInt();
  }

  /// 금액·용량 칸 값. 비었거나 잘못된 값이면 0.
  static double _number(String text) => DutyFreeFormat.parseNumber(text) ?? 0;

  void _pickCategory(DutyFreeCategory category) {
    setState(() {
      _category = category;
      _volumeError = false;
      if (category.hasVolume && _number(_volume.text) <= 0) {
        _volume.text = category == DutyFreeCategory.liquor ? '0.7' : '50';
      }
    });
  }

  DutyFreeItem _build() {
    final notifier = ref.read(dutyFreeProvider.notifier);
    final quantity = _quantityValue(_quantity.text)!.clamp(1, 999);
    final values = (
      category: _category,
      name: _name.text.trim(),
      quantity: quantity,
      volume: _category.hasVolume ? _number(_volume.text).clamp(0, 99999) : 0.0,
      amount: _number(_amount.text).clamp(0, 1e12).toDouble(),
    );
    final initial = widget.initial;
    if (initial != null) {
      return initial.copyWith(
        category: values.category,
        name: values.name,
        quantity: values.quantity,
        volume: values.volume.toDouble(),
        amount: values.amount,
        currency: _currency,
        place: _place,
        needsCheck: false,
      );
    }
    return DutyFreeItem(
      id: notifier.newId(),
      category: values.category,
      name: values.name,
      quantity: values.quantity,
      volume: values.volume.toDouble(),
      amount: values.amount,
      currency: _currency,
      place: _place,
      purchasedAt: notifier.now(),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    // 금액과 주류·향수 용량은 0보다 커야 한다(0이면 한도 계산에서 조용히 빠진다).
    // 수량은 1 이상의 정수여야 한다(다른 값으로 바꿔 저장하지 않는다).
    final nameError = _name.text.trim().isEmpty;
    final quantityError = _quantityValue(_quantity.text) == null;
    final amountError = _number(_amount.text) <= 0;
    final volumeError = _category.hasVolume && _number(_volume.text) <= 0;
    if (nameError || quantityError || amountError || volumeError) {
      setState(() {
        _nameError = nameError;
        _quantityError = quantityError;
        _amountError = amountError;
        _volumeError = volumeError;
      });
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final notifier = ref.read(dutyFreeProvider.notifier);
    try {
      final item = _build();
      await (_editing ? notifier.update(item) : notifier.add(item));
      if (mounted) Navigator.of(context).pop(_editing ? '수정했어요' : '추가했어요');
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = '저장하지 못했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final item = widget.initial;
    if (item == null || _saving) return;
    final ok = await confirmDutyFreeDelete(context, item, widget.rules);
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(dutyFreeProvider.notifier).remove(item.id);
      if (mounted) Navigator.of(context).pop('삭제했어요');
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = '삭제하지 못했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  String _usdHint() {
    final rules = widget.rules;
    final usd = rules?.toUsd(_number(_amount.text), _currency);
    if (usd == null) return '환율이 없어 달러로 바꿀 수 없어요';
    return '≈ ${DutyFreeFormat.usd(usd)}${rules!.isExample ? ' (예시 환율)' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final error = _saveError;

    return ScheduleSheetFrame(
      title: _editing ? '물건 수정' : '물건 추가',
      leading: _editing
          ? IconButton(
              tooltip: '뒤로 가기',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            )
          : null,
      banner: error == null
          ? null
          : Container(
              color: colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
      rows: [
        ScheduleSheetRow(
          icon: Icons.category_outlined,
          label: '분류',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<DutyFreeCategory>(
                key: const ValueKey('duty-free-category'),
                showSelectedIcon: false,
                style: dutyFreeSegmentStyle(context),
                segments: [
                  for (final c in DutyFreeCategory.values)
                    ButtonSegment(
                      value: c,
                      label: Text(c.label, textAlign: TextAlign.center),
                    ),
                ],
                selected: {_category},
                onSelectionChanged: (s) => _pickCategory(s.first),
              ),
              if (_category != DutyFreeCategory.general) ...[
                const SizedBox(height: 4),
                Text('일반 물품 한도와 따로, 수량·용량 기준으로 계산해요.', style: hint),
              ],
            ],
          ),
        ),
        ScheduleSheetRow(
          icon: Icons.shopping_bag_outlined,
          label: '상품명',
          child: ScheduleFieldLabel(
            label: '상품명, 필수',
            child: TextField(
              key: const ValueKey('duty-free-name'),
              controller: _name,
              maxLength: DutyFreeItem.maxNameLength,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: '예: 가죽 가방',
                counterText: '',
                errorText: _nameError ? '상품명을 입력해 주세요' : null,
              ),
              onChanged: (_) {
                if (_nameError) setState(() => _nameError = false);
              },
            ),
          ),
        ),
        ScheduleSheetRow(
          icon: Icons.numbers,
          label: _category.hasVolume
              ? '${_category.quantityLabel} · 용량'
              : _category.quantityLabel,
          child: DutyFreeQuantityFields(
            category: _category,
            quantity: _quantity,
            volume: _volume,
            quantityError: _quantityError,
            volumeError: _volumeError,
            onQuantityChanged: () {
              if (_quantityError) setState(() => _quantityError = false);
            },
            onVolumeChanged: () {
              if (_volumeError) setState(() => _volumeError = false);
            },
          ),
        ),
        ScheduleSheetRow(
          icon: Icons.payments_outlined,
          label: '금액(합계)',
          child: DutyFreeAmountField(
            amount: _amount,
            amountError: _amountError,
            currency: _currency,
            usdHint: _usdHint(),
            onAmountChanged: () => setState(() => _amountError = false),
            onCurrencyChanged: (c) => setState(() => _currency = c),
          ),
        ),
        ScheduleSheetRow(
          icon: Icons.storefront_outlined,
          label: '구매처',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<PurchasePlace>(
                key: const ValueKey('duty-free-place'),
                showSelectedIcon: false,
                style: dutyFreeSegmentStyle(context),
                segments: [
                  for (final p in PurchasePlace.values)
                    ButtonSegment(
                      value: p,
                      label: Text(p.label, textAlign: TextAlign.center),
                    ),
                ],
                selected: {_place},
                onSelectionChanged: (s) => setState(() => _place = s.first),
              ),
              const SizedBox(height: 4),
              Text('출국 면세점·기내에서 산 것도 한도에 들어가요(예시 기준).', style: hint),
            ],
          ),
        ),
      ],
      footer: _editing
          ? [
              OutlinedButton(
                key: const ValueKey('duty-free-delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(color: colorScheme.error),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _saving ? null : _delete,
                child: const Text('삭제'),
              ),
              FilledButton(
                key: const ValueKey('duty-free-save'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _saving ? null : _save,
                child: const Text('수정'),
              ),
            ]
          : [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                key: const ValueKey('duty-free-save'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _saving ? null : _save,
                child: const Text('저장'),
              ),
            ],
    );
  }
}
