import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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
      final recognizedText = await textRecognizer.processImage(inputImage);
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
