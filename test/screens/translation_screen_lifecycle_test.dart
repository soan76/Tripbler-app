import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/capture_frame.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/translation/translation_provider.dart';
import 'package:tripbler/screens/translation_screen.dart';
import 'package:tripbler/services/ocr_service.dart';
import 'package:tripbler/services/translation_service.dart';
import 'package:tripbler/widgets/translation/initial_camera_permission_view.dart';
import 'package:tripbler/widgets/translation/translation_camera.dart';
import 'package:tripbler/widgets/translation/translation_camera_preview_card.dart';
import 'package:tripbler/widgets/translation/translation_result_view.dart';

import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_camera_platform.dart';

// 번역 화면 카메라 비동기·생명주기 회귀 테스트.
// 가짜 카메라 플랫폼의 Completer(initializeGate·takePictureGate)와 권한 요청 Completer로 시점을 정한다.

const int _denied = 0;
const int _granted = 1;
const int _cameraPermission = 1;

const MethodChannel _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);
const MethodChannel _imagePickerChannel = MethodChannel(
  'plugins.flutter.io/image_picker',
);

const String _cameraStartFailedMessage =
    '카메라를 시작할 수 없습니다.\n카메라 상태를 확인한 뒤 다시 시도해 주세요.';
const String _captureFailedMessage = '사진을 촬영하지 못했습니다.\n다시 시도해 주세요.';
const String _preparingCameraMessage = '카메라를 준비하고 있습니다.';
const String _translatingMessage = '번역하고 있습니다.';
const String _emptyInFrameMessage =
    '프레임 안에서 번역할 문자를 찾지 못했습니다.\n번역할 글자를 프레임 안에 맞춰 다시 촬영해 주세요.';
const String _retakeButton = '다시 촬영';
const String _repickButton = '다시 선택';
const String _shutterTooltip = '사진 찍기';

class _PermissionChannelFake {
  int checkResult = _denied;
  int requestResult = _denied;

  /// 있으면 권한 요청이 이 Completer를 기다린다(대화상자가 떠 있는 동안).
  Completer<void>? requestGate;

  /// 있으면 권한 상태 확인이 이 Completer를 기다린다(늦게 오는 확인 응답).
  Completer<void>? checkGate;

  int checkCount = 0;
  int requestCount = 0;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
        checkCount++;
        final result = checkResult;
        final gate = checkGate;
        if (gate != null) {
          await gate.future;
        }
        return result;
      case 'requestPermissions':
        requestCount++;
        final gate = requestGate;
        if (gate != null) {
          await gate.future;
        }
        return <int, int>{_cameraPermission: requestResult};
      case 'openAppSettings':
        return true;
    }
    return null;
  }
}

class _FakeOcrService extends OcrService {
  int lineCallCount = 0;
  int textCallCount = 0;
  CaptureFrameLines linesResult = (
    lines: const <String>['hello'],
    frameApplied: true,
  );

  @override
  Future<CaptureFrameLines> recognizeLines({
    required String imagePath,
    required String sourceLanguageCode,
    bool onlyInCaptureFrame = false,
    double? cameraPreviewAspect,
  }) async {
    lineCallCount++;
    return linesResult;
  }

  @override
  Future<String> recognizeText({
    required String imagePath,
    required String sourceLanguageCode,
  }) async {
    textCallCount++;
    return 'hello';
  }
}

class _FakeTranslationService extends TranslationService {
  final List<Completer<String>> calls = [];

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) {
    final completer = Completer<String>();
    calls.add(completer);
    return completer.future;
  }
}

class _Harness {
  _Harness(this.permissions, this.camera, this.ocr, this.translator);

  final _PermissionChannelFake permissions;
  final FakeCameraPlatform camera;
  final _FakeOcrService ocr;
  final _FakeTranslationService translator;
  int pickCount = 0;

  /// 갤러리에서 고를 사진 경로. null이면 고르기를 취소한 것과 같다.
  String? pickedPath;
}

void main() {
  late CameraPlatform originalCameraPlatform;

  setUp(() => originalCameraPlatform = CameraPlatform.instance);

  tearDown(() {
    CameraPlatform.instance = originalCameraPlatform;
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  Future<_Harness> pumpScreen(
    WidgetTester tester, {
    int checkResult = _granted,
    int requestResult = _denied,
    FakeCameraPlatform? camera,
  }) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final permissions = _PermissionChannelFake()
      ..checkResult = checkResult
      ..requestResult = requestResult;
    final fakeCamera = camera ?? FakeCameraPlatform();
    final harness = _Harness(
      permissions,
      fakeCamera,
      _FakeOcrService(),
      _FakeTranslationService(),
    );

    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_permissionChannel, permissions.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(_permissionChannel, null),
    );
    messenger.setMockMethodCallHandler(_imagePickerChannel, (call) async {
      harness.pickCount++;
      return harness.pickedPath;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_imagePickerChannel, null),
    );

    CameraPlatform.instance = fakeCamera;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => FakeAuthNotifier(initiallySignedIn: false),
          ),
          ocrServiceProvider.overrideWithValue(harness.ocr),
          translationServiceProvider.overrideWithValue(harness.translator),
        ],
        child: const MaterialApp(home: Scaffold(body: TranslationScreen())),
      ),
    );
    await flush(tester);

    return harness;
  }

  Future<void> tapAndFlush(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder, warnIfMissed: false);
    await flush(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await flush(tester);
  }

  /// 권한 대화상자처럼 잠깐 비활성이 됐다가 돌아온다.
  Future<void> inactiveThenResumed(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
  }

  /// 실제 백그라운드로 갔다가 돌아온다.
  Future<void> backgroundRoundTrip(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await flush(tester);
    }
  }

  void expectCameraReadyView() {
    expect(find.byType(TranslationCameraPreviewCard), findsOneWidget);
    expect(find.bySemanticsLabel('카메라 준비 중'), findsNothing);
    expect(find.text(_cameraStartFailedMessage), findsNothing);
  }

  ButtonStyleButton buttonWithLabel(WidgetTester tester, String label) {
    return tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
  }

  TranslationState stateOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(TranslationScreen)),
    ).read(translationProvider);
  }

  TranslationNotifier notifierOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(TranslationScreen)),
    ).read(translationProvider.notifier);
  }

  group('A. 카메라 준비 중 잠시 종료·화면 제거', () {
    testWidgets('준비 중 inactive→resumed: 오류 화면 없이 돌아온 뒤 카메라를 다시 준비한다', (
      tester,
    ) async {
      final gate = Completer<void>();
      final camera = FakeCameraPlatform()..initializeGate = gate;
      final h = await pumpScreen(tester, camera: camera);
      final firstId = camera.lastCameraId;
      expect(find.text(_preparingCameraMessage), findsOneWidget);

      await inactiveThenResumed(tester);
      expect(find.text(_cameraStartFailedMessage), findsNothing);

      camera.initializeGate = null;
      gate.complete();
      await flush(tester);

      // 예전 버그: 돌아온 뒤 재준비가 "준비 중" 표시 때문에 빠지고, 끊긴 준비가 cameraReady를 남겨
      // 컨트롤러 없는 스피너에 머물렀다.
      expect(h.permissions.checkCount, 2);
      expect(camera.disposedCameraIds, contains(firstId));
      expect(camera.createdCameraIds, hasLength(2));
      expectCameraReadyView();

      await unmount(tester);
    });

    testWidgets('준비 중 화면을 빼면 새 컨트롤러를 닫고 더 만들지 않는다', (tester) async {
      final gate = Completer<void>();
      final camera = FakeCameraPlatform()..initializeGate = gate;
      await pumpScreen(tester, camera: camera);

      await unmount(tester);
      gate.complete();
      await flush(tester);

      expect(camera.createdCameraIds, hasLength(1));
      expect(camera.disposedCameraIds, [camera.lastCameraId]);
    });
  });

  group('A·C. 중복 초기화', () {
    testWidgets('실제 백그라운드 왕복: 돌아올 때 카메라를 한 번만 다시 만든다', (tester) async {
      final h = await pumpScreen(tester);
      final firstId = h.camera.lastCameraId;

      await backgroundRoundTrip(tester);

      expect(h.camera.disposedCameraIds, [firstId]);
      expect(h.camera.createdCameraIds, hasLength(2));
      expect(h.camera.initializedCameraIds, hasLength(2));
      expectCameraReadyView();

      await unmount(tester);
    });

    testWidgets('준비 중에 다시 확인해도(resumed 두 번) 진행 중인 준비를 함께 써서 카메라는 하나다', (
      tester,
    ) async {
      final gate = Completer<void>();
      final camera = FakeCameraPlatform()..initializeGate = gate;
      final h = await pumpScreen(tester, camera: camera);

      // inactive 없이 resumed만 다시 오면(이미 활성) 진행 중인 준비를 끊지 않는다.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);
      expect(h.permissions.checkCount, 2);

      camera.initializeGate = null;
      gate.complete();
      await flush(tester);

      expect(camera.createdCameraIds, hasLength(1));
      expectCameraReadyView();

      await unmount(tester);
    });
  });

  group('B. 결과 화면에서 돌아올 때 상태 유지', () {
    testWidgets('번역 중 inactive→resumed: 번역 중 상태·버튼 비활성·중복 처리 방지를 유지한다', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
      expect(h.translator.calls, hasLength(1));

      await inactiveThenResumed(tester);

      expect(h.permissions.checkCount, 1);
      expect(h.camera.createdCameraIds, hasLength(1));
      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(find.text(_translatingMessage), findsWidgets);
      expect(buttonWithLabel(tester, _retakeButton).enabled, isFalse);
      expect(buttonWithLabel(tester, _repickButton).enabled, isFalse);

      // 비활성 버튼은 갤러리를 열지 않고, 처리 중 새 처리 요청은 막힌다.
      await tapAndFlush(tester, find.text(_repickButton));
      expect(h.pickCount, 0);
      await notifierOf(tester).processImage('/other.jpg');
      expect(h.ocr.lineCallCount, 1);
      expect(h.ocr.textCallCount, 0);

      h.translator.calls.single.complete('안녕');
      await flush(tester);
      expect(buttonWithLabel(tester, _retakeButton).enabled, isTrue);

      await unmount(tester);
    });

    testWidgets('번역 완료 뒤 inactive→resumed: 결과를 그대로 보여 준다', (tester) async {
      final h = await pumpScreen(tester);
      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
      h.translator.calls.single.complete('안녕');
      await flush(tester);

      await inactiveThenResumed(tester);
      await backgroundRoundTrip(tester);

      expect(h.permissions.checkCount, 1);
      expect(h.camera.createdCameraIds, hasLength(1));
      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(buttonWithLabel(tester, _retakeButton).enabled, isTrue);

      // 다시 촬영하면 그때 권한을 확인하고 카메라를 준비한다.
      await tapAndFlush(tester, find.text(_retakeButton));
      expect(h.permissions.checkCount, 2);
      expect(h.camera.createdCameraIds, hasLength(2));
      expectCameraReadyView();

      await unmount(tester);
    });

    testWidgets('인식 실패 결과에서 inactive→resumed: 실패 안내를 그대로 보여 준다', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      h.ocr.linesResult = (lines: const <String>[], frameApplied: true);
      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
      expect(find.text(_emptyInFrameMessage), findsOneWidget);

      await inactiveThenResumed(tester);

      expect(h.permissions.checkCount, 1);
      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(find.text(_emptyInFrameMessage), findsOneWidget);

      await unmount(tester);
    });
  });

  group('C. 권한 대화상자', () {
    testWidgets('요청 중 inactive→resumed: 돌아올 때 확인을 건너뛰고 요청 결과로 카메라를 한 번 준비한다', (
      tester,
    ) async {
      final h = await pumpScreen(
        tester,
        checkResult: _denied,
        requestResult: _granted,
      );
      final requestGate = Completer<void>();
      h.permissions.requestGate = requestGate;

      await tapAndFlush(tester, find.text('접근 권한 허용'));
      expect(h.permissions.requestCount, 1);

      // 대화상자가 떠서 inactive, 사용자가 허용하고 닫아 resumed. 요청 결과는 그 뒤에 도착한다.
      h.permissions.checkResult = _granted;
      await inactiveThenResumed(tester);
      expect(h.permissions.checkCount, 1);
      expect(h.camera.createdCameraIds, isEmpty);

      requestGate.complete();
      await flush(tester);

      expect(h.camera.createdCameraIds, hasLength(1));
      expectCameraReadyView();

      await unmount(tester);
    });

    testWidgets('요청 중 inactive→resumed 뒤 요청 결과가 거부면 거부 안내만 보여 준다', (
      tester,
    ) async {
      final h = await pumpScreen(
        tester,
        checkResult: _denied,
        requestResult: _denied,
      );
      final requestGate = Completer<void>();
      h.permissions.requestGate = requestGate;

      await tapAndFlush(tester, find.text('접근 권한 허용'));
      await inactiveThenResumed(tester);
      requestGate.complete();
      await flush(tester);

      expect(h.permissions.checkCount, 1);
      expect(h.camera.createdCameraIds, isEmpty);
      expect(find.text('카메라 권한이 허용되지 않았습니다'), findsOneWidget);
      expect(find.byType(InitialCameraPermissionView), findsNothing);

      await unmount(tester);
    });
  });

  group('D. 다시 촬영 권한 조회', () {
    Future<_Harness> resultScreen(WidgetTester tester) async {
      final h = await pumpScreen(tester);
      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
      h.translator.calls.single.complete('안녕');
      await flush(tester);
      expect(h.permissions.checkCount, 1);
      return h;
    }

    testWidgets('허용이면 권한을 한 번만 조회하고 카메라를 준비한다', (tester) async {
      final h = await resultScreen(tester);

      await tapAndFlush(tester, find.text(_retakeButton));

      expect(h.permissions.checkCount, 2);
      expectCameraReadyView();

      await unmount(tester);
    });

    testWidgets('거부로 바뀌었으면 권한을 한 번만 조회하고 첫 권한 안내를 보여 준다', (tester) async {
      final h = await resultScreen(tester);
      h.permissions.checkResult = _denied;

      await tapAndFlush(tester, find.text(_retakeButton));

      expect(h.permissions.checkCount, 2);
      expect(find.byType(InitialCameraPermissionView), findsOneWidget);

      await unmount(tester);
    });
  });

  group('A. 촬영 시간 제한', () {
    // 같은 컨트롤러에서의 중복 촬영 차단(시간 제한 뒤 실제 촬영이 끝날 때까지)은 화면에서는 닿지 않는다
    // (시간 제한 뒤 실패 화면이 되고, 다시 촬영하면 새 컨트롤러를 만든다). 카메라 단위 테스트가 다룬다.
    testWidgets(
      '시간 제한 뒤 다시 촬영으로 새 카메라가 준비되면, 이전 촬영이 끝나지 않아도 셔터가 켜지고 새 카메라로 찍는다',
      (tester) async {
        final oldGate = Completer<void>();
        final camera = FakeCameraPlatform()..takePictureGate = oldGate;
        final h = await pumpScreen(tester, camera: camera);
        final oldId = camera.lastCameraId;

        await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
        await tester.pump(TranslationCamera.captureTimeout);
        await flush(tester);
        // 시간 제한에 걸린 첫 촬영은 실패로 알린다.
        expect(find.text(_captureFailedMessage), findsOneWidget);

        // 버그 수정(촬영 중 상태를 컨트롤러별로): 예전에는 이전 컨트롤러의 촬영이 끝나지 않으면 새 컨트롤러가
        // 준비돼도 셔터가 계속 비활성이었다. 이제 새 컨트롤러 기준으로 셔터가 켜진다.
        await tapAndFlush(tester, find.text(_retakeButton));
        expectCameraReadyView();
        final newId = camera.lastCameraId;
        expect(newId, isNot(oldId));
        final semantics = tester.ensureSemantics();
        expect(
          tester.getSemantics(find.bySemanticsLabel('사진 찍기')),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
        );

        final newGate = Completer<void>();
        camera.takePictureGate = newGate;
        await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
        expect(camera.takePictureCameraIds, [oldId, newId]);
        expect(
          tester.getSemantics(find.bySemanticsLabel('사진 찍는 중')),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
        );

        // 이전 촬영이 늦게 끝나도 새 촬영은 계속 진행 중이고, 이전 결과는 쓰지 않는다.
        oldGate.complete();
        await flush(tester);
        expect(
          tester.getSemantics(find.bySemanticsLabel('사진 찍는 중')),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
        );
        expect(find.byType(TranslationResultView), findsNothing);
        expect(find.text(_captureFailedMessage), findsNothing);
        expect(h.ocr.lineCallCount, 0);
        semantics.dispose();

        // 새 촬영이 끝나야 인식·번역으로 넘어간다.
        camera.takePictureGate = null;
        newGate.complete();
        await flush(tester);
        expect(h.ocr.lineCallCount, 1);
        expect(h.translator.calls, hasLength(1));
        expect(find.byType(TranslationResultView), findsOneWidget);

        await unmount(tester);
      },
    );
  });

  group('B. 늦게 온 권한 거부 응답', () {
    // 결과 화면 → 다시 촬영(이전 카메라가 아직 준비된 채 카메라 대기 화면) → 권한 확인이 늦는 사이
    // 갤러리로 사진을 고른다.
    Future<(_Harness, Completer<void>)> galleryDuringLateCheck(
      WidgetTester tester,
    ) async {
      final h = await pumpScreen(tester);
      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
      h.translator.calls.single.complete('안녕');
      await flush(tester);

      final checkGate = Completer<void>();
      h.permissions
        ..checkResult = _denied
        ..checkGate = checkGate;
      await tapAndFlush(tester, find.text(_retakeButton));
      expect(h.permissions.checkCount, 2);

      h.pickedPath = '/fake/gallery/menu.jpg';
      await tapAndFlush(tester, find.byTooltip('갤러리에서 사진 고르기'));
      expect(h.ocr.textCallCount, 1);
      expect(h.translator.calls, hasLength(2));
      return (h, checkGate);
    }

    testWidgets('번역 중에 거부 응답이 와도 번역 중 상태와 버튼 비활성을 유지한다', (tester) async {
      final (h, checkGate) = await galleryDuringLateCheck(tester);

      checkGate.complete();
      await flush(tester);

      expect(find.byType(InitialCameraPermissionView), findsNothing);
      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(find.text(_translatingMessage), findsWidgets);
      expect(stateOf(tester).status, TranslationStatus.translating);
      expect(buttonWithLabel(tester, _retakeButton).enabled, isFalse);
      expect(buttonWithLabel(tester, _repickButton).enabled, isFalse);

      h.translator.calls.last.complete('안녕');
      await flush(tester);
      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(buttonWithLabel(tester, _retakeButton).enabled, isTrue);

      await unmount(tester);
    });

    testWidgets('번역이 끝난 뒤 거부 응답이 와도 결과를 그대로 보여 준다', (tester) async {
      final (h, checkGate) = await galleryDuringLateCheck(tester);
      h.translator.calls.last.complete('안녕');
      await flush(tester);

      checkGate.complete();
      await flush(tester);

      expect(find.byType(InitialCameraPermissionView), findsNothing);
      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      // 화면은 사진이 있어 결과를 보여 주더라도, 상태가 권한 안내로 덮이면 안 된다.
      expect(stateOf(tester).status, TranslationStatus.completed);
      expect(buttonWithLabel(tester, _retakeButton).enabled, isTrue);

      // 다시 촬영하면 그때 권한을 다시 확인해 권한 안내를 보여 준다.
      h.permissions.checkGate = null;
      await tapAndFlush(tester, find.text(_retakeButton));
      expect(h.permissions.checkCount, 3);
      expect(find.byType(InitialCameraPermissionView), findsOneWidget);

      await unmount(tester);
    });
  });
}
