import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/exchange_provider.dart';
import '../widgets/currency_management_bottom_sheet.dart';
import '../widgets/currency_row.dart';
import '../widgets/currency_selection_sheet.dart';
import '../widgets/exchange_chart_carousel.dart';

class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}
// 환율 화면을 구성하는 StatefulWidget
class _ExchangeScreenState extends State<ExchangeScreen> {
  bool hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!hasInitialized) {
      hasInitialized = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<ExchangeProvider>().initialize();
      });
    }
  }
  // 환율 화면의 상태를 관리하는 State 클래스
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExchangeProvider>();

    return Container(
      color: Colors.white,
      child: RefreshIndicator(
        onRefresh: provider.fetchRates,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(provider),

              if (provider.isLoading) const LinearProgressIndicator(),

              if (provider.errorMessage != null)
                _buildErrorBox(
                  message: provider.errorMessage!,
                  onRetry: provider.fetchRates,
                ),
              // 기준 통화와 상대 통화 간의 환율을 표시하는 CurrencyRow 위젯
              CurrencyRow(
                currency: provider.baseCurrency,
                isBase: true,
                amount: provider.inputAmount,
                rate: 1,
                onAmountChanged: provider.changeAmount,
                onCurrencyTap: () {
                  showCurrencySelectionSheet(
                    context: context,
                    selectedCurrency: provider.baseCurrency,
                    onSelected: provider.changeBaseCurrency,
                  );
                },
                onGraphTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('아래 차트 영역에서 환율 변동을 확인할 수 있습니다.'),
                    ),
                  );
                },
              ),
              // 상대 통화 목록을 표시하는 CurrencyRow 위젯 리스트
              ...List.generate(provider.visibleCurrencies.length, (index) {
                final currency = provider.visibleCurrencies[index];
                final amount = provider.convertedAmount(currency.code);

                return CurrencyRow(
                  currency: currency,
                  isBase: false,
                  amount: amount,
                  rate: provider.rateFor(currency.code),
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
                  onGraphTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('아래 차트 영역에서 환율 변동을 확인할 수 있습니다.'),
                      ),
                    );
                  },
                );
              }),

              // 통화 추가 / 편집 버튼을 표시하는 OutlinedButton 위젯
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: OutlinedButton.icon(
                  onPressed: () {
                    showCurrencyManagementBottomSheet(
                      context: context,
                      baseCurrency: provider.baseCurrency,
                      visibleCurrencies: provider.visibleCurrencies,
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
              if (provider.visibleCurrencies.isNotEmpty) ...[
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
                        baseCurrency: provider.baseCurrency,
                        targetCurrencies: provider.visibleCurrencies,
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

  // 환율 화면의 헤더 영역을 구성하는 위젯을 반환하는 메서드
  Widget _buildHeader(ExchangeProvider provider) {
    final lastUpdated = provider.lastUpdated;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '환율',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            lastUpdated == null
                ? '환율 정보를 불러오는 중입니다.'
                : '마지막 업데이트: ${lastUpdated.year}.${lastUpdated.month.toString().padLeft(2, '0')}.${lastUpdated.day.toString().padLeft(2, '0')} ${lastUpdated.hour.toString().padLeft(2, '0')}:${lastUpdated.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // 오류 메시지를 표시하는 박스를 구성하는 위젯을 반환하는 메서드
  Widget _buildErrorBox({
    required String message,
    required VoidCallback onRetry,
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
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
