import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../domain/duty_free/receipt_parser.dart';
import '../models/duty_free/duty_free_item.dart';
import '../providers/duty_free/duty_free_provider.dart';
import '../utils/duty_free/duty_free_format.dart';
import '../widgets/duty_free/duty_free_list_parts.dart';
import '../widgets/duty_free/receipt_line_row.dart';

/// 영수증 넣는 방식. 둘 중 하나만 골라 합계와 항목이 이중으로 더해지지 않게 한다.
enum ReceiptAddMode { items, total }

/// 영수증 검토 화면(docs/mockups/duty-free.md 4절): 가게·날짜·합계, 넣는 방식, 줄 고르기·금액 고치기,
/// 중복 경고. 목록에 넣으면 알림 글자를 돌려주며 닫는다.
class ReceiptReviewScreen extends ConsumerStatefulWidget {
  const ReceiptReviewScreen({super.key, required this.receipt});

  final ParsedReceipt receipt;

  static const String unreadableMessage =
      '영수증에서 금액을 읽지 못했어요. 다시 찍거나 직접 입력해 주세요.';
  static const String currencyNeededMessage = '통화를 읽지 못했어요. 영수증 통화를 골라 주세요';

  /// `다시 찍기`로 닫힐 때 돌려주는 값. 받는 쪽은 알림 대신 촬영을 다시 연다.
  static const String retakeResult = 'retake';

  /// [imagePath] 사진을 기기에서 읽고, 읽은 게 있으면 검토 화면을 연다. 화면에 보일 알림 글자를 돌려준다.
  static Future<String?> scanAndOpen(
    BuildContext context,
    String imagePath,
  ) async {
    final container = ProviderScope.containerOf(context);
    final navigator = Navigator.of(context);
    // 읽는 중 안내는 앱 맨 위 Navigator에 띄우고, 띄운 그 route만 직접 걷어 낸다. 가까운
    // Navigator의 pop()은 중첩 Navigator에서 안내 대신 다른 화면을 닫을 수 있다.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final loading = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: DialogTheme.of(context).barrierColor ?? Colors.black54,
      themes: InheritedTheme.capture(from: context, to: rootNavigator.context),
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('영수증을 읽는 중이에요')),
            ],
          ),
        ),
      ),
    );
    rootNavigator.push(loading);
    ParsedReceipt? receipt;
    try {
      receipt = await container
          .read(receiptScanServiceProvider)
          .scan(imagePath);
    } catch (_) {
      receipt = null;
    } finally {
      // 글자를 다 읽었으면 사진은 더 쓰지 않는다. 지우지 못해도 흐름은 잇는다.
      unawaited(
        container
            .read(receiptPhotoDeleterProvider)(imagePath)
            .catchError((_) {}),
      );
    }
    if (loading.isActive) rootNavigator.removeRoute(loading);
    if (receipt == null || (receipt.lines.isEmpty && receipt.total == null)) {
      return unreadableMessage;
    }
    return navigator.push<String>(
      MaterialPageRoute(builder: (_) => ReceiptReviewScreen(receipt: receipt!)),
    );
  }

  @override
  ConsumerState<ReceiptReviewScreen> createState() =>
      _ReceiptReviewScreenState();
}

class _ReviewLine {
  _ReviewLine(this.line)
    : selected = !line.unsure,
      amount = TextEditingController(
        text: DutyFreeFormat.editable(line.amount),
      );

  final ReceiptLine line;
  bool selected;
  final TextEditingController amount;

  /// 고친 금액. `1,5`·글자 섞임처럼 읽을 수 없으면 null(다른 값으로 바꾸지 않는다).
  double? get value => DutyFreeFormat.parseNumber(amount.text);

  /// 골랐는데 금액이 0 이하이거나 읽을 수 없는 줄. 하나라도 있으면 추가를 막는다.
  bool get invalid => selected && (value ?? 0) <= 0;
}

class _ReceiptReviewScreenState extends ConsumerState<ReceiptReviewScreen> {
  ReceiptAddMode _mode = ReceiptAddMode.items;

  /// 읽은 통화. 읽지 못했거나 지원하지 않는 통화면 사용자가 고를 때까지 null(추가를 막는다).
  String? _currency;
  late final List<_ReviewLine> _lines;
  bool _saving = false;

  ParsedReceipt get _receipt => widget.receipt;

  @override
  void initState() {
    super.initState();
    final read = _receipt.currency;
    _currency = DutyFreeItem.currencies.contains(read) ? read : null;
    _lines = [for (final l in _receipt.lines) _ReviewLine(l)];
    if (_lines.isEmpty) _mode = ReceiptAddMode.total;
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.amount.dispose();
    }
    super.dispose();
  }

  String get _storeName => _receipt.store.isEmpty ? '영수증' : _receipt.store;

  int get _count => _mode == ReceiptAddMode.total
      ? 1
      : _lines.where((l) => l.selected && !l.invalid).length;

  /// 합계 한 줄로 넣는데 합계가 0 이하라 넣을 수 없는지.
  bool get _totalInvalid =>
      _mode == ReceiptAddMode.total && _receipt.totalOrSum <= 0;

  /// 넣을 금액에 오류가 있는지: 항목별이면 고른 줄, 합계면 합계.
  bool get _hasInvalid =>
      _totalInvalid ||
      (_mode == ReceiptAddMode.items && _lines.any((l) => l.invalid));

  PurchasePlace get _place {
    final lower = _receipt.store.toLowerCase();
    return lower.contains('duty free') || lower.contains('면세점')
        ? PurchasePlace.departureDutyFree
        : PurchasePlace.local;
  }

  Future<void> _add() async {
    final currency = _currency;
    if (_saving || _count == 0 || _hasInvalid || currency == null) return;
    final notifier = ref.read(dutyFreeProvider.notifier);
    final date = _receipt.date ?? notifier.now();
    final place = _place;
    DutyFreeItem item({
      required String name,
      required double amount,
      DutyFreeCategory category = DutyFreeCategory.general,
      double volume = 0,
      bool unsure = false,
    }) => DutyFreeItem(
      id: notifier.newId(),
      category: category,
      name: name.length > DutyFreeItem.maxNameLength
          ? name.substring(0, DutyFreeItem.maxNameLength)
          : name,
      quantity: 1,
      volume: volume,
      amount: amount,
      currency: currency,
      place: place,
      purchasedAt: date,
      needsCheck: unsure,
    );
    final items = _mode == ReceiptAddMode.total
        ? [item(name: '$_storeName 합계', amount: _receipt.totalOrSum)]
        : [
            for (final l in _lines)
              if (l.selected)
                item(
                  name: l.line.name,
                  amount: l.value!,
                  category: l.line.category,
                  volume: l.line.volume,
                  unsure: l.line.unsure,
                ),
          ];
    setState(() => _saving = true);
    try {
      await notifier.addReceipt(items, _receipt.keyFor(currency));
      if (mounted) Navigator.of(context).pop('영수증에서 ${items.length}개를 추가했어요');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('저장하지 못했어요. 다시 시도해 주세요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sub = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final currency = _currency;
    final dup =
        currency != null &&
        ref.watch(
          dutyFreeProvider.select(
            (s) => s.trip.receiptKeys.contains(_receipt.keyFor(currency)),
          ),
        );
    final date = _receipt.date;
    final number = DutyFreeFormat.number(_receipt.totalOrSum);
    final total = currency == null
        ? number
        : '${DutyFreeFormat.symbol(currency)}$number $currency';
    final head = [
      if (date != null) DutyFreeFormat.day(date),
      '합계 $total${_receipt.total == null ? '(줄 합)' : ''}',
      '읽은 줄 ${_lines.length}개',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: const Text('영수증 확인')),
      body: ListView(
        children: [
          if (dup)
            Semantics(
              liveRegion: true,
              child: Container(
                key: const ValueKey('receipt-duplicate'),
                color: colorScheme.warningContainer,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '이미 추가한 영수증일 수 있어요',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onWarningContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_storeName · ${date == null ? '' : '${DutyFreeFormat.day(date)} · '}합계 $total이(가) 목록에 있어요. 같은 영수증이면 추가하지 마세요.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onWarningContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_storeName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(head, style: sub),
                      Text('사진은 서버로 보내지 않고 기기에서 글자만 읽었어요', style: sub),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  key: const ValueKey('receipt-currency'),
                  value: _currency,
                  hint: const Text('통화'),
                  items: [
                    for (final c in DutyFreeItem.currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (c) {
                    if (c != null) setState(() => _currency = c);
                  },
                ),
              ],
            ),
          ),
          if (currency == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                ReceiptReviewScreen.currencyNeededMessage,
                key: const ValueKey('receipt-currency-needed'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.warning,
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ReceiptAddMode>(
                  key: const ValueKey('receipt-mode'),
                  showSelectedIcon: false,
                  style: dutyFreeSegmentStyle(context),
                  segments: [
                    ButtonSegment(
                      value: ReceiptAddMode.items,
                      enabled: _lines.isNotEmpty,
                      label: const Text('항목별로 넣기', textAlign: TextAlign.center),
                    ),
                    const ButtonSegment(
                      value: ReceiptAddMode.total,
                      label: Text('합계 한 줄로 넣기', textAlign: TextAlign.center),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                  _mode == ReceiptAddMode.items
                      ? '고른 항목만 따로 넣어요. 합계는 넣지 않아요.'
                      : '합계 하나만 일반 물품으로 넣어요. 주류·향수가 섞여 있으면 별도 기준 계산이 빠져요.',
                  style: sub,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_mode == ReceiptAddMode.items)
            for (final (i, l) in _lines.indexed)
              ReceiptLineRow(
                index: i,
                line: l.line,
                selected: l.selected,
                invalid: l.invalid,
                amount: l.amount,
                currency: currency,
                onSelected: (v) => setState(() => l.selected = v),
                onAmountChanged: () => setState(() {}),
              )
          else
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text('$_storeName 합계'),
              subtitle: _totalInvalid
                  ? Text(
                      _lines.isEmpty
                          ? '합계가 0이라 넣을 수 없어요. 직접 입력해 주세요.'
                          : '합계가 0이라 넣을 수 없어요. 항목별로 넣어 주세요.',
                      key: const ValueKey('receipt-total-invalid'),
                      style: TextStyle(color: colorScheme.error),
                    )
                  : const Text('일반'),
              trailing: Text(
                total,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(ReceiptReviewScreen.retakeResult),
                    child: const Text('다시 찍기'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('receipt-add'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed:
                        _saving ||
                            _count == 0 ||
                            _hasInvalid ||
                            currency == null
                        ? null
                        : _add,
                    child: Text('${dup ? '그래도 추가' : '목록에 추가'} ($_count)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
