import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/tab_provider.dart';
import 'providers/exchange_provider.dart';
import 'providers/translation_provider.dart';
import 'providers/map_provider.dart';
import 'screens/main_screen.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),

      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}
