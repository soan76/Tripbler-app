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
import 'package:tripbler/widgets/translation/translation_camera_preview_card.dart';
import 'package:tripbler/widgets/translation/translation_header.dart';
import 'package:tripbler/widgets/translation/translation_result_view.dart';

import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_camera_platform.dart';

// 번역 화면(TranslationScreen) 리팩터링 전 기준 테스트.
//
// 지금 동작을 그대로 기록한다. 내부 private 이름 대신 화면 문구·버튼·공개 위젯 타입과
// 플랫폼 호출 기록(권한 채널, 가짜 카메라 플랫폼, 가짜 OCR·번역 서비스)으로 확인한다.

// permission_handler 상태 값(PermissionStatusValue.value).
const int _denied = 0;
const int _granted = 1;
const int _restricted = 2;
const int _permanentlyDenied = 4;

// Permission.camera.value
const int _cameraPermission = 1;

const MethodChannel _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);
const MethodChannel _imagePickerChannel = MethodChannel(
  'plugins.flutter.io/image_picker',
);

// 화면 문구
const String _initialPermissionTitle = '번역을 위해 촬영 권한이 필요합니다';
const String _initialPermissionButton = '접근 권한 허용';
const String _deniedTitle = '카메라 권한이 허용되지 않았습니다';
const String _deniedButton = '다시 권한 요청';
const String _blockedTitle = '설정에서 카메라 권한을 허용해 주세요';
const String _blockedButton = '앱 설정 열기';
const String _noCameraMessage = '카메라를 사용할 수 없습니다.\n기기의 카메라 상태를 확인해 주세요.';
const String _noBackCameraMessage = '사용 가능한 후면 카메라가 없습니다.';
const String _cameraStartFailedMessage =
    '카메라를 시작할 수 없습니다.\n카메라 상태를 확인한 뒤 다시 시도해 주세요.';
const String _retryButton = '다시 시도';
const String _privacyNote = '사진 속 글자는 기기에서 읽어요. 서버에는 읽은 글자만 보내고 사진은 보내지 않아요.';
const String _captureFailedMessage = '사진을 촬영하지 못했습니다.\n다시 시도해 주세요.';
const String _flashUnavailableMessage = '이 기기에서는 플래시를 사용할 수 없습니다.';
const String _retakeButton = '다시 촬영';
const String _repickButton = '다시 선택';

// 카메라 미리보기 카드 버튼 툴팁
const String _flashOnTooltip = '플래시 켜기';
const String _flashOffTooltip = '플래시 끄기';
const String _galleryTooltip = '갤러리에서 사진 고르기';
const String _cameraRetryTooltip = '카메라 다시 켜기';
const String _shutterTooltip = '사진 찍기';

/// 권한 채널 흉내. 상태 확인·요청 결과를 정하고 호출 횟수를 센다.
class _PermissionChannelFake {
  int checkResult = _denied;
  int requestResult = _denied;

  int checkCount = 0;
  int requestCount = 0;
  int openSettingsCount = 0;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
        expect(call.arguments, _cameraPermission);
        checkCount++;
        return checkResult;
      case 'requestPermissions':
        expect(call.arguments, <int>[_cameraPermission]);
        requestCount++;
        return <int, int>{_cameraPermission: requestResult};
      case 'openAppSettings':
        openSettingsCount++;
        return true;
    }
    return null;
  }
}

/// 갤러리(image_picker) 채널 흉내. [pickedPath]가 null이면 고르기를 취소한 것과 같다.
class _ImagePickerChannelFake {
  String? pickedPath;
  final List<Map<Object?, Object?>> pickCalls = <Map<Object?, Object?>>[];

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'pickImage') {
      pickCalls.add(Map<Object?, Object?>.from(call.arguments as Map));
      return pickedPath;
    }
    return null;
  }
}

/// 글자 인식 호출 인자를 기록하는 가짜 OCR.
class _FakeOcrService extends OcrService {
  final List<
    ({
      String imagePath,
      String sourceLanguageCode,
      bool onlyInCaptureFrame,
      double? cameraPreviewAspect,
    })
  >
  lineCalls = [];
  final List<({String imagePath, String sourceLanguageCode})> textCalls = [];

  CaptureFrameLines linesResult = (
    lines: const <String>['hello'],
    frameApplied: true,
  );
  String textResult = 'hello';

  @override
  Future<CaptureFrameLines> recognizeLines({
    required String imagePath,
    required String sourceLanguageCode,
    bool onlyInCaptureFrame = false,
    double? cameraPreviewAspect,
  }) async {
    lineCalls.add((
      imagePath: imagePath,
      sourceLanguageCode: sourceLanguageCode,
      onlyInCaptureFrame: onlyInCaptureFrame,
      cameraPreviewAspect: cameraPreviewAspect,
    ));
    return linesResult;
  }

  @override
  Future<String> recognizeText({
    required String imagePath,
    required String sourceLanguageCode,
  }) async {
    textCalls.add((
      imagePath: imagePath,
      sourceLanguageCode: sourceLanguageCode,
    ));
    return textResult;
  }
}

/// 요청마다 Completer를 만들어 테스트가 번역 응답 시점을 정한다.
class _FakeTranslationService extends TranslationService {
  final List<({String text, Completer<String> completer})> calls = [];

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) {
    final completer = Completer<String>();
    calls.add((text: text, completer: completer));
    return completer.future;
  }
}

class _Harness {
  _Harness({
    required this.permissions,
    required this.camera,
    required this.ocr,
    required this.translator,
    required this.imagePicker,
  });

  final _PermissionChannelFake permissions;
  final FakeCameraPlatform camera;
  final _FakeOcrService ocr;
  final _FakeTranslationService translator;
  final _ImagePickerChannelFake imagePicker;
}

void main() {
  late CameraPlatform originalCameraPlatform;

  setUp(() {
    originalCameraPlatform = CameraPlatform.instance;
  });

  tearDown(() {
    CameraPlatform.instance = originalCameraPlatform;
  });

  /// 마이크로태스크(채널 응답, 카메라 초기화)를 여러 번 흘려 보낸다.
  /// 로딩 표시처럼 끝나지 않는 애니메이션이 있어 pumpAndSettle 대신 쓴다.
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  Future<_Harness> pumpScreen(
    WidgetTester tester, {
    int checkResult = _denied,
    int requestResult = _denied,
    FakeCameraPlatform? camera,
  }) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final permissions = _PermissionChannelFake()
      ..checkResult = checkResult
      ..requestResult = requestResult;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_permissionChannel, permissions.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(_permissionChannel, null),
    );

    final imagePicker = _ImagePickerChannelFake();
    messenger.setMockMethodCallHandler(_imagePickerChannel, imagePicker.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(_imagePickerChannel, null),
    );

    final fakeCamera = camera ?? FakeCameraPlatform();
    CameraPlatform.instance = fakeCamera;

    final ocr = _FakeOcrService();
    final translator = _FakeTranslationService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 로그아웃 상태: 카메라 촬영은 프레임 안 줄 인식 + 통번역을 쓴다.
          authProvider.overrideWith(
            () => FakeAuthNotifier(initiallySignedIn: false),
          ),
          ocrServiceProvider.overrideWithValue(ocr),
          translationServiceProvider.overrideWithValue(translator),
        ],
        child: const MaterialApp(home: Scaffold(body: TranslationScreen())),
      ),
    );
    // 첫 프레임 뒤 권한 확인이 시작된다.
    await flush(tester);

    return _Harness(
      permissions: permissions,
      camera: fakeCamera,
      ocr: ocr,
      translator: translator,
      imagePicker: imagePicker,
    );
  }

  Future<void> tapAndFlush(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await flush(tester);
  }

  ButtonStyleButton buttonWithLabel(WidgetTester tester, String label) {
    return tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
  }

  void expectCameraReadyView() {
    expect(find.byType(TranslationHeader), findsOneWidget);
    expect(find.byType(TranslationCameraPreviewCard), findsOneWidget);
    expect(find.text(TranslationCameraPreviewCard.guideText), findsOneWidget);
    expect(find.text(_privacyNote), findsOneWidget);
    // 카메라가 준비되면 "카메라 준비 중" 표시가 없다.
    expect(find.bySemanticsLabel('카메라 준비 중'), findsNothing);
  }

  /// 화면 제거 뒤 남은 비동기 정리를 흘려 보내 타이머가 남지 않게 한다.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await flush(tester);
  }

  group('1~3. 카메라 권한', () {
    testWidgets('1. 들어올 때 권한이 거부(요청 전)면 첫 권한 안내 화면을 보여 준다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _denied);

      expect(h.permissions.checkCount, 1);
      expect(h.permissions.requestCount, 0);
      expect(find.byType(InitialCameraPermissionView), findsOneWidget);
      expect(find.text(_initialPermissionTitle), findsOneWidget);
      expect(find.text(_initialPermissionButton), findsOneWidget);
      // 권한이 없으면 카메라를 찾지 않는다.
      expect(h.camera.availableCamerasCallCount, 0);

      await unmount(tester);
    });

    testWidgets('2. 권한 요청 버튼 → 요청 결과 거부면 거부 안내와 다시 요청 버튼을 보여 준다', (
      tester,
    ) async {
      final h = await pumpScreen(
        tester,
        checkResult: _denied,
        requestResult: _denied,
      );

      await tapAndFlush(tester, find.text(_initialPermissionButton));

      expect(h.permissions.requestCount, 1);
      expect(find.text(_deniedTitle), findsOneWidget);
      expect(find.text(_deniedButton), findsOneWidget);
      expect(find.byType(InitialCameraPermissionView), findsNothing);

      // 다시 요청 버튼도 권한을 다시 요청한다.
      await tapAndFlush(tester, find.text(_deniedButton));
      expect(h.permissions.requestCount, 2);
      expect(find.text(_deniedTitle), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('2-1. 요청 결과 허용이면 카메라를 준비해 카메라 대기 화면을 보여 준다', (tester) async {
      final h = await pumpScreen(
        tester,
        checkResult: _denied,
        requestResult: _granted,
      );

      await tapAndFlush(tester, find.text(_initialPermissionButton));

      expect(h.permissions.requestCount, 1);
      expect(h.camera.createdCameraIds, hasLength(1));
      expectCameraReadyView();

      await unmount(tester);
    });

    testWidgets('2-2. 요청 거부 뒤 앱으로 돌아와 다시 확인해도 첫 안내가 아니라 거부 안내를 보여 준다', (
      tester,
    ) async {
      final h = await pumpScreen(
        tester,
        checkResult: _denied,
        requestResult: _denied,
      );

      await tapAndFlush(tester, find.text(_initialPermissionButton));
      expect(find.text(_deniedTitle), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);

      expect(h.permissions.checkCount, 2);
      expect(find.text(_deniedTitle), findsOneWidget);
      expect(find.byType(InitialCameraPermissionView), findsNothing);

      await unmount(tester);
    });

    testWidgets('3. 들어올 때 영구 거부면 설정 안내와 앱 설정 열기 버튼을 보여 준다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _permanentlyDenied);

      expect(find.text(_blockedTitle), findsOneWidget);
      expect(find.text(_blockedButton), findsOneWidget);

      await tapAndFlush(tester, find.text(_blockedButton));
      expect(h.permissions.openSettingsCount, 1);
      expect(h.permissions.requestCount, 0);

      await unmount(tester);
    });

    testWidgets('3-1. 들어올 때 제한(restricted)도 설정 안내를 보여 준다', (tester) async {
      await pumpScreen(tester, checkResult: _restricted);

      expect(find.text(_blockedTitle), findsOneWidget);
      expect(find.text(_blockedButton), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('3-2. 권한 요청 결과가 영구 거부면 설정 안내를 보여 준다', (tester) async {
      await pumpScreen(
        tester,
        checkResult: _denied,
        requestResult: _permanentlyDenied,
      );

      await tapAndFlush(tester, find.text(_initialPermissionButton));

      expect(find.text(_blockedTitle), findsOneWidget);
      expect(find.text(_blockedButton), findsOneWidget);

      await unmount(tester);
    });
  });

  group('4. 카메라를 쓸 수 없을 때', () {
    testWidgets('카메라가 하나도 없으면 사용할 수 없다는 안내를 보여 준다', (tester) async {
      final h = await pumpScreen(
        tester,
        checkResult: _granted,
        camera: FakeCameraPlatform(cameras: const <CameraDescription>[]),
      );

      expect(h.camera.availableCamerasCallCount, 1);
      expect(h.camera.createdCameraIds, isEmpty);
      expect(find.text(_noCameraMessage), findsOneWidget);
      expect(find.text(_retryButton), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('전면 카메라만 있으면 후면 카메라가 없다는 안내를 보여 준다', (tester) async {
      final h = await pumpScreen(
        tester,
        checkResult: _granted,
        camera: FakeCameraPlatform(
          cameras: const <CameraDescription>[FakeCameraPlatform.frontCamera],
        ),
      );

      expect(h.camera.createdCameraIds, isEmpty);
      expect(find.text(_noBackCameraMessage), findsOneWidget);
      expect(find.text(_retryButton), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('초기화 중 예외가 나면 시작할 수 없다는 안내와 다시 시도 버튼을 보여 준다', (tester) async {
      final camera = FakeCameraPlatform()..initializeError = fakeCameraError();
      final h = await pumpScreen(tester, checkResult: _granted, camera: camera);

      expect(find.text(_cameraStartFailedMessage), findsOneWidget);
      expect(find.text(_retryButton), findsOneWidget);
      // 실패한 컨트롤러는 정리한다.
      expect(h.camera.disposedCameraIds, contains(h.camera.lastCameraId));

      // 다시 시도: 권한을 다시 확인하고 카메라를 다시 준비한다.
      camera.initializeError = null;
      await tapAndFlush(tester, find.text(_retryButton));

      expect(h.permissions.checkCount, 2);
      expect(h.camera.createdCameraIds, hasLength(2));
      expectCameraReadyView();

      await unmount(tester);
    });
  });

  group('5. 카메라 대기 화면', () {
    testWidgets('권한 허용 + 초기화 성공이면 언어 막대·미리보기 카드·안내 문구·버튼을 보여 준다', (
      tester,
    ) async {
      final h = await pumpScreen(tester, checkResult: _granted);

      expect(h.permissions.requestCount, 0);
      // 후면 카메라를 high 해상도, 소리 없이 만든다.
      expect(
        h.camera.createdDescriptions.single.lensDirection,
        CameraLensDirection.back,
      );
      expect(
        h.camera.createdSettings.single.resolutionPreset,
        ResolutionPreset.high,
      );
      expect(h.camera.createdSettings.single.enableAudio, isFalse);
      expect(h.camera.initializedCameraIds, [h.camera.lastCameraId]);

      expectCameraReadyView();
      expect(find.byTooltip(_flashOnTooltip), findsOneWidget);
      expect(find.byIcon(Icons.flash_off), findsOneWidget);
      expect(find.byTooltip(_galleryTooltip), findsOneWidget);
      expect(find.byTooltip(_cameraRetryTooltip), findsOneWidget);
      expect(find.byTooltip(_shutterTooltip), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('카메라 다시 켜기 버튼은 권한을 다시 확인하고 카메라를 새로 만든다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);
      final firstId = h.camera.lastCameraId;

      await tapAndFlush(tester, find.byTooltip(_cameraRetryTooltip));

      expect(h.permissions.checkCount, 2);
      expect(h.camera.disposedCameraIds, contains(firstId));
      expect(h.camera.createdCameraIds, hasLength(2));
      expectCameraReadyView();

      await unmount(tester);
    });
  });

  group('6. 촬영', () {
    testWidgets('촬영하면 사진 경로·카메라 출처·미리보기 비율로 글자를 읽는다', (tester) async {
      final camera = FakeCameraPlatform(previewSize: const Size(1920, 1080))
        ..picturePath = '/fake/camera/menu.jpg';
      final h = await pumpScreen(tester, checkResult: _granted, camera: camera);

      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));

      expect(h.camera.takePictureCameraIds, [h.camera.lastCameraId]);
      // 카메라 촬영 + 미리보기 비율이 있으면 프레임 안 줄 인식을 쓴다.
      final call = h.ocr.lineCalls.single;
      expect(call.imagePath, '/fake/camera/menu.jpg');
      expect(call.sourceLanguageCode, 'auto');
      expect(call.onlyInCaptureFrame, isTrue);
      expect(call.cameraPreviewAspect, closeTo(1080 / 1920, 1e-9));
      expect(h.ocr.textCalls, isEmpty);
      // 로그아웃 상태라 읽은 줄을 이어 통번역을 요청한다.
      expect(h.translator.calls.single.text, 'hello');

      h.translator.calls.single.completer.complete('안녕');
      await flush(tester);
      expect(find.byType(TranslationResultView), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('촬영에 실패하면 촬영 실패 안내를 보여 준다', (tester) async {
      final camera = FakeCameraPlatform()..takePictureError = fakeCameraError();
      final h = await pumpScreen(tester, checkResult: _granted, camera: camera);

      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));

      expect(h.camera.takePictureCameraIds, hasLength(1));
      expect(h.ocr.lineCalls, isEmpty);
      expect(h.ocr.textCalls, isEmpty);
      expect(find.text(_captureFailedMessage), findsOneWidget);
      expect(find.byType(TranslationResultView), findsOneWidget);

      await unmount(tester);
    });
  });

  group('7. 플래시', () {
    testWidgets('플래시를 켜면 아이콘과 툴팁이 켜짐으로 바뀌고, 다시 누르면 꺼진다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);

      await tapAndFlush(tester, find.byTooltip(_flashOnTooltip));

      expect(h.camera.flashModes, [FlashMode.torch]);
      expect(find.byTooltip(_flashOffTooltip), findsOneWidget);
      expect(find.byIcon(Icons.flash_on), findsOneWidget);

      await tapAndFlush(tester, find.byTooltip(_flashOffTooltip));

      expect(h.camera.flashModes, [FlashMode.torch, FlashMode.off]);
      expect(find.byTooltip(_flashOnTooltip), findsOneWidget);
      expect(find.byIcon(Icons.flash_off), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('플래시 변경이 실패하면 안내 SnackBar를 띄우고 꺼짐 상태를 유지한다', (tester) async {
      final camera = FakeCameraPlatform()
        ..setFlashModeError = fakeCameraError();
      final h = await pumpScreen(tester, checkResult: _granted, camera: camera);

      await tapAndFlush(tester, find.byTooltip(_flashOnTooltip));

      expect(h.camera.flashModes, [FlashMode.torch]);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(_flashUnavailableMessage), findsOneWidget);
      expect(find.byTooltip(_flashOnTooltip), findsOneWidget);
      expect(find.byIcon(Icons.flash_off), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('플래시를 켠 채 화면을 떠나면 플래시를 끈 뒤 카메라를 정리한다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);
      final cameraId = h.camera.lastCameraId;

      await tapAndFlush(tester, find.byTooltip(_flashOnTooltip));
      await unmount(tester);

      expect(h.camera.flashModes, [FlashMode.torch, FlashMode.off]);
      expect(h.camera.disposedCameraIds, [cameraId]);
    });
  });

  group('8. 앱 생명주기', () {
    tearDown(() {
      // 다음 테스트를 위해 앱 상태를 되돌린다.
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    });

    testWidgets('백그라운드로 가면 카메라를 정리하고, 돌아오면 권한을 다시 확인해 카메라를 다시 준비한다', (
      tester,
    ) async {
      final h = await pumpScreen(tester, checkResult: _granted);
      final firstId = h.camera.lastCameraId;
      expect(h.permissions.checkCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await flush(tester);

      expect(h.camera.disposedCameraIds, [firstId]);
      expect(h.permissions.checkCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);

      expect(h.permissions.checkCount, 2);
      expect(h.camera.createdCameraIds, hasLength(2));
      expectCameraReadyView();

      await unmount(tester);
    });

    testWidgets('돌아왔을 때 권한이 거부로 바뀌었으면 첫 권한 안내를 보여 준다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await flush(tester);

      h.permissions.checkResult = _denied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester);

      expect(h.permissions.checkCount, 2);
      expect(h.camera.createdCameraIds, hasLength(1));
      expect(find.byType(InitialCameraPermissionView), findsOneWidget);

      await unmount(tester);
    });
  });

  group('9. 결과 화면', () {
    testWidgets('번역이 끝나기 전에는 다시 촬영·다시 선택이 비활성이고, 끝나면 활성이다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);

      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));

      expect(h.translator.calls, hasLength(1));
      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(find.text('번역하고 있습니다.'), findsWidgets);
      expect(buttonWithLabel(tester, _retakeButton).enabled, isFalse);
      expect(buttonWithLabel(tester, _repickButton).enabled, isFalse);

      h.translator.calls.single.completer.complete('안녕');
      await flush(tester);

      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(buttonWithLabel(tester, _retakeButton).enabled, isTrue);
      expect(buttonWithLabel(tester, _repickButton).enabled, isTrue);

      await unmount(tester);
    });
  });

  group('10. 다시 촬영', () {
    testWidgets('결과에서 다시 촬영하면 권한 확인 뒤 카메라를 다시 준비해 카메라 대기 화면으로 돌아간다', (
      tester,
    ) async {
      final h = await pumpScreen(tester, checkResult: _granted);
      final firstId = h.camera.lastCameraId;

      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
      h.translator.calls.single.completer.complete('안녕');
      await flush(tester);
      expect(find.byType(TranslationResultView), findsOneWidget);

      await tapAndFlush(tester, find.text(_retakeButton));

      expect(find.byType(TranslationResultView), findsNothing);
      expect(h.permissions.checkCount, 2);
      expect(h.camera.disposedCameraIds, contains(firstId));
      expect(h.camera.createdCameraIds, hasLength(2));
      expectCameraReadyView();

      await unmount(tester);
    });

    testWidgets('다시 촬영 때 권한이 거부로 바뀌었으면 첫 권한 안내를 보여 준다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);

      await tapAndFlush(tester, find.byTooltip(_shutterTooltip));
      h.translator.calls.single.completer.complete('안녕');
      await flush(tester);

      h.permissions.checkResult = _denied;
      await tapAndFlush(tester, find.text(_retakeButton));

      // 지금 코드는 다시 촬영에서 한 번, 권한 재확인에서 한 번 더 확인해 3번이 된다.
      // 확인 횟수를 줄이는 정리는 허용하도록 "다시 확인했는지"만 본다.
      expect(h.permissions.checkCount, greaterThanOrEqualTo(2));
      expect(h.camera.createdCameraIds, hasLength(1));
      expect(find.byType(InitialCameraPermissionView), findsOneWidget);

      await unmount(tester);
    });
  });

  group('11. 화면 제거', () {
    testWidgets('화면을 트리에서 빼면 카메라를 정리한다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);
      final cameraId = h.camera.lastCameraId;
      expect(h.camera.disposedCameraIds, isEmpty);

      await unmount(tester);

      expect(h.camera.disposedCameraIds, [cameraId]);
      // 플래시를 켜지 않았으면 플래시를 건드리지 않는다.
      expect(h.camera.flashModes, isEmpty);
    });
  });

  group('갤러리', () {
    testWidgets('갤러리에서 고른 사진은 프레임 없이 사진 전체 글자를 읽는다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);
      h.imagePicker.pickedPath = '/fake/gallery/menu.jpg';

      await tapAndFlush(tester, find.byTooltip(_galleryTooltip));

      final pick = h.imagePicker.pickCalls.single;
      expect(pick['source'], 1); // ImageSource.gallery
      expect(pick['imageQuality'], 95);
      // 로그아웃 + 갤러리 사진이라 전체 글자 인식을 쓴다.
      expect(h.ocr.lineCalls, isEmpty);
      expect(h.ocr.textCalls.single.imagePath, '/fake/gallery/menu.jpg');
      expect(h.translator.calls.single.text, 'hello');
      expect(h.camera.takePictureCameraIds, isEmpty);

      h.translator.calls.single.completer.complete('안녕');
      await flush(tester);
      expect(find.byType(TranslationResultView), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('갤러리 고르기를 취소하면 카메라 대기 화면을 유지한다', (tester) async {
      final h = await pumpScreen(tester, checkResult: _granted);
      h.imagePicker.pickedPath = null;

      await tapAndFlush(tester, find.byTooltip(_galleryTooltip));

      expect(h.imagePicker.pickCalls, hasLength(1));
      expect(h.ocr.lineCalls, isEmpty);
      expect(h.ocr.textCalls, isEmpty);
      expectCameraReadyView();

      await unmount(tester);
    });
  });
}
