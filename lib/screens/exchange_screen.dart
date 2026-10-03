import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../crypto/widgets/crypto_chart_carousel.dart';
import '../presentation/exchange/exchange_display_provider.dart';
import '../providers/exchange_provider.dart';
import '../widgets/exchange/currency_management_bottom_sheet.dart';
import '../widgets/exchange/currency_row.dart';
import '../widgets/exchange/currency_selection_sheet.dart';
import '../widgets/exchange/exchange_chart_carousel.dart';

enum ChartCategory { fiat, crypto }

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
  ChartCategory _chartCategory = ChartCategory.fiat;
  bool _hasOpenedCryptoCharts = false;

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
      });
    }
  }

  // 환율 화면의 상태를 관리하는 State 클래스
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExchangeProvider>();
    final display = context.watch<ExchangeDisplayProvider>();

    // 한 번의 build 안에서 동일한 Provider 상태 snapshot을 사용하도록 지역 변수로 정리.
    final baseCurrency = provider.baseCurrency;
    final visibleCurrencies = provider.visibleCurrencies;
    final isLoading = provider.isLoading;
    final errorMessage = provider.errorMessage;
    final lastUpdated = provider.lastUpdated;
    final colorScheme = Theme.of(context).colorScheme;

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
                          ? '환산할 통화를 추가해 주세요.'
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
                    : priceError != null
                    ? '조회 실패 · 아래로 당겨 재시도'
                    : quote == null
                    ? '현재가 조회 중'
                    : '1 ${row.code} = ${NumberFormat('#,##0.########').format(quote.price)} KRW · ${DateFormat('MM.dd HH:mm').format(time!)}';
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
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: OutlinedButton.icon(
                  onPressed: () {
                    showCurrencyManagementBottomSheet(context: context);
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('통화 추가 / 편집'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),

              // 차트 영역을 표시하는 ExchangeChartCarousel 위젯
              if (visibleCurrencies.isNotEmpty ||
                  display.crypto.selectedCoins.isNotEmpty) ...[
                const SizedBox(height: 64),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '차트',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<ChartCategory>(
                    segments: const [
                      ButtonSegment(
                        value: ChartCategory.fiat,
                        label: Text('통화'),
                      ),
                      ButtonSegment(
                        value: ChartCategory.crypto,
                        label: Text('암호'),
                      ),
                    ],
                    selected: {_chartCategory},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _chartCategory = selection.single;
                        if (_chartCategory == ChartCategory.crypto) {
                          _hasOpenedCryptoCharts = true;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Offstage(
                  offstage: _chartCategory != ChartCategory.fiat,
                  child: TickerMode(
                    enabled: _chartCategory == ChartCategory.fiat,
                    child: visibleCurrencies.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('통화 관리에서 통화를 추가해 주세요.'),
                          )
                        : ExchangeChartCarousel(
                            baseCurrency: baseCurrency,
                            targetCurrencies: visibleCurrencies,
                            active: _chartCategory == ChartCategory.fiat,
                          ),
                  ),
                ),
                if (_hasOpenedCryptoCharts)
                  Offstage(
                    offstage: _chartCategory != ChartCategory.crypto,
                    child: TickerMode(
                      enabled: _chartCategory == ChartCategory.crypto,
                      child: display.crypto.selectedCoins.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('통화 관리에서 암호화폐를 추가해 주세요.'),
                            )
                          : CryptoChartCarousel(
                              coins: display.crypto.selectedCoins,
                              active: _chartCategory == ChartCategory.crypto,
                            ),
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 기준 통화와 상대 통화의 그래프 안내 SnackBar 중복 코드를 하나의 메서드로 분리.
  void _showChartGuide() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('아래 차트 영역에서 환율 변동을 확인할 수 있습니다.')),
    );
  }

  // 환율 화면의 헤더 영역을 구성하는 위젯을 반환하는 메서드
  Widget _buildHeader(DateTime? lastUpdated, {String? emptyMessage}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: colorScheme.surface,
      child: Center(
        child: Text(
          lastUpdated == null && emptyMessage != null
              ? emptyMessage
              : _formatLastUpdatedText(lastUpdated?.toLocal()),
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      ),
    );
  }

  // 마지막 업데이트 문자열 생성 로직을 분리해 build와 header 코드를 읽기 쉽게 함.
  String _formatLastUpdatedText(DateTime? lastUpdated) {
    if (lastUpdated == null) {
      return '환율 정보를 불러오는 중입니다.';
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () {
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
