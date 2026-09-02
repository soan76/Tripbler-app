import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/tab_provider.dart';
import 'providers/exchange_provider.dart';
import 'providers/translation_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/map_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/account_recovery_provider.dart';
import 'screens/auth/auth_gate.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AccountRecoveryProvider()),
        ChangeNotifierProvider(create: (_) => TabProvider()),
        ChangeNotifierProvider(create: (_) => ExchangeProvider()),
        ChangeNotifierProvider(create: (_) => TranslationProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const TripblerApp(),
    ),
  );
}

class TripblerApp extends StatelessWidget {
  const TripblerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider =
      context.watch<SettingsProvider>();
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
