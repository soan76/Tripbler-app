import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:provider/provider.dart';

import 'providers/settings_provider.dart';
import 'providers/map_provider.dart';
import 'providers/auth_provider.dart';
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
        ],
        child: const TripblerApp(),
      ),
    ),
  );
}

class TripblerApp extends ConsumerWidget {
  const TripblerApp({super.key, this.home = const AuthGate()});

  /// 시작 화면. 테스트에서 인증 흐름 없이 앱 틀만 띄울 때 바꾼다.
  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      settingsProvider.select((settings) => settings.themeMode),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tripbler',
      theme: AppTheme.lightTheme,

      darkTheme: AppTheme.darkTheme,

      themeMode: themeMode,
      home: home,
    );
  }
}
