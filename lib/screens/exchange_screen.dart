import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/exchange_provider.dart';
import '../widgets/currency_management_bottom_sheet.dart';
import '../widgets/currency_row.dart';
import '../widgets/currency_selection_sheet.dart';
import '../widgets/exchange_chart_carousel.dart';
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

        context.read<ExchangeProvider>().initialize();
      });
    }
  }

  // 환율 화면의 상태를 관리하는 State 클래스
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExchangeProvider>();

    // 한 번의 build 안에서 동일한 Provider 상태 snapshot을 사용하도록 지역 변수로 정리.
    final baseCurrency = provider.baseCurrency;
    final visibleCurrencies = provider.visibleCurrencies;
    final inputAmount = provider.inputAmount;
    final isLoading = provider.isLoading;
    final errorMessage = provider.errorMessage;
    final lastUpdated = provider.lastUpdated;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: RefreshIndicator(
        onRefresh: provider.fetchRates,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(lastUpdated),

              if (isLoading) const LinearProgressIndicator(),

              if (errorMessage != null)
                _buildErrorBox(
                  message: errorMessage,
                  onRetry: provider.fetchRates,
                ),
              // 기준 통화와 상대 통화 간의 환율을 표시하는 CurrencyRow 위젯
              CurrencyRow(
                currency: baseCurrency,
                isBase: provider.activeInputCurrencyCode == baseCurrency.code,
                amount: inputAmount,
                rate: 1,

                onAmountTap: () {
                  provider.selectInputCurrency(baseCurrency.code);
                },

                onAmountChanged: (value) {
                  provider.changeAmountFromCurrency(
                    currencyCode: baseCurrency.code,
                    amount: value,
                  );
                },
                onCurrencyTap: () {
                  showCurrencySelectionSheet(
                    context: context,
                    selectedCurrency: baseCurrency,
                    onSelected: provider.changeBaseCurrency,
                  );
                },
                onGraphTap: _showChartGuide,
              ),
              // 상대 통화 목록을 표시하는 CurrencyRow 위젯 리스트
              ...List.generate(visibleCurrencies.length, (index) {
                final currency = visibleCurrencies[index];
                final amount = provider.convertedAmount(currency.code);

                return CurrencyRow(
                  currency: currency,
                  isBase: provider.activeInputCurrencyCode == currency.code,
                  amount: amount,
                  rate: provider.rateFor(currency.code),

                  onAmountTap: () {
                    provider.selectInputCurrency(currency.code);
                  },

                  onAmountChanged: (value) {
                    provider.changeAmountFromCurrency(
                      currencyCode: currency.code,
                      amount: value,
                    );
                  },

                  onCurrencyTap: () {
                    showCurrencySelectionSheet(
                      context: context,
                      selectedCurrency: currency,
                      onSelected: (newCurrency) {
                        provider.replaceVisibleCurrency(
                          index: index,
                          newCurrency: newCurrency,
                        );
                      },
                    );
                  },
                  onGraphTap: _showChartGuide,
                );
              }),

              // 통화 추가 / 편집 버튼을 표시하는 OutlinedButton 위젯
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: OutlinedButton.icon(
                  onPressed: () {
                    showCurrencyManagementBottomSheet(
                      context: context,
                      baseCurrency: baseCurrency,
                      visibleCurrencies: visibleCurrencies,
                      onApply: provider.applyVisibleCurrencies,
                    );
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
              if (visibleCurrencies.isNotEmpty) ...[
                const SizedBox(height: 64),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '차트',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ExchangeChartCarousel(
                        baseCurrency: baseCurrency,
                        targetCurrencies: visibleCurrencies,
                      ),
                    ],
                  ),
                ),
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
  Widget _buildHeader(DateTime? lastUpdated) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: colorScheme.surface,
      child: Center(
        child: Text(
          _formatLastUpdatedText(lastUpdated),
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
