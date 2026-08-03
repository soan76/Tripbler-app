import 'dart:io';

import 'package:flutter/material.dart';

import '../../providers/translation_provider.dart';
import 'translation_header.dart';
import 'translation_result_cards.dart';
// 촬영/선택한 이미지, 인식/번역 결과, 다시 촬영/다시 선택 버튼
// 번역 결과 화면을 구성하는 위젯
class TranslationResultView extends StatelessWidget {
  final TranslationStatus status;
  final String? selectedImagePath;
  final String? errorMessage;
  final String recognizedText;
  final String translatedText;
  final bool isProcessing;
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslationLanguage> languages;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;
  final VoidCallback onSwapLanguages;
  final Future<void> Function() onRetake;
  final Future<void> Function() onPickFromGallery;

  const TranslationResultView({
    super.key,
    required this.status,
    required this.selectedImagePath,
    required this.errorMessage,
    required this.recognizedText,
    required this.translatedText,
    required this.isProcessing,
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.languages,
    required this.onSourceLanguageChanged,
    required this.onTargetLanguageChanged,
    required this.onSwapLanguages,
    required this.onRetake,
    required this.onPickFromGallery,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslationHeader(
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            languages: languages,
            onSourceLanguageChanged: onSourceLanguageChanged,
            onTargetLanguageChanged: onTargetLanguageChanged,
            onSwapLanguages: onSwapLanguages,
          ),
          const SizedBox(height: 18),
          if (selectedImagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(
                File(selectedImagePath!),
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 18),
          if (status == TranslationStatus.recognizing)
            const TranslationProcessingCard(message: '문자를 인식하고 있습니다.'),
          if (status == TranslationStatus.translating)
            const TranslationProcessingCard(message: '번역하고 있습니다.'),
          if (errorMessage != null)
            TranslationMessageCard(
              message: errorMessage!,
              icon: Icons.info_outline,
            ),
          if (recognizedText.trim().isNotEmpty)
            TranslationTextCard(title: '인식된 원문', text: recognizedText),
          if (translatedText.trim().isNotEmpty)
            TranslationTextCard(title: '번역 결과', text: translatedText),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () {
                          onRetake();
                        },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('다시 촬영'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () {
                          onPickFromGallery();
                        },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('다시 선택'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
