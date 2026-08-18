import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/tab_provider.dart';
import 'providers/exchange_provider.dart';
import 'providers/translation_provider.dart';
import 'providers/map_provider.dart';
import 'screens/main_screen.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TabProvider()),
        ChangeNotifierProvider(create: (_) => ExchangeProvider()),
        ChangeNotifierProvider(create: (_) => TranslationProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
      ],
      child: const TripblerApp(),
    ),
  );
}

class TripblerApp extends StatelessWidget {
  const TripblerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tripbler',      
      theme: AppTheme.lightTheme,

      darkTheme: AppTheme.darkTheme,

      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}
