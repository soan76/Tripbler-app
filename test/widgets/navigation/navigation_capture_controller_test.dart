import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/navigation/navigation_capture_controller.dart';

void _noop() {}

void _other() {}

void main() {
  group('NavigationCaptureController', () {
    test('등록하면 촬영 동작과 촬영 중 여부를 알리고 해제하면 비운다', () {
      final controller = NavigationCaptureController();
      final owner = Object();

      controller.register(owner, _noop, busy: true);
      expect(controller.action.value, same(_noop));
      expect(controller.busy.value, isTrue);

      controller.unregister(owner);
      expect(controller.action.value, isNull);
      expect(controller.busy.value, isFalse);
      controller.dispose();
    });

    test('촬영 화면 여부를 등록 인자대로 알리고, 빠뜨리거나 해제하면 false다', () {
      final controller = NavigationCaptureController();
      final owner = Object();
      var notified = 0;
      controller.cameraScreen.addListener(() => notified++);

      controller.register(owner, null, cameraScreen: true);
      expect(controller.cameraScreen.value, isTrue);
      controller.register(owner, null, cameraScreen: true);
      expect(notified, 1);

      controller.register(owner, _noop);
      expect(controller.cameraScreen.value, isFalse);

      controller.register(owner, null, cameraScreen: true);
      controller.unregister(Object());
      expect(controller.cameraScreen.value, isTrue);
      controller.unregister(owner);
      expect(controller.cameraScreen.value, isFalse);
      controller.dispose();
      expect(
        () => controller.register(owner, null, cameraScreen: true),
        returnsNormally,
      );
    });

    test('다른 소유자의 해제는 무시한다', () {
      final controller = NavigationCaptureController();
      final first = Object();
      final second = Object();

      controller.register(first, _noop, busy: true);
      controller.register(second, _other, busy: true);
      controller.unregister(first);

      expect(controller.action.value, same(_other));
      expect(controller.busy.value, isTrue);
      controller.dispose();
    });

    test('같은 동작·같은 상태로 다시 등록하면 알리지 않는다', () {
      final controller = NavigationCaptureController();
      final owner = Object();
      var notified = 0;
      controller.register(owner, _noop);
      controller.action.addListener(() => notified++);
      controller.busy.addListener(() => notified++);

      controller.register(owner, _noop);
      expect(notified, 0);

      controller.register(owner, _noop, busy: true);
      expect(notified, 1);
      controller.dispose();
    });

    test('정리한 뒤의 등록·해제는 무시한다', () {
      final controller = NavigationCaptureController();
      final owner = Object();
      controller.dispose();

      expect(
        () => controller.register(owner, _noop, busy: true),
        returnsNormally,
      );
      expect(() => controller.unregister(owner), returnsNormally);
    });
  });

  group('NavigationCaptureBinding', () {
    Widget binding(
      NavigationCaptureController? controller, {
      VoidCallback? onCapture,
      bool busy = false,
      bool cameraScreen = false,
    }) {
      return NavigationCaptureBinding(
        controller: controller,
        onCapture: onCapture,
        busy: busy,
        cameraScreen: cameraScreen,
        child: const SizedBox(),
      );
    }

    testWidgets('build 뒤 프레임에 등록하고 바뀐 값을 다시 등록한다', (tester) async {
      final controller = NavigationCaptureController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(binding(controller, onCapture: _noop));
      expect(controller.action.value, same(_noop));
      expect(controller.busy.value, isFalse);

      await tester.pumpWidget(binding(controller, busy: true));
      expect(controller.action.value, isNull);
      expect(controller.busy.value, isTrue);
    });

    testWidgets('촬영 화면 여부를 전달하고 화면이 사라지면 false로 내린다', (tester) async {
      final controller = NavigationCaptureController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(binding(controller, cameraScreen: true));
      expect(controller.cameraScreen.value, isTrue);
      await tester.pumpWidget(binding(controller));
      expect(controller.cameraScreen.value, isFalse);
      await tester.pumpWidget(binding(controller, cameraScreen: true));
      expect(controller.cameraScreen.value, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(controller.cameraScreen.value, isFalse);
    });

    testWidgets('화면이 사라지면 해제해 촬영 중 표시가 남지 않는다', (tester) async {
      final controller = NavigationCaptureController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        binding(controller, onCapture: _noop, busy: true),
      );
      expect(controller.busy.value, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(controller.action.value, isNull);
      expect(controller.busy.value, isFalse);
    });

    testWidgets('컨트롤러가 바뀌면 이전 컨트롤러에서 해제한다', (tester) async {
      final first = NavigationCaptureController();
      final second = NavigationCaptureController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await tester.pumpWidget(binding(first, onCapture: _noop, busy: true));
      await tester.pumpWidget(binding(second, onCapture: _noop));
      await tester.pump();

      expect(first.action.value, isNull);
      expect(first.busy.value, isFalse);
      expect(second.action.value, same(_noop));
    });

    testWidgets('컨트롤러를 먼저 정리해도 화면 제거 때 오류가 없다', (tester) async {
      final controller = NavigationCaptureController();

      await tester.pumpWidget(binding(controller, onCapture: _noop));
      controller.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
