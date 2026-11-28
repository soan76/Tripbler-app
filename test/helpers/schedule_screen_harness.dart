import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/schedule/schedule_data.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/map/map_provider.dart';
import 'package:tripbler/providers/schedule/schedule_provider.dart';
import 'package:tripbler/screens/schedule_screen.dart';

import 'fake_auth_notifier.dart';
import 'fake_place_api.dart';
import 'memory_schedule_storage.dart';

/// 일정 화면 위젯 테스트에서 찾는 칸들.
final scheduleTitleField = find.byKey(const ValueKey('schedule-title'));
final schedulePlaceField = find.byKey(const ValueKey('schedule-place'));
final scheduleMemoField = find.byKey(const ValueKey('schedule-memo'));
final scheduleAddFirst = find.byKey(const ValueKey('schedule-add-first'));
final scheduleAddNext = find.byKey(const ValueKey('schedule-add-next'));

/// 일정 테스트의 기준 시각(2026-11-28 토 14:20).
final scheduleTestNow = DateTime(2026, 11, 28, 14, 20);

/// 띄운 일정 화면의 저장소 대역과 provider 컨테이너.
class ScheduleScreenHarness {
  ScheduleScreenHarness(this.storage, this.container);

  final MemoryScheduleStorage storage;
  final ProviderContainer container;
}

/// [items]를 저장해 둔 상태로 일정 화면을 띄운다. 글자 배율은 앱 전체(카드·선택 창 포함)에
/// 적용한다. 장소 고르기 화면의 지도 위젯이 테스트 환경에서 지도 ID를 고르다 내는
/// UnsupportedError는 걸러 낸다.
Future<ScheduleScreenHarness> pumpScheduleScreen(
  WidgetTester tester, {
  List<ScheduleItem> items = const [],
  List<ArchivedScheduleItem> archived = const [],
  Map<String, Object> prefs = const {},
  Size size = const Size(400, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final reportError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = reportError);
  FlutterError.onError = (details) {
    final fromMapId =
        details.exception is UnsupportedError &&
        details.stack.toString().contains('MapIdConfig');
    if (!fromMapId) reportError?.call(details);
  };

  // 기기 백업 목록은 실제 저장소(가짜 shared_preferences)를 쓴다.
  SharedPreferences.setMockInitialValues(prefs);
  final storage = MemoryScheduleStorage(items, archived);
  final places = HeldPlaceApi();
  addTearDown(places.dispose);
  final container = ProviderContainer.test(
    retry: (_, _) => null,
    overrides: [
      scheduleStorageServiceProvider.overrideWithValue(storage),
      scheduleClockProvider.overrideWithValue(() => scheduleTestNow),
      authProvider.overrideWith(FakeAuthNotifier.new),
      placeApiServiceProvider.overrideWithValue(places),
      authorizedRequestRunnerProvider.overrideWithValue(passThroughRunner),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: ScheduleScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return ScheduleScreenHarness(storage, container);
}
