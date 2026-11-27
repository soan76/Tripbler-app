import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/tab_provider.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/screens/photo_translation_screen.dart';
import 'package:tripbler/services/photo_normalizer.dart';
import 'package:tripbler/widgets/translation/photo/photo_capture_view.dart';
import 'package:tripbler/widgets/translation/photo/photo_consent_dialog.dart';
import 'package:tripbler/widgets/translation/photo/photo_result_view.dart';

import '../helpers/fake_camera_platform.dart';

// 사진 번역 화면: 전체 화면 촬영 → 동의 → 결과. Notifier는 호출만 기록하는 가짜로 바꾼다.

const int _granted = 1;
const MethodChannel _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

class _FakePhotoNotifier extends PhotoTranslationNotifier {
  final List<String> processed = [];
  int accepted = 0;
  int cancelled = 0;
  int retakes = 0;
  int leaves = 0;

  @override
  PhotoTranslationState build() => const PhotoTranslationState();

  void emit(PhotoTranslationState next) => state = next;

  @override
  Future<void> processPhoto(String sourcePath) async {
    processed.add(sourcePath);
  }

  @override
  Future<void> acceptConsentAndTranslate() async {
    accepted++;
    state = state.copyWith(status: PhotoTranslationStatus.uploading);
  }

  @override
  void cancelConsent() {
    cancelled++;
    state = state.reset();
  }

  @override
  void retake() {
    retakes++;
    state = state.reset();
  }

  @override
  void leave() {
    leaves++;
    // 실제 Notifier처럼, 정리된 뒤면 아무것도 하지 않고 아니면 상태를 비운다.
    if (!ref.mounted) {
      return;
    }
    state = state.reset();
  }
}

/// 처음 선택된 탭을 정한다(실제 앱은 홈에서 시작한다).
class _TabAt extends TabNotifier {
  _TabAt(this.initialIndex);

  final int initialIndex;

  @override
  TabState build() => TabState(selectedIndex: initialIndex);
}

const int _translationTab = 2;

void main() {
  late CameraPlatform originalCameraPlatform;

  setUp(() => originalCameraPlatform = CameraPlatform.instance);
  tearDown(() => CameraPlatform.instance = originalCameraPlatform);

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  Future<({_FakePhotoNotifier notifier, FakeCameraPlatform camera})> pumpScreen(
    WidgetTester tester, {
    int tabIndex = _translationTab,
    bool photoAi = false,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_permissionChannel, (call) async {
      if (call.method == 'checkPermissionStatus') {
        return _granted;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_permissionChannel, null),
    );

    final camera = FakeCameraPlatform();
    CameraPlatform.instance = camera;
    final notifier = _FakePhotoNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoTranslationProvider.overrideWith(() => notifier),
          tabProvider.overrideWith(() => _TabAt(tabIndex)),
          photoAiTranslationProvider.overrideWithValue(photoAi),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PhotoTranslationScreen()),
        ),
      ),
    );
    await flush(tester);
    return (notifier: notifier, camera: camera);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await flush(tester);
  }

  // 촬영 화면의 안내 문구(촬영 안내·기기/전송 안내)는 2026-11-27 사용자 요청으로 없앴다.
  // 사진 AI 번역의 사진 전송은 처음 촬영 때 동의 대화상자로 알린다.
  void expectNoCaptureNotices() {
    expect(find.textContaining('기기에서'), findsNothing);
    expect(find.textContaining('전송'), findsNothing);
    expect(find.textContaining('보내'), findsNothing);
    expect(find.textContaining('촬영해요'), findsNothing);
    expect(find.textContaining('보관'), findsNothing);
    expect(find.textContaining('삭제'), findsNothing);
  }

  testWidgets('기본 방식(사진 안 보냄)은 촬영 화면에 안내 문구가 없다', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(PhotoCaptureView), findsOneWidget);
    expectNoCaptureNotices();

    await unmount(tester);
  });

  testWidgets('사진 AI 번역 방식도 촬영 화면에 안내 문구가 없다', (tester) async {
    await pumpScreen(tester, photoAi: true);

    expect(find.byType(PhotoCaptureView), findsOneWidget);
    expectNoCaptureNotices();

    await unmount(tester);
  });

  testWidgets('셔터를 누르면 찍은 사진으로 사진 번역을 시작한다', (tester) async {
    final h = await pumpScreen(tester);

    await tester.tap(find.byTooltip(PhotoCaptureView.shutterTooltip));
    await flush(tester);

    expect(h.camera.takePictureCameraIds, isNotEmpty);
    expect(h.notifier.processed, [h.camera.picturePath]);

    await unmount(tester);
  });

  testWidgets('동의를 기다리면 동의 대화상자를 띄우고, 동의하면 한 번 알린다', (tester) async {
    final h = await pumpScreen(tester);

    h.notifier.emit(
      const PhotoTranslationState(
        status: PhotoTranslationStatus.awaitingConsent,
        photo: NormalizedPhoto(path: 'tmp/p.jpg', width: 800, height: 600),
      ),
    );
    await flush(tester);

    expect(find.byType(PhotoConsentDialog), findsOneWidget);
    expect(find.byType(PhotoResultView), findsOneWidget);

    await tester.tap(find.text(PhotoConsentDialog.acceptLabel));
    await flush(tester);

    expect(h.notifier.accepted, 1);
    expect(h.notifier.cancelled, 0);
    expect(find.byType(PhotoConsentDialog), findsNothing);
    expect(find.text(PhotoResultView.uploadingLabel), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('동의 취소면 취소를 알리고 촬영 화면으로 돌아간다', (tester) async {
    final h = await pumpScreen(tester);

    h.notifier.emit(
      const PhotoTranslationState(
        status: PhotoTranslationStatus.awaitingConsent,
        photo: NormalizedPhoto(path: 'tmp/p.jpg', width: 800, height: 600),
      ),
    );
    await flush(tester);
    await tester.tap(find.text(PhotoConsentDialog.cancelLabel));
    await flush(tester);

    expect(h.notifier.cancelled, 1);
    expect(find.byType(PhotoCaptureView), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('동의 대기 중 상태가 바뀌면(세션 변경 등) 대화상자를 닫고 취소를 알리지 않는다', (tester) async {
    final h = await pumpScreen(tester);

    h.notifier.emit(
      const PhotoTranslationState(
        status: PhotoTranslationStatus.awaitingConsent,
        photo: NormalizedPhoto(path: 'tmp/p.jpg', width: 800, height: 600),
      ),
    );
    await flush(tester);
    h.notifier.emit(const PhotoTranslationState());
    await flush(tester);

    expect(find.byType(PhotoConsentDialog), findsNothing);
    expect(h.notifier.cancelled, 0);

    await unmount(tester);
  });

  testWidgets('번역 탭을 떠나면 사진 번역을 떠난다', (tester) async {
    final h = await pumpScreen(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PhotoTranslationScreen)),
    );
    final tabs = container.read(tabProvider.notifier);
    expect(h.notifier.leaves, 0);

    tabs.selectTab(0);
    await flush(tester);
    expect(h.notifier.leaves, 1);

    await unmount(tester);
  });

  testWidgets('다른 탭에 있으면 카메라를 켜지 않고, 번역 탭을 고르면 켠다', (tester) async {
    final h = await pumpScreen(tester, tabIndex: TabState.homeIndex);
    expect(h.camera.initializedCameraIds, isEmpty);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PhotoTranslationScreen)),
    );
    container.read(tabProvider.notifier).selectTab(_translationTab);
    await flush(tester);
    expect(h.camera.initializedCameraIds, hasLength(1));

    await unmount(tester);
  });

  testWidgets('결과 화면에서 탭을 떠나면 촬영 화면으로 돌아가도 카메라를 켜지 않는다', (tester) async {
    final h = await pumpScreen(tester);
    expect(h.camera.initializedCameraIds, hasLength(1));
    h.notifier.emit(
      const PhotoTranslationState(
        status: PhotoTranslationStatus.failed,
        photo: NormalizedPhoto(path: 'tmp/p.jpg', width: 800, height: 600),
      ),
    );
    await flush(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PhotoTranslationScreen)),
    );
    // 탭을 떠나면 leave()로 상태가 idle이 되지만, 보이지 않는 카메라는 켜지 않는다.
    container.read(tabProvider.notifier).selectTab(0);
    await flush(tester);

    expect(h.notifier.leaves, 1);
    expect(h.camera.initializedCameraIds, hasLength(1));
    expect(h.camera.disposedCameraIds, hasLength(1));

    await unmount(tester);
  });

  testWidgets('화면을 제거하면 사진 번역을 떠난다', (tester) async {
    final h = await pumpScreen(tester);

    await unmount(tester);

    expect(h.notifier.leaves, 1);
  });

  group('화면 위 경로 유지와 ProviderScope가 남는 제거', () {
    const awaiting = PhotoTranslationState(
      status: PhotoTranslationStatus.awaitingConsent,
      photo: NormalizedPhoto(path: 'tmp/p.jpg', width: 800, height: 600),
    );

    /// 실제 시간을 흘려 애니메이션·경로 전환을 끝낸다.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    void mockGrantedPermission(WidgetTester tester) {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_permissionChannel, (call) async {
        return call.method == 'checkPermissionStatus' ? _granted : null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(_permissionChannel, null),
      );
      CameraPlatform.instance = FakeCameraPlatform();
    }

    /// 기본 경로('BASE') 위에 사진 번역 화면 경로를 올린다.
    Future<({_FakePhotoNotifier notifier, NavigatorState navigator})>
    pushOverBase(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      mockGrantedPermission(tester);
      final notifier = _FakePhotoNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [photoTranslationProvider.overrideWith(() => notifier)],
          child: MaterialApp(
            home: const Scaffold(body: Text('BASE')),
            routes: {
              '/photo': (_) => const Scaffold(body: PhotoTranslationScreen()),
            },
          ),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/photo');
      await settle(tester);
      expect(find.byType(PhotoTranslationScreen), findsOneWidget);

      notifier.emit(awaiting);
      await settle(tester);
      expect(find.byType(PhotoConsentDialog), findsOneWidget);
      return (notifier: notifier, navigator: navigator);
    }

    void expectScreenKept(NavigatorState navigator) {
      expect(find.byType(PhotoConsentDialog), findsNothing);
      expect(find.byType(PhotoTranslationScreen), findsOneWidget);
      expect(find.text('BASE', skipOffstage: false), findsOneWidget);
      // 남은 경로는 기본 경로와 사진 번역 화면뿐이다.
      expect(navigator.canPop(), isTrue);
    }

    testWidgets('동의하면 대화상자만 닫고 화면과 기본 경로는 남는다', (tester) async {
      final h = await pushOverBase(tester);

      await tester.tap(find.text(PhotoConsentDialog.acceptLabel));
      await settle(tester);

      expect(h.notifier.accepted, 1);
      expectScreenKept(h.navigator);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });

    testWidgets('취소하면 대화상자만 닫고 화면과 기본 경로는 남는다', (tester) async {
      final h = await pushOverBase(tester);

      await tester.tap(find.text(PhotoConsentDialog.cancelLabel));
      await settle(tester);

      expect(h.notifier.cancelled, 1);
      expectScreenKept(h.navigator);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });

    testWidgets('상태가 바뀌어 대화상자를 닫아도 화면과 기본 경로는 남는다', (tester) async {
      final h = await pushOverBase(tester);

      h.notifier.emit(const PhotoTranslationState());
      await settle(tester);

      expect(h.notifier.cancelled, 0);
      expectScreenKept(h.navigator);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });

    testWidgets('ProviderScope를 남기고 화면만 제거해도 오류 없이 떠난다', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      mockGrantedPermission(tester);
      final notifier = _FakePhotoNotifier();
      final show = ValueNotifier<bool>(true);
      addTearDown(show.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [photoTranslationProvider.overrideWith(() => notifier)],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: show,
                builder: (_, visible, _) => visible
                    ? const PhotoTranslationScreen()
                    : const Text('OTHER'),
              ),
            ),
          ),
        ),
      );
      await flush(tester);

      show.value = false;
      await flush(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('OTHER'), findsOneWidget);
      expect(notifier.leaves, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
    });
  });
}
