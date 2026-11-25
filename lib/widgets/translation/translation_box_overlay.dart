import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/translation/photo_paragraphs.dart' show unreadableMarker;

part 'translation_box_layout.dart';

/// 덮어 그릴 번역 하나. [box]는 [TranslationBoxOverlay]를 그리는 영역의 좌표로 옮긴 원문 영역이고,
/// [lineCount]는 원문 줄 수(글자 크기·줄 간격을 정할 때 쓴다)다.
@immutable
class TranslationBox {
  const TranslationBox(
    this.box,
    this.lineCount,
    this.translated, {
    this.id,
    this.uncertain = false,
    this.fallback = false,
  });

  final Rect box;
  final int lineCount;
  final String translated;

  /// 누를 때 [TranslationBoxOverlay.onBoxTap]에 넘길 값. 없으면 눌러도 알리지 않는다.
  final String? id;

  /// 읽기·번역이 불확실한 번역이면 경고 표시를 붙인다.
  final bool uncertain;

  /// 사진 없이 글자만으로 번역했으면 안내 표시를 붙인다.
  final bool fallback;
}

/// 번역을 원문 자리에 흰 상자로 덮어 그린다. 상자는 원문 영역을 가리고, 번역 글자는 그 상자 크기에 맞춘다.
///
/// 좌표 변환(사진 → 화면)은 부르는 쪽이 맡는다. [onBoxTap]이 있으면 배치된 상자를 누를 때 그 상자의
/// [TranslationBox.id]를 알린다. 없으면 터치를 받지 않는다.
class TranslationBoxOverlay extends StatefulWidget {
  const TranslationBoxOverlay({super.key, required this.boxes, this.onBoxTap});

  /// 그릴 번역. 같은 결과면 같은 목록 객체를 넘겨야 다시 배치하지 않는다.
  final List<TranslationBox> boxes;

  /// 배치된 상자를 눌렀을 때 그 상자의 id를 받는다.
  final ValueChanged<String>? onBoxTap;

  /// 불확실·대체 번역 표시 문구(낭독기용).
  static const String uncertainLabel = '불확실한 번역';
  static const String fallbackLabel = '글자만으로 번역';

  /// 덮어 그리는 번역 글자의 최소 크기(글자 배율 1 기준). 원문이 이보다 작아도 이 크기로 읽히게 그린다.
  static const double minFontSize = 12;

  // 시스템 글자 크기를 따르되, 덮어 그린 번역이 이웃 줄을 지나치게 가리지 않도록 상한을 둔다.
  static const double _maxTextScale = 1.5;

  @override
  State<TranslationBoxOverlay> createState() => _TranslationBoxOverlayState();
}

/// 배치 입력. 번역 목록은 같은 결과면 같은 객체라 `==`(동일성)로 바뀜을 안다.
typedef _LayoutKey = ({
  List<TranslationBox> boxes,
  Size size,
  TextStyle style,
  double minFontSize,
  TextDirection textDirection,
});

class _TranslationBoxOverlayState extends State<TranslationBoxOverlay> {
  _LayoutKey? _layoutKey;
  _TranslationBoxLayout? _layout;

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  // 결과·크기·글자 모양이 바뀔 때만 다시 배치한다(다시 그리기만 할 때는 저장한 배치를 쓴다).
  _TranslationBoxLayout _layoutFor(_LayoutKey key) {
    final current = _layout;
    if (current != null && _layoutKey == key) {
      return current;
    }
    current?.dispose();
    final layout = _TranslationBoxLayout.compute(
      lines: key.boxes,
      size: key.size,
      baseStyle: key.style,
      minFontSize: key.minFontSize,
      textDirection: key.textDirection,
    );
    _layoutKey = key;
    _layout = layout;
    return layout;
  }

  @override
  Widget build(BuildContext context) {
    final boxes = widget.boxes;
    if (boxes.isEmpty) {
      return const SizedBox.shrink();
    }

    // 글자 모양(글꼴·굵기)은 테마를 따르고, 크기는 원문 상자에 맞춰 정한다.
    final baseStyle =
        Theme.of(context).textTheme.titleMedium ?? const TextStyle();
    final minSize = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: TranslationBoxOverlay._maxTextScale)
        .scale(TranslationBoxOverlay.minFontSize);
    final textDirection = Directionality.of(context);

    final onBoxTap = widget.onBoxTap;
    return IgnorePointer(
      ignoring: onBoxTap == null,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final layout = _layoutFor((
              boxes: boxes,
              size: size,
              style: baseStyle,
              minFontSize: minSize,
              textDirection: textDirection,
            ));
            return Semantics(
              label: '번역\n${boxes.map(_semanticsLine).join('\n')}',
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: onBoxTap == null
                    ? null
                    : (details) {
                        final id = layout.idAt(details.localPosition);
                        if (id != null) {
                          onBoxTap(id);
                        }
                      },
                child: CustomPaint(
                  size: size,
                  painter: _TranslationBoxPainter(layout),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _semanticsLine(TranslationBox box) {
  return [
    box.translated,
    if (box.uncertain) TranslationBoxOverlay.uncertainLabel,
    if (box.fallback) TranslationBoxOverlay.fallbackLabel,
  ].join(', ');
}

/// 테스트용: 번역 글자 배치를 계산한 횟수.
@visibleForTesting
int debugTranslationBoxLayoutCount = 0;

/// 테스트용: 마지막으로 배치한 배경 상자(그리는 영역 좌표). 단위끼리 겹치지 않는지 확인한다.
@visibleForTesting
List<Rect> debugTranslationBoxes = const <Rect>[];
