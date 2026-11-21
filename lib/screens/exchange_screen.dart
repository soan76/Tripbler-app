import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../crypto/providers/crypto_provider.dart';
import '../presentation/charts/chart_selection_provider.dart';
import '../presentation/exchange/display_currency.dart';
import '../presentation/exchange/exchange_display_provider.dart';
import '../presentation/exchange/exchange_display_view.dart';
import '../providers/exchange/exchange_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/charts/chart_pair_carousel.dart';
import '../widgets/exchange/chart_currency_picker_sheet.dart';
import '../widgets/exchange/currency_management_bottom_sheet.dart';
import '../widgets/exchange/currency_row.dart';
import '../widgets/exchange/currency_selection_sheet.dart';
import '../widgets/focus_history.dart';

/// 환율이 서버의 대체 출처에서 온 경우 화면에 띄우는 안내.
const String fallbackSourceNotice =
    '평소 환율 출처에 연결하지 못해 대체 출처 환율을 표시합니다. 값이 조금 다를 수 있습니다.';

// 환율 화면을 구성하는 StatefulWidget
class ExchangeScreen extends ConsumerStatefulWidget {
  const ExchangeScreen({super.key});

  @override
  ConsumerState<ExchangeScreen> createState() => _ExchangeScreenState();
}

// 환율 화면을 구성하는 StatefulWidget
class _ExchangeScreenState extends ConsumerState<ExchangeScreen> {
  // 코인 행 상태 문구의 시세·시각 형식. 행마다 새로 만들지 않고 재사용한다.
  static final _coinPriceFormat = NumberFormat('#,##0.########');
  static final _quoteTimeFormat = DateFormat('MM.dd HH:mm');

  // State 내부에서만 사용하는 초기화 여부 값이므로 private 필드로 변경.
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_hasInitialized) {
      _hasInitialized = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        // callback 실행 전에 화면이 dispose된 경우 context 사용을 막음.
        if (!mounted) {
          return;
        }

        ref.read(exchangeDisplayProvider.notifier).initialize();
        ref.read(chartSelectionProvider.notifier).initialize();
      });
    }
  }

  // 환율 화면의 상태를 관리하는 State 클래스
  @override
  Widget build(BuildContext context) {
    // 금액·환율은 exchangeDisplayViewProvider로 받으므로 여기서는 화면에 쓰는 필드만 읽는다.
    final (
      :visibleCurrencies,
      :isLoading,
      :errorMessage,
      :lastUpdated,
      :usesFallbackSource,
    ) = ref.watch(
      exchangeProvider.select(
        (state) => (
          visibleCurrencies: state.visibleCurrencies,
          isLoading: state.isLoading,
          errorMessage: state.errorMessage,
          lastUpdated: state.lastUpdated,
          usesFallbackSource: state.usesFallbackSource,
        ),
      ),
    );
    final exchange = ref.read(exchangeProvider.notifier);
    final view = ref.watch(exchangeDisplayViewProvider);
    final crypto = ref.watch(cryptoProvider);
    final conversionError = ref.watch(
      exchangeDisplayProvider.select((state) => state.conversionError),
    );
    final display = ref.read(exchangeDisplayProvider.notifier);
    final charts = ref.watch(chartSelectionProvider);
    final chartsNotifier = ref.read(chartSelectionProvider.notifier);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 입력 중인 통화를 맨 위, 자국 통화를 그 아래에 두고 나머지를 목록으로 보여 준다.
    // 모든 행은 같은 Column 안에서 ValueKey로 자리만 바뀌어 입력칸 상태와 초점을 유지한다.
    final rows = view.rows;
    final base = view.base;
    final active = rows
        .firstWhere((row) => row.isActive, orElse: () => view.rowOf(base))
        .currency;
    final others = [
      for (final row in rows)
        if (row.currency.id != active.id && row.currency.id != base.id)
          row.currency,
    ];

    Widget buildRow(DisplayCurrency row, CurrencyRowLayout layout) {
      final isBaseRow = row.id == base.id;
      final quote = row.isCrypto ? crypto.priceFor(row.code) : null;
      final priceError = row.isCrypto ? crypto.errorFor(row.code) : null;
      final time = quote?.fetchedAt.toLocal();
      final status = !row.isCrypto
          ? null
          : quote == null
          ? (priceError != null ? '조회 실패 · 아래로 당겨 재시도' : '현재가 조회 중')
          : '${crypto.isStale(row.code) ? '저장값 · ' : ''}${crypto.isLoading(row.code) ? '갱신 중 · ' : ''}1 ${row.code} = ${_coinPriceFormat.format(quote.price)} KRW · ${_quoteTimeFormat.format(time!)}';
      return CurrencyRow(
        key: ValueKey(row.id),
        currency: row,
        amount: view.rowOf(row).amount,
        status: status,
        onAmountTap: () => display.selectInput(row),
        onAmountChanged: (value) => display.changeAmount(row, value),
        onCurrencyTap: () {
          _leaveAmountField();
          if (row.isCrypto) {
            showCurrencyManagementBottomSheet(context: context);
            return;
          }
          showCurrencySelectionSheet(
            context: context,
            selectedCurrency: row.fiat!,
            onSelected: (currency) {
              if (isBaseRow) {
                exchange.changeBaseCurrency(currency);
              } else {
                exchange.replaceVisibleCurrency(
                  index: visibleCurrencies.indexWhere(
                    (item) => item.code == row.code,
                  ),
                  newCurrency: currency,
                );
              }
            },
          );
        },
        layout: layout,
      );
    }

    return Container(
      color: colorScheme.surface,
      child: RefreshIndicator(
        onRefresh: display.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(
                lastUpdated,
                emptyMessage: visibleCurrencies.isEmpty
                    ? (crypto.selectedCoins.isEmpty
                          ? '환산할 통화를 추가해 주세요'
                          : '암호화폐 현재가 기준 환산 수량')
                    : null,
                // 서버가 평소 출처 대신 대체 출처 값을 준 경우에만 알린다(사용자 결정).
                showFallbackNotice: usesFallbackSource,
              ),

              if (isLoading) const LinearProgressIndicator(),

              if (errorMessage != null)
                _buildErrorBox(
                  message: errorMessage,
                  onRetry: exchange.fetchRates,
                ),
              if (conversionError != null)
                _buildErrorBox(
                  message: conversionError,
                  onRetry: display.refreshConversion,
                ),
              buildRow(active, CurrencyRowLayout.input),
              if (active.id != base.id) buildRow(base, CurrencyRowLayout.home),
              if (others.isNotEmpty) _buildOthersLabel(),
              for (final row in others) buildRow(row, CurrencyRowLayout.list),

              // 통화 추가 / 편집 버튼을 표시하는 OutlinedButton 위젯
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () {
                    _leaveAmountField();
                    showCurrencyManagementBottomSheet(context: context);
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('통화 추가 / 편집'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    foregroundColor: colorScheme.onSurface,
                    side: BorderSide(color: colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),

              // 차트는 위쪽 환산 통화와 따로 고른 통화쌍을 보여 준다.
              const SizedBox(height: 32),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('환율 흐름', style: theme.textTheme.titleLarge),
              ),

              const SizedBox(height: 16),

              if (charts.loaded)
                ChartPairCarousel(
                  pairs: charts.pairs,
                  currencies: view.available,
                  onPick: (index, {required base, required swapped}) =>
                      _pickChartCurrency(index, base: base, swapped: swapped),
                  onAdd: charts.canAdd ? chartsNotifier.add : null,
                  onRemove: charts.canRemove ? chartsNotifier.remove : null,
                  swappedAfterReplace: chartsNotifier.swappedAfterReplace,
                  swappedAfterExchange: chartsNotifier.swappedAfterExchange,
                  decimalPlaces: ref.watch(
                    settingsProvider.select((s) => s.decimalPlaces),
                  ),
                )
              else
                const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // 창을 열기 전에 부른다. 터치로는 버튼이 초점을 가져가지 않아 전에 쓴 입력칸이 초점을 쥐고
  // 있다. 그대로 열면 창이 닫힐 때 입력칸으로 돌아가 키보드가 뜨고 화면이 올라간다. 값은 입력할
  // 때마다 반영되어 초점을 풀어도 잃지 않는다. 키보드로 연 경우 초점은 누른 버튼에 있어 닫으면
  // 그리로 돌아온다.
  void _leaveAmountField() {
    if (primaryFocusInTextField) releaseFocusHistory();
  }

  // 차트 카드 한쪽 통화를 검색 선택창에서 바꾼다. 위쪽 환산 통화에는 영향을 주지 않는다.
  // 쌍 계산·중복 판정·선택창이 열린 사이의 변경 확인은 Provider가 맡는다.
  Future<void> _pickChartCurrency(
    int index, {
    required bool base,
    required bool swapped,
  }) async {
    final charts = ref.read(chartSelectionProvider.notifier);
    final available = ref.read(exchangeDisplayViewProvider).available;
    final pair = ref.read(chartSelectionProvider).pairs[index];
    _leaveAmountField();
    final picked = await showChartCurrencyPicker(
      context: context,
      title: '차트 통화 선택',
      current: pair.currencyOf(base: base, currencies: available),
      optionsOf: (available) => pair.options(base: base, currencies: available),
      note: pair.isCrypto && !base ? '코인 차트는 KRW 기준만 지원합니다' : null,
    );
    if (picked == null || !mounted) return;
    final result = charts.replaceSide(
      index,
      expected: pair,
      base: base,
      swapped: swapped,
      currency: picked,
    );
    if (result == ChartPairChange.swappedPositions) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미 있던 차트와 위치를 바꿨습니다')));
    }
  }

  // 입력칸·자국 통화 아래 나머지 통화 목록의 제목
  Widget _buildOthersLabel() {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      // 위 칸과 16dp를 띄워 입력·결과 묶음과 보조 목록을 나눈다.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text('다른 통화', style: style),
          const SizedBox(width: 12),
          // 줄 순서가 바뀌는 이유를 알려 준다. 글자를 키우면 줄임표로 줄인다.
          Expanded(
            child: Text(
              '금액을 누르면 그 통화로 입력',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  // 환율 화면의 헤더 영역을 구성하는 위젯을 반환하는 메서드
  Widget _buildHeader(
    DateTime? lastUpdated, {
    String? emptyMessage,
    bool showFallbackNotice = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colorScheme.surface,
      // 조회 시각과 출처 안내는 같은 값에 대한 설명이라 화면 낭독기가 한 번에 읽게 묶는다.
      child: MergeSemantics(
        child: Column(
          children: [
            Text(
              lastUpdated == null && emptyMessage != null
                  ? emptyMessage
                  : _formatLastUpdatedText(lastUpdated?.toLocal()),
              textAlign: TextAlign.center,
              style: style,
            ),
            if (showFallbackNotice) ...[
              const SizedBox(height: 4),
              _buildFallbackSourceNotice(style),
            ],
          ],
        ),
      ),
    );
  }

  /// 환율이 대체 출처에서 온 경우의 안내. 평소 출처와 기준이 달라 값이 조금 다를 수 있다.
  ///
  /// 오류가 아니라 참고 정보라서 "마지막 업데이트"와 같은 보조 색을 쓰고, 정보 아이콘으로
  /// 조회 시각과 구분한다. 글자가 여러 줄로 늘어나도 아이콘은 첫 줄 옆에 둔다.
  Widget _buildFallbackSourceNotice(TextStyle? style) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          // bodySmall 한 줄 높이(16)에 맞추고, 시스템 글자 크기를 따라 함께 커진다.
          size: 16,
          applyTextScaling: true,
          color: style?.color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            fallbackSourceNotice,
            // 여러 줄이면 아이콘 옆에서 왼쪽부터 읽히게 한다. 한 줄이면 묶음째 가운데 놓인다.
            textAlign: TextAlign.start,
            style: style,
          ),
        ),
      ],
    );
  }

  // 마지막 업데이트 문자열 생성 로직을 분리해 build와 header 코드를 읽기 쉽게 함.
  String _formatLastUpdatedText(DateTime? lastUpdated) {
    if (lastUpdated == null) {
      return '환율 정보를 불러오는 중입니다';
    }

    final month = lastUpdated.month.toString().padLeft(2, '0');
    final day = lastUpdated.day.toString().padLeft(2, '0');
    final hour = lastUpdated.hour.toString().padLeft(2, '0');
    final minute = lastUpdated.minute.toString().padLeft(2, '0');

    return '마지막 업데이트: ${lastUpdated.year}.$month.$day $hour:$minute';
  }

  // 오류 메시지를 표시하는 박스를 구성하는 위젯을 반환하는 메서드
  Widget _buildErrorBox({
    required String message,
    required Future<void> Function() onRetry,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onErrorContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: () {
              // 누르면 이 박스가 사라져 버튼의 초점이 전에 쓴 입력칸으로 돌아가므로 먼저 푼다.
              // 입력칸에 초점을 둔 채 터치했으면 그대로 둔다.
              if (!primaryFocusInTextField) releaseFocusHistory();
              // Future를 직접 await하지 않고 재시도만 트리거함.
              onRetry();
            },
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
