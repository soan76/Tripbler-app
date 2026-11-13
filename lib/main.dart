import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:provider/provider.dart';

import 'crypto/providers/crypto_provider.dart';
import 'presentation/charts/chart_selection_provider.dart';
import 'presentation/exchange/exchange_display_provider.dart';
import 'providers/tab_provider.dart';
import 'providers/exchange_provider.dart';
import 'providers/translation_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/map_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/account_recovery_provider.dart';
import 'screens/auth/auth_gate.dart';
import 'core/theme/app_theme.dart';

/// 앱 전체를 감싸는 Riverpod 범위. 실패한 provider를 자동으로 다시 시도하지 않는다.
Widget buildAppScope({
  List<Override> overrides = const [],
  required Widget child,
}) {
  return ProviderScope(
    retry: (_, _) => null,
    overrides: overrides,
    child: child,
  );
}

void main() {
  runApp(
    buildAppScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => AccountRecoveryProvider()),
          ChangeNotifierProvider(create: (_) => TabProvider()),
          ChangeNotifierProvider(create: (_) => ExchangeProvider()),
          ChangeNotifierProvider(create: (_) => CryptoProvider()),
          ChangeNotifierProvider(
            create: (context) => ExchangeDisplayProvider(
              context.read<ExchangeProvider>(),
              context.read<CryptoProvider>(),
            ),
          ),
          ChangeNotifierProvider(create: (_) => ChartSelectionProvider()),
          ChangeNotifierProvider(create: (_) => TranslationProvider()),
          // 장소 검색은 로그인이 필요하다. 토큰 첨부·재발급은 AuthProvider가 맡고,
          // 로그인이 풀리면 MapProvider가 검색 상태를 비운다.
          ChangeNotifierProvider(
            create: (context) {
              final authProvider = context.read<AuthProvider>();

              return MapProvider(
                authorizedRequest: authProvider.runAuthorizedRequest,
                authState: authProvider,
                isAuthenticated: () => authProvider.isAuthenticated,
              );
            },
          ),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const TripblerApp(),
      ),
    ),
  );
}

class TripblerApp extends StatelessWidget {
  const TripblerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tripbler',
      theme: AppTheme.lightTheme,

      darkTheme: AppTheme.darkTheme,

      themeMode: settingsProvider.themeMode,
      home: const AuthGate(),
    );
  }
}
