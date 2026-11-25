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
    // 실제 Notifier처럼 상태를 비운다.
    state = state.reset();
  }
}

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
    WidgetTester tester,
  ) async {
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
        overrides: [photoTranslationProvider.overrideWith(() => notifier)],
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

  testWidgets('촬영 화면은 하단 고정 안내를 보이고 보관·삭제 문구는 없다', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(PhotoCaptureView), findsOneWidget);
    expect(find.text('촬영한 사진은 AI 번역을 위해 전송됩니다'), findsOneWidget);
    expect(find.textContaining('보관'), findsNothing);
    expect(find.textContaining('삭제'), findsNothing);

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

    tabs.selectTab(2);
    await flush(tester);
    expect(h.notifier.leaves, 0);

    tabs.selectTab(0);
    await flush(tester);
    expect(h.notifier.leaves, 1);

    await unmount(tester);
  });

  testWidgets('화면을 제거하면 사진 번역을 떠난다', (tester) async {
    final h = await pumpScreen(tester);

    await unmount(tester);

    expect(h.notifier.leaves, 1);
  });
}
