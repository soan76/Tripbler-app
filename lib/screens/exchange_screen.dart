import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../presentation/charts/chart_selection_provider.dart';
import '../presentation/exchange/exchange_display_provider.dart';
import '../providers/exchange_provider.dart';
import '../widgets/charts/chart_pair_carousel.dart';
import '../widgets/exchange/chart_currency_picker_sheet.dart';
import '../widgets/exchange/currency_management_bottom_sheet.dart';
import '../widgets/exchange/currency_row.dart';
import '../widgets/exchange/currency_selection_sheet.dart';
import '../widgets/focus_history.dart';

// 환율 화면을 구성하는 StatefulWidget
class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

// 환율 화면을 구성하는 StatefulWidget
class _ExchangeScreenState extends State<ExchangeScreen> {
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

        context.read<ExchangeDisplayProvider>().initialize();
        context.read<ChartSelectionProvider>().initialize();
      });
    }
  }

  // 환율 화면의 상태를 관리하는 State 클래스
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExchangeProvider>();
    final display = context.watch<ExchangeDisplayProvider>();
    final charts = context.watch<ChartSelectionProvider>();

    // 한 번의 build 안에서 동일한 Provider 상태 snapshot을 사용하도록 지역 변수로 정리.
    final visibleCurrencies = provider.visibleCurrencies;
    final isLoading = provider.isLoading;
    final errorMessage = provider.errorMessage;
    final lastUpdated = provider.lastUpdated;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                    ? (display.crypto.selectedCoins.isEmpty
                          ? '환산할 통화를 추가해 주세요'
                          : '암호화폐 현재가 기준 환산 수량')
                    : null,
              ),

              if (isLoading) const LinearProgressIndicator(),

              if (errorMessage != null)
                _buildErrorBox(
                  message: errorMessage,
                  onRetry: provider.fetchRates,
                ),
              if (display.conversionError != null)
                _buildErrorBox(
                  message: display.conversionError!,
                  onRetry: display.refreshConversion,
                ),
              ...[display.base, ...display.visible].map((row) {
                final isBaseRow = row.id == display.base.id;
                final quote = row.isCrypto
                    ? display.crypto.priceFor(row.code)
                    : null;
                final priceError = row.isCrypto
                    ? display.crypto.errorFor(row.code)
                    : null;
                final time = quote?.fetchedAt.toLocal();
                final status = !row.isCrypto
                    ? null
                    : quote == null
                    ? (priceError != null ? '조회 실패 · 아래로 당겨 재시도' : '현재가 조회 중')
                    : '${display.crypto.isStale(row.code) ? '저장값 · ' : ''}${display.crypto.isLoading(row.code) ? '갱신 중 · ' : ''}1 ${row.code} = ${NumberFormat('#,##0.########').format(quote.price)} KRW · ${DateFormat('MM.dd HH:mm').format(time!)}';
                return CurrencyRow(
                  key: ValueKey(row.id),
                  currency: row,
                  isBase: display.isActive(row),
                  amount: display.amountFor(row),
                  rate: row.isCrypto ? null : provider.rateFor(row.code),
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
                          provider.changeBaseCurrency(currency);
                        } else {
                          provider.replaceVisibleCurrency(
                            index: visibleCurrencies.indexWhere(
                              (item) => item.code == row.code,
                            ),
                            newCurrency: currency,
                          );
                        }
                      },
                    );
                  },
                  onGraphTap: row.isCrypto ? null : _showChartGuide,
                );
              }),

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
                  currencies: display.available,
                  onPick: (index, {required base, required swapped}) =>
                      _pickChartCurrency(index, base: base, swapped: swapped),
                  onAdd: charts.canAdd ? charts.add : null,
                  onRemove: charts.canRemove ? charts.remove : null,
                  swappedAfterReplace: charts.swappedAfterReplace,
                  swappedAfterExchange: charts.swappedAfterExchange,
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
    final charts = context.read<ChartSelectionProvider>();
    final display = context.read<ExchangeDisplayProvider>();
    final pair = charts.pairs[index];
    _leaveAmountField();
    final picked = await showChartCurrencyPicker(
      context: context,
      title: '차트 통화 선택',
      current: pair.currencyOf(base: base, currencies: display.available),
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

  // 기준 통화와 상대 통화의 그래프 안내 SnackBar 중복 코드를 하나의 메서드로 분리.
  void _showChartGuide() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('아래 차트 영역에서 환율 변동을 확인할 수 있습니다')),
    );
  }

  // 환율 화면의 헤더 영역을 구성하는 위젯을 반환하는 메서드
  Widget _buildHeader(DateTime? lastUpdated, {String? emptyMessage}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colorScheme.surface,
      child: Center(
        child: Text(
          lastUpdated == null && emptyMessage != null
              ? emptyMessage
              : _formatLastUpdatedText(lastUpdated?.toLocal()),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
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
