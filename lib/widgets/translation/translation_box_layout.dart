part of 'translation_box_overlay.dart';

// 번역 상자 배치(글자 크기·넓히기·말줄임)와 그리기. 위젯·터치는 translation_box_overlay.dart가 맡는다.

/// 배치를 마친 단위 하나: 배경 상자와 글자.
typedef _PlacedLine = ({
  RRect box,
  Offset textOffset,
  TextPainter text,
  String? id,
});

// 단위(문단·항목)마다 원문 영역을 가리고 번역을 그 안에 맞춰 배치한다. 라벨을 영역 위에 띄우지 않는다.
//
// 크기 규칙:
// 1. 원문 줄 높이의 80%에서 시작해, 원문 영역 폭으로 줄바꿈했을 때 영역 높이에 들어가는 가장 큰 글자 크기를
//    찾는다. 최소 크기 아래로는 줄이지 않는다.
// 2. 최소 크기에서도 넘치면 빈 곳으로만 넓힌다. 폭은 오른쪽으로 1.5배까지(옆 단위 앞·영역 안), 높이는 아래로
//    (아래 단위 바로 위·영역 안) 넓힌다. 다른 단위를 가리지 않는다.
// 3. 그래도 넘치면 들어가는 줄까지만 그리고 끝을 말줄임(…)으로 표시한다.
class _TranslationBoxLayout {
  _TranslationBoxLayout._(this.lines);

  final List<_PlacedLine> lines;

  /// [position]을 덮는 상자의 id. 나중에 그린(위에 있는) 상자를 먼저 본다.
  String? idAt(Offset position) {
    for (final line in lines.reversed) {
      if (line.id != null && line.box.outerRect.contains(position)) {
        return line.id;
      }
    }
    return null;
  }

  // 배경 안쪽 여백, 영역 가장자리 여백, 이웃 단위와의 간격.
  static const double _padding = 2;
  static const double _edge = 4;
  static const double _gap = 2;

  // 줄 간격(글자 크기 배율): 한 줄 항목, 여러 줄 문단.
  static const double _itemLineSpacing = 1.15;
  static const double _paragraphLineSpacing = 1.25;

  // 최소 크기에서도 넘칠 때 폭을 넓히는 최대 배율.
  static const double _maxWidthGrowth = 1.5;

  // 글자 크기 이진 탐색 정밀도(논리 픽셀).
  static const double _fontSizePrecision = 0.5;

  factory _TranslationBoxLayout.compute({
    required List<TranslationBox> lines,
    required Size size,
    required TextStyle baseStyle,
    required double minFontSize,
    required TextDirection textDirection,
  }) {
    debugTranslationBoxLayoutCount++;

    // 지금 배치하는 단위의 줄 간격. 한 줄 항목은 원문 줄 상자에 맞춰 좁게, 여러 줄 문단은 줄끼리 붙어 보이지
    // 않게 조금 넓힌다(원문 줄 높이의 80% 글자 × 1.25 = 원문 줄 간격).
    var lineSpacing = _itemLineSpacing;

    TextPainter layout(
      TranslationBox line,
      double fontSize, {
      required double maxWidth,
      int? maxLines,
    }) {
      return TextPainter(
        text: _spanFor(
          line,
          baseStyle.copyWith(
            color: _TranslationBoxPainter.textColor,
            fontSize: fontSize,
            height: lineSpacing,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
        textDirection: textDirection,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: math.max(0, maxWidth));
    }

    final rects = [for (final line in lines) line.box];
    final placed = <_PlacedLine>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final rect = rects[i];
      if (rect.width <= 1 || rect.height <= 1) {
        continue;
      }

      lineSpacing = line.lineCount > 1
          ? _paragraphLineSpacing
          : _itemLineSpacing;
      final innerWidth = rect.width - _padding * 2;
      final innerHeight = rect.height - _padding * 2;
      TextPainter? fitsAt(double fontSize) {
        final painter = layout(line, fontSize, maxWidth: innerWidth);
        if (painter.height <= innerHeight) {
          return painter;
        }
        painter.dispose();
        return null;
      }

      final lineHeight = rect.height / math.max(1, line.lineCount);
      final largest = math.max(lineHeight * 0.8, minFontSize);
      var text = fitsAt(largest);
      if (text == null && largest > minFontSize) {
        var best = fitsAt(minFontSize);
        if (best != null) {
          // 최소 크기는 들어가고 가장 큰 크기는 넘친다: 들어가는 가장 큰 크기를 이진 탐색한다.
          var low = minFontSize;
          var high = largest;
          while (high - low > _fontSizePrecision) {
            final middle = (low + high) / 2;
            final painter = fitsAt(middle);
            if (painter == null) {
              high = middle;
            } else {
              best!.dispose();
              best = painter;
              low = middle;
            }
          }
        }
        text = best;
      }
      text ??= _overflowing(
        line,
        rect,
        others: [
          for (var j = 0; j < rects.length; j++)
            if (j != i) rects[j],
        ],
        size: size,
        minFontSize: minFontSize,
        layout: layout,
      );

      final box = _boxFor(rect, text, size);
      final radius = Radius.circular(
        math.min(AppTheme.cornerRadius, box.shortestSide / 2),
      );
      // 한 줄 항목은 세로 가운데, 여러 줄 문단은 위에서부터 그린다.
      final centered =
          line.lineCount <= 1 && text.computeLineMetrics().length <= 1;
      placed.add((
        box: RRect.fromRectAndRadius(box, radius),
        textOffset: Offset(
          box.left + _padding,
          centered
              ? box.top + (box.height - text.height) / 2
              : box.top + _padding,
        ),
        text: text,
        id: line.id,
      ));
    }
    assert(() {
      debugTranslationBoxes = [for (final line in placed) line.box.outerRect];
      return true;
    }());
    return _TranslationBoxLayout._(placed);
  }

  // 최소 크기에서도 원문 영역에 들어가지 않는 번역: 빈 곳으로 넓히고, 그래도 넘치면 말줄임한다.
  static TextPainter _overflowing(
    TranslationBox translated,
    Rect rect, {
    required List<Rect> others,
    required Size size,
    required double minFontSize,
    required TextPainter Function(
      TranslationBox line,
      double fontSize, {
      required double maxWidth,
      int? maxLines,
    })
    layout,
  }) {
    // 오른쪽: 같은 높이에 있는 오른쪽 단위 앞까지, 1.5배까지.
    var rightLimit = size.width - _edge;
    for (final other in others) {
      final sameRow = other.top < rect.bottom && other.bottom > rect.top;
      if (sameRow && other.left >= rect.right - 1) {
        rightLimit = math.min(rightLimit, other.left - _gap);
      }
    }
    final innerWidth = rect.width - _padding * 2;
    final width = math.max(
      innerWidth,
      math.min(
        innerWidth * _maxWidthGrowth,
        rightLimit - rect.left - _padding * 2,
      ),
    );

    // 아래: 넓힌 폭과 겹치는 아래 단위 바로 위까지.
    var bottomLimit = size.height - _edge;
    final right = rect.left + width + _padding * 2;
    for (final other in others) {
      final sameColumn = other.left < right && other.right > rect.left;
      if (sameColumn && other.top >= rect.center.dy) {
        bottomLimit = math.min(bottomLimit, other.top - _gap);
      }
    }
    final maxHeight = math.max(
      rect.height - _padding * 2,
      bottomLimit - rect.top - _padding * 2,
    );

    final full = layout(translated, minFontSize, maxWidth: width);
    if (full.height <= maxHeight) {
      return full;
    }
    final maxLines = math.max(
      1,
      (maxHeight / full.preferredLineHeight).floor(),
    );
    full.dispose();
    return layout(translated, minFontSize, maxWidth: width, maxLines: maxLines);
  }

  // 번역 글자. `[읽을 수 없음]`은 다른 색으로, 불확실·대체 번역이면 끝에 표시 아이콘을 붙인다.
  // 아이콘도 글자 배치에 들어가므로 상자 크기 계산에 포함된다.
  static TextSpan _spanFor(TranslationBox line, TextStyle style) {
    final parts = line.translated.split(unreadableMarker);
    final markerStyle = style.copyWith(
      color: _TranslationBoxPainter.unreadableColor,
    );
    final icon = line.uncertain
        ? Icons.warning_amber_rounded
        : line.fallback
        ? Icons.info_outline
        : null;
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) TextSpan(text: unreadableMarker, style: markerStyle),
          if (parts[i].isNotEmpty) TextSpan(text: parts[i]),
        ],
        if (icon != null)
          TextSpan(
            text: ' ${String.fromCharCode(icon.codePoint)}',
            style: style.copyWith(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: line.uncertain
                  ? _TranslationBoxPainter.uncertainColor
                  : _TranslationBoxPainter.fallbackColor,
            ),
          ),
      ],
    );
  }

  // 원문 영역을 덮으면서 번역 글자가 들어가는 배경 영역. 영역 밖으로 나가지 않게 옮긴다.
  static Rect _boxFor(Rect rect, TextPainter painter, Size size) {
    final covered = rect.inflate(1);
    final width = math.max(covered.width, painter.width + _padding * 2);
    final height = math.max(covered.height, painter.height + _padding * 2);

    var left = covered.left;
    var top = covered.top;
    left = left.clamp(0, math.max(0, size.width - width)).toDouble();
    top = top.clamp(0, math.max(0, size.height - height)).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  void dispose() {
    for (final line in lines) {
      line.text.dispose();
    }
  }
}

// 배치해 둔 배경 상자와 글자를 그리기만 한다.
class _TranslationBoxPainter extends CustomPainter {
  _TranslationBoxPainter(this.layout);

  final _TranslationBoxLayout layout;

  // 색: 사진 위에 그려 바탕이 늘 사진이라 앱 테마(라이트/다크)와 상관없이 고정한다.
  // 거의 불투명한 밝은 바탕 + 아주 어두운 글자로 원문을 가리고 대비를 지킨다(인쇄물을 닮아 읽기 편하다).
  // 옅은 어두운 테두리는 흰 종이 위에서도 "덮어 그린 번역"의 경계가 보이게 한다.
  static const Color _background = Color(0xF7FFFFFF);
  static const Color textColor = Color(0xFF1B1B1F);

  // `[읽을 수 없음]` 부분과 표시 아이콘 색. 흰 바탕에서 4.5:1 이상 대비를 지킨다.
  static const Color unreadableColor = Color(0xFF6B6B73);
  static const Color uncertainColor = Color(0xFFA14A00);
  static const Color fallbackColor = Color(0xFF1F5FAF);
  static const Color _border = Color(0x59000000);
  static const double _borderWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final background = Paint()..color = _background;
    final border = Paint()
      ..color = _border
      ..style = PaintingStyle.stroke
      ..strokeWidth = _borderWidth;

    for (final line in layout.lines) {
      canvas.drawRRect(line.box, background);
      canvas.drawRRect(line.box.deflate(_borderWidth / 2), border);
      line.text.paint(canvas, line.textOffset);
    }

    canvas.restore();
  }

  // 배치가 바뀔 때(결과·크기·글자 모양)만 다시 그린다.
  @override
  bool shouldRepaint(_TranslationBoxPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout);
}
