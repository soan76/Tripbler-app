import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';

import '../domain/translation/capture_frame.dart';
import '../domain/translation/text_paragraphs.dart';

class OcrService {
  /// 사진 전체의 글자를 읽는다(통번역용). ML Kit가 이어 준 글자(덩어리 안 줄과 덩어리 사이를 모두 `\n`으로
  /// 이음)를 그대로 쓴다. 프레임 안만 읽으려면 [recognizeLines]를 쓴다.
  Future<String> recognizeText({
    required String imagePath,
    required String sourceLanguageCode,
  }) async {
    if (imagePath.trim().isEmpty) {
      return '';
    }

    if (sourceLanguageCode == 'auto') {
      return _recognizeWithAutoScripts(imagePath);
    }

    final script = _scriptForLanguage(sourceLanguageCode);

    return _recognizeWithScript(imagePath: imagePath, script: script);
  }

  /// 사진의 글자를 줄 단위로 읽는다(찍기 모드 줄별 번역용). 글자 덩어리 순서대로 줄을 이어 붙이고,
  /// 빈 줄은 뺀다. [sourceLanguageCode]가 `auto`면 문자 체계 4가지로 읽어 글자가 가장 많은 결과를 쓴다.
  ///
  /// [onlyInCaptureFrame]이면 카메라로 찍은 사진에서 가이드 프레임 안의 줄만 쓴다(줄 가운데 점 기준).
  /// [cameraPreviewAspect]는 촬영 때 미리보기의 세로 기준 비율(짧은 변/긴 변)이다([CaptureFrame.regionInPhoto]).
  /// 프레임을 맞출 수 없는 사진(가로로 든 사진, 크기를 모름)이면 모든 줄을 쓰고 `frameApplied`를 false로 돌려준다.
  Future<CaptureFrameLines> recognizeLines({
    required String imagePath,
    required String sourceLanguageCode,
    bool onlyInCaptureFrame = false,
    double? cameraPreviewAspect,
  }) async {
    if (imagePath.trim().isEmpty) {
      return (lines: const <String>[], frameApplied: false);
    }

    final storedSize = onlyInCaptureFrame
        ? await _storedImageSize(imagePath)
        : null;

    final scripts = sourceLanguageCode == 'auto'
        ? const <TextRecognitionScript>[
            TextRecognitionScript.korean,
            TextRecognitionScript.latin,
            TextRecognitionScript.japanese,
            TextRecognitionScript.chinese,
          ]
        : <TextRecognitionScript>[_scriptForLanguage(sourceLanguageCode)];

    CaptureFrameLines? best;
    var bestLength = 0;

    for (final script in scripts) {
      final boxes = await _recognizeLinesWithScript(
        imagePath: imagePath,
        script: script,
      );
      final selected = CaptureFrame.selectLines(
        boxes,
        storedSize,
        cameraPreviewAspect: cameraPreviewAspect,
      );

      if (onlyInCaptureFrame) {
        _logFrameDecision(boxes, storedSize, cameraPreviewAspect, selected);
      }

      final length = selected.lines.fold<int>(
        0,
        (sum, line) => sum + line.length,
      );

      // 모두 비어 있으면 첫 결과의 프레임 적용 여부를 쓴다.
      if (best == null || length > bestLength) {
        best = selected;
        bestLength = length;
      }
    }

    return best ?? (lines: const <String>[], frameApplied: false);
  }

  /// 사진의 글자를 줄 단위로 읽고 줄 상자와 글자 덩어리 번호(`recognizedText.blocks` 인덱스)를 함께 돌려준다
  /// (사진 번역용). 빈 줄은 뺀다. [sourceLanguageCode]가 `auto`면 문자 체계 4가지로 읽어 글자가 가장 많은
  /// 결과를 쓴다. 사진 속 글자는 로그에 남기지 않는다.
  Future<List<RecognizedTextLine>> recognizeTextLines({
    required String imagePath,
    required String sourceLanguageCode,
  }) async {
    if (imagePath.trim().isEmpty) {
      return const <RecognizedTextLine>[];
    }

    final scripts = sourceLanguageCode == 'auto'
        ? const <TextRecognitionScript>[
            TextRecognitionScript.korean,
            TextRecognitionScript.latin,
            TextRecognitionScript.japanese,
            TextRecognitionScript.chinese,
          ]
        : <TextRecognitionScript>[_scriptForLanguage(sourceLanguageCode)];

    var best = const <RecognizedTextLine>[];
    var bestLength = 0;

    for (final script in scripts) {
      final lines = await _recognizeTextLinesWithScript(
        imagePath: imagePath,
        script: script,
      );
      final length = lines.fold<int>(0, (sum, line) => sum + line.text.length);

      if (length > bestLength) {
        best = lines;
        bestLength = length;
      }
    }

    return best;
  }

  /// ML Kit 줄 위치가 세워진 사진 기준이라는 가정을 실기기에서 확인하기 위한 디버그 로그.
  /// 사진 속 글자는 개인정보일 수 있어 글자 내용은 남기지 않고 크기·위치·개수만 남긴다.
  static void _logFrameDecision(
    List<({String text, ui.Rect box})> boxes,
    ui.Size? storedSize,
    double? cameraPreviewAspect,
    CaptureFrameLines selected,
  ) {
    if (!kDebugMode) {
      return;
    }

    final portrait = storedSize == null
        ? null
        : CaptureFrame.portraitSizeOf(storedSize);
    final maxRight = boxes.fold<double>(
      0,
      (value, line) => math.max(value, line.box.right),
    );
    final maxBottom = boxes.fold<double>(
      0,
      (value, line) => math.max(value, line.box.bottom),
    );

    debugPrint(
      '[프레임] 저장 크기 $storedSize, 세로 판단 $portrait, '
      '미리보기 비율 $cameraPreviewAspect, 줄 ${boxes.length}개, '
      '최대 right ${maxRight.toStringAsFixed(0)}, '
      '최대 bottom ${maxBottom.toStringAsFixed(0)}, '
      '프레임 적용 ${selected.frameApplied}, 남은 줄 ${selected.lines.length}개',
    );
  }

  /// 파일에 저장된 사진의 가로·세로 픽셀(방향 정보는 적용하지 않음). 읽지 못하면 null.
  ///
  /// 전체를 디코딩하지 않고 머리 정보만 읽는다. 다만 `ImmutableBuffer.fromFilePath`가 파일 전체(촬영 사진
  /// 수 MB)를 메모리에 읽으므로, 한 번 찍을 때 한 번만 부르고 바로 해제한다.
  static Future<ui.Size?> _storedImageSize(String imagePath) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;

    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(imagePath);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } catch (error) {
      debugPrint('사진 크기를 읽지 못함: $error');
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<List<({String text, ui.Rect box})>> _recognizeLinesWithScript({
    required String imagePath,
    required TextRecognitionScript script,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: script);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);

      return <({String text, ui.Rect box})>[
        for (final block in recognizedText.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty)
              (text: line.text.trim(), box: line.boundingBox),
      ];
    } finally {
      await textRecognizer.close();
    }
  }

  Future<List<RecognizedTextLine>> _recognizeTextLinesWithScript({
    required String imagePath,
    required TextRecognitionScript script,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: script);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);

      return <RecognizedTextLine>[
        for (var index = 0; index < recognizedText.blocks.length; index++)
          for (final line in recognizedText.blocks[index].lines)
            if (line.text.trim().isNotEmpty)
              (text: line.text.trim(), box: line.boundingBox, block: index),
      ];
    } finally {
      await textRecognizer.close();
    }
  }

  Future<String> _recognizeWithAutoScripts(String imagePath) async {
    final scripts = <TextRecognitionScript>[
      TextRecognitionScript.korean,
      TextRecognitionScript.latin,
      TextRecognitionScript.japanese,
      TextRecognitionScript.chinese,
    ];

    String bestText = '';

    for (final script in scripts) {
      final text = await _recognizeWithScript(
        imagePath: imagePath,
        script: script,
      );

      if (text.length > bestText.length) {
        bestText = text;
      }
    }

    return bestText.trim();
  }

  Future<String> _recognizeWithScript({
    required String imagePath,
    required TextRecognitionScript script,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: script);

    try {
      debugPrint('=== ML Kit processImage 시작 ===');

      final recognizedText = await textRecognizer.processImage(inputImage);

      debugPrint('=== ML Kit processImage 완료 ===');
      debugPrint('=== 인식 텍스트: ${recognizedText.text} ===');

      return recognizedText.text.trim();
    } finally {
      await textRecognizer.close();
    }
  }

  TextRecognitionScript _scriptForLanguage(String languageCode) {
    switch (languageCode) {
      case 'ko':
        return TextRecognitionScript.korean;
      case 'ja':
        return TextRecognitionScript.japanese;
      case 'zh':
        return TextRecognitionScript.chinese;
      case 'en':
      default:
        return TextRecognitionScript.latin;
    }
  }
}
