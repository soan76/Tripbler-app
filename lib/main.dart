import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/tab_provider.dart';
import 'providers/exchange_provider.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TabProvider()),
        ChangeNotifierProvider(create: (_) => ExchangeProvider()),
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
      theme: ThemeData(useMaterial3: true),
      home: const MainScreen(),
    );
  }
}
