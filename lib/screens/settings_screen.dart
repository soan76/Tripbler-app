import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ConsumerWidget, ProviderListenableSelect, WidgetRef;

import '../presentation/exchange/exchange_display_view.dart';
import '../providers/settings_provider.dart';
import '../widgets/exchange/currency_management_bottom_sheet.dart';
import '../widgets/navigation/app_top_bar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    // 통화 목록만 쓰므로 금액·시세가 바뀔 때는 다시 그리지 않는다.
    final currencies = ref.watch(
      exchangeDisplayViewProvider.select((view) => view.currencies),
    );
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    // 현재 환율 화면에 표시되고 있는 모든 통화
    final displayedCurrencies = currencies.displayed;

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
                      showCurrencyManagementBottomSheet(context: context);
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
                    subtitle: settings.decimalPlacesLabel,
                    onTap: () {
                      _showDecimalLimitDialog(
                        context,
                        settings,
                        settingsNotifier,
                      );
                    },
                  ),

                  const Divider(),

                  // 라이트 / 다크 모드
                  _buildThemeSettingItem(context, settings, settingsNotifier),
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
    SettingsState settings,
    SettingsNotifier settingsNotifier,
  ) {
    // -1은 자동
    const decimalOptions = [-1, 0, 1, 2, 3, 4, 5, 6];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('자릿수 제한'),
          children: [
            RadioGroup<int>(
              groupValue: settings.decimalPlaces,
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                settingsNotifier.changeDecimalPlaces(value);

                Navigator.of(dialogContext).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: decimalOptions.map((decimal) {
                  final label = decimal == -1
                      ? SettingsState.autoDecimalPlacesLabel
                      : '$decimal';

                  return RadioListTile<int>(title: Text(label), value: decimal);
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  // 라이트 / 다크 모드 설정 항목
  Widget _buildThemeSettingItem(
    BuildContext context,
    SettingsState settings,
    SettingsNotifier settingsNotifier,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    final isDarkMode = settings.isDarkMode;

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
              settingsNotifier.toggleTheme();
            },
          ),
        ],
      ),
    );
  }
}
