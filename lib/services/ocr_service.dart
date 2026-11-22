import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';

class OcrService {
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
  Future<List<String>> recognizeLines({
    required String imagePath,
    required String sourceLanguageCode,
  }) async {
    if (imagePath.trim().isEmpty) {
      return const <String>[];
    }

    final scripts = sourceLanguageCode == 'auto'
        ? const <TextRecognitionScript>[
            TextRecognitionScript.korean,
            TextRecognitionScript.latin,
            TextRecognitionScript.japanese,
            TextRecognitionScript.chinese,
          ]
        : <TextRecognitionScript>[_scriptForLanguage(sourceLanguageCode)];

    var bestLines = const <String>[];
    var bestLength = 0;

    for (final script in scripts) {
      final lines = await _recognizeLinesWithScript(
        imagePath: imagePath,
        script: script,
      );
      final length = lines.fold<int>(0, (sum, line) => sum + line.length);

      if (length > bestLength) {
        bestLines = lines;
        bestLength = length;
      }
    }

    return bestLines;
  }

  Future<List<String>> _recognizeLinesWithScript({
    required String imagePath,
    required TextRecognitionScript script,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: script);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);

      return <String>[
        for (final block in recognizedText.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty) line.text.trim(),
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
