import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/exchange_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/currency_management_bottom_sheet.dart';
import '../widgets/navigation/app_top_bar.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final exchangeProvider = context.watch<ExchangeProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

    // 현재 환율 화면에 표시되고 있는 모든 통화
    final displayedCurrencies = [
      exchangeProvider.baseCurrency,
      ...exchangeProvider.visibleCurrencies,
    ];

    final displayedCurrencyCodes = displayedCurrencies
        .map((currency) => currency.code)
        .join(', ');

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // 뒤로가기 버튼 + 설정
            const AppTopBar(title: '설정', showBackButton: true),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                children: [
                  // 화면의 통화
                  _buildSettingItem(
                    context: context,
                    title: '화면의 통화',
                    subtitle:
                        '${displayedCurrencies.length}개 · $displayedCurrencyCodes',
                    onTap: () {
                      showCurrencyManagementBottomSheet(
                        context: context,
                        baseCurrency: exchangeProvider.baseCurrency,
                        visibleCurrencies: exchangeProvider.visibleCurrencies,
                        onApply: exchangeProvider.applyVisibleCurrencies,
                      );
                    },
                  ),

                  const Divider(),

                  // 자국 통화
                  _buildSettingItem(
                    context: context,
                    title: '자국 통화',
                    subtitle: 'KRW',
                    onTap: () {
                      // 자국 통화 변경 기능은 추후 연결
                    },
                  ),

                  const Divider(),

                  // 자릿수 제한
                  _buildSettingItem(
                    context: context,
                    title: '자릿수 제한',
                    subtitle: settingsProvider.decimalPlacesLabel,
                    onTap: () {
                      _showDecimalLimitDialog(context, settingsProvider);
                    },
                  ),

                  const Divider(),

                  // 라이트 / 다크 모드
                  _buildThemeSettingItem(context, settingsProvider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 일반 설정 항목
  Widget _buildSettingItem({
    required BuildContext context,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // 자릿수 제한 선택 창
  void _showDecimalLimitDialog(
    BuildContext context,
    SettingsProvider settingsProvider,
  ) {
    // -1은 자동
    const decimalOptions = [-1, 0, 1, 2, 3, 4, 5, 6];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('자릿수 제한'),
          children: decimalOptions.map((decimal) {
            final label = decimal == -1 ? '자동' : '$decimal';

            return RadioListTile<int>(
              title: Text(label),
              value: decimal,
              groupValue: settingsProvider.decimalPlaces,
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                settingsProvider.changeDecimalPlaces(value);

                Navigator.of(dialogContext).pop();
              },
            );
          }).toList(),
        );
      },
    );
  }

  // 라이트 / 다크 모드 설정 항목
  Widget _buildThemeSettingItem(
    BuildContext context,
    SettingsProvider settingsProvider,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    final isDarkMode = settingsProvider.isDarkMode;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '라이트 / 다크 모드',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),

          Switch(
            value: isDarkMode,
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
              if (states.contains(WidgetState.selected)) {
                return const Icon(Icons.dark_mode);
              }

              return const Icon(Icons.light_mode);
            }),
            onChanged: (_) {
              settingsProvider.toggleTheme();
            },
          ),
        ],
      ),
    );
  }
}
