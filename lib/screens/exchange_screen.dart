import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/currency_model.dart';
import '../providers/exchange_provider.dart';
import '../widgets/currency_management_bottom_sheet.dart';
import '../widgets/currency_row.dart';
import '../widgets/currency_selection_sheet.dart';
import 'exchange_detail_screen.dart';

class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExchangeProvider>();

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(provider),
          if (provider.isLoading) const LinearProgressIndicator(),
          if (provider.errorMessage != null)
            _buildErrorBox(
              message: provider.errorMessage!,
              onRetry: provider.fetchRates,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: provider.fetchRates,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
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
                      _openDetail(
                        context: context,
                        baseCurrency: provider.baseCurrency,
                        targetCurrency: provider.baseCurrency,
                        currentRate: 1,
                      );
                    },
                  ),
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
                        _openDetail(
                          context: context,
                          baseCurrency: provider.baseCurrency,
                          targetCurrency: currency,
                          currentRate: provider.rateFor(currency.code),
                        );
                      },
                    );
                  }),
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
                ],
              ),
            ),
          ),

          if (provider.visibleCurrencies.isNotEmpty)
            _buildChartSection(provider),
        ],
      ),
    );
  }

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

  Widget _buildChartSection(ExchangeProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '차트',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              provider.isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      onPressed: provider.fetchRates,
                      icon: const Icon(Icons.refresh),
                    ),
            ],
          ),
          const SizedBox(height: 12),

          ...provider.visibleCurrencies.map((currency) {
            final rate = provider.rateFor(currency.code);
            final convertedAmount = provider.convertedAmount(currency.code);

            return _buildChartPreviewCard(
              provider: provider,
              targetCurrency: currency,
              rate: rate,
              convertedAmount: convertedAmount,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChartPreviewCard({
    required ExchangeProvider provider,
    required CurrencyModel targetCurrency,
    required double? rate,
    required double convertedAmount,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _openDetail(
            context: context,
            baseCurrency: provider.baseCurrency,
            targetCurrency: targetCurrency,
            currentRate: rate,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                targetCurrency.flagEmoji,
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${provider.baseCurrency.code} / ${targetCurrency.code}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rate == null
                          ? '환율 데이터 없음'
                          : '1 ${provider.baseCurrency.code} = ${_formatRate(rate)} ${targetCurrency.code}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Icon(Icons.show_chart, color: Colors.blue),
                  const SizedBox(height: 6),
                  Text(
                    _formatRate(convertedAmount),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRate(double value) {
    if (value == 0) {
      return '0';
    }

    if (value.abs() >= 100) {
      return value
          .toStringAsFixed(2)
          .replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+\.)'),
            (match) => '${match[1]},',
          );
    }

    if (value.abs() >= 1) {
      return value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }

    return value.toStringAsFixed(6).replaceAll(RegExp(r'\.?0+$'), '');
  }

  void _openDetail({
    required BuildContext context,
    required CurrencyModel baseCurrency,
    required CurrencyModel targetCurrency,
    required double? currentRate,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return ExchangeDetailScreen(
            baseCurrency: baseCurrency,
            targetCurrency: targetCurrency,
            currentRate: currentRate,
          );
        },
      ),
    );
  }
}
