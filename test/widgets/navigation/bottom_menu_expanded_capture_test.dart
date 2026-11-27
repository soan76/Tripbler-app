import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show TranslationState;
import 'package:tripbler/screens/main_screen.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';
import 'package:tripbler/widgets/navigation/navigation_capture_controller.dart';
import 'package:tripbler/widgets/translation/photo/photo_capture_view.dart';
import 'package:tripbler/widgets/translation/photo/photo_language_pill.dart';

import '../../helpers/bottom_menu_background.dart';

// 확장 메뉴(6개 버튼)와 번역 카메라 화면의 겹침: docs/mockups/bottom-nav.md 10-8절 마지막 조건.
// 위 "Tripbler"·언어 막대와 겹치지 않고, 아래 갤러리·플래시는 펼치는 동안 흐려지고 눌리지 않는다.

const _translation = 2;
const _sizes = [Size(360, 740), Size(320, 640)];
final _current = find.byKey(const ValueKey('bottom-menu-current'));
Finder _tab(int index) => find.byKey(ValueKey('bottom-menu-tab-$index'));
final _gallery = find.byTooltip(PhotoCaptureView.galleryTooltip);
final _flash = find.byTooltip(PhotoCaptureView.flashOnTooltip);

class _Calls {
  int gallery = 0, flash = 0, capture = 0;
}

/// 메인 화면처럼 촬영 화면 위에 화면 전체를 받는 하단 메뉴를 겹쳐 그린다.
Future<(NavigationCaptureController, _Calls)> _mount(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = NavigationCaptureController();
  addTearDown(controller.dispose);
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: PhotoCaptureView(
                  navigationCapture: controller,
                  cameraController: null,
                  isCameraReady: true,
                  isFlashOn: false,
                  isCapturing: false,
                  sourceLanguageCode: 'auto',
                  targetLanguageCode: 'ko',
                  languages: const TranslationState().languages,
                  onSourceLanguageChanged: (_) {},
                  onTargetLanguageChanged: (_) {},
                  onToggleFlash: () => calls.flash++,
                  onCapture: () => calls.capture++,
                  onPickFromGallery: () => calls.gallery++,
                ),
              ),
              Positioned.fill(
                child: BottomTabBar(
                  tabs: MainScreen.tabs,
                  selectedIndex: _translation,
                  isHomeSelected: false,
                  onTabTap: (_) {},
                  onHomeTap: () {},
                  onCurrentScreenTap: () => calls.capture++,
                  isCaptureScreen: true,
                  alwaysShowIcon: true,
                  onExpansionChanged: (value) =>
                      controller.expansion.value = value,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (controller, calls);
}

Finder _controlsOf(Finder button) =>
    find.ancestor(of: button, matching: find.byType(NavigationCaptureControls));

double _opacity(WidgetTester tester, Finder button) => tester
    .widget<Opacity>(
      find.descendant(of: _controlsOf(button), matching: find.byType(Opacity)),
    )
    .opacity;

bool _ignoring(WidgetTester tester, Finder button) => tester
    .widget<IgnorePointer>(
      find
          .descendant(
            of: _controlsOf(button),
            matching: find.byType(IgnorePointer),
          )
          .first,
    )
    .ignoring;

void main() {
  testWidgets('펼친 6개 버튼은 위 Tripbler·언어 막대와 겹치지 않는다(360×740·320×640)', (
    tester,
  ) async {
    for (final size in _sizes) {
      for (final textScale in [1.0, 1.3]) {
        await _mount(tester, size, textScale: textScale);
        await tester.drag(_current, const Offset(0, -150));
        await tester.pumpAndSettle();
        expectBottomMenuBackgroundCoversArea(tester);

        final brand = tester.getRect(find.text(PhotoCaptureView.brand));
        final pill = tester.getRect(find.byType(PhotoLanguagePill));
        for (final index in [-1, 0, 1, 2, 3, 4]) {
          final rect = tester.getRect(_tab(index));
          final reason = '$index $size $textScale';
          expect(rect.overlaps(brand), isFalse, reason: reason);
          expect(rect.overlaps(pill), isFalse, reason: reason);
          // 가장 높은 버튼(일정·면세)도 언어 막대 아래에 있다.
          expect(rect.top, greaterThan(pill.bottom), reason: reason);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('아래 갤러리·플래시는 펼치는 동안 흐려지고 눌리지 않으며, 접히면 돌아온다', (tester) async {
    for (final size in _sizes) {
      final (controller, calls) = await _mount(tester, size);
      // 현재 화면 버튼 상태: 갤러리·플래시는 메뉴 원과 겹치지 않고 누를 수 있다.
      final circle = tester.getRect(bottomMenuBackground);
      for (final button in [_gallery, _flash]) {
        expect(tester.getRect(button).overlaps(circle), isFalse);
        expect(_opacity(tester, button), 1);
        expect(_ignoring(tester, button), isFalse);
      }
      await tester.tap(_gallery);
      await tester.tap(_flash);
      await tester.pump();
      expect((calls.gallery, calls.flash, calls.capture), (1, 1, 0));

      // 끄는 도중(p 0.3)부터 흐려지고 눌리지 않는다.
      final gesture = await tester.startGesture(tester.getCenter(_current));
      await gesture.moveBy(const Offset(0, -45));
      await tester.pump();
      expect(controller.expansion.value, closeTo(.3, .001));
      for (final button in [_gallery, _flash]) {
        expect(_opacity(tester, button), closeTo(.7, .001), reason: '$size');
        expect(_ignoring(tester, button), isTrue, reason: '$size');
      }
      await gesture.moveBy(const Offset(0, -105));
      await gesture.up();
      await tester.pumpAndSettle();
      for (final button in [_gallery, _flash]) {
        expect(_opacity(tester, button), 0, reason: '$size');
        expect(_ignoring(tester, button), isTrue, reason: '$size');
      }
      // 펼친 동안 갤러리 자리를 누르면 갤러리가 아니라 메뉴 배경이 받아 현재 화면 버튼으로 접힌다.
      await tester.tapAt(tester.getCenter(_gallery));
      await tester.pumpAndSettle();
      expect((calls.gallery, calls.flash, calls.capture), (1, 1, 0));
      expect(controller.expansion.value, 0);
      expect(tester.getSize(bottomMenuBackground).width, 74);
      for (final button in [_gallery, _flash]) {
        expect(_opacity(tester, button), 1, reason: '$size');
        expect(_ignoring(tester, button), isFalse, reason: '$size');
      }
      await tester.tap(_gallery);
      await tester.pump();
      expect(calls.gallery, 2);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
