import 'dart:io';

import 'package:flutter/material.dart';

import '../../providers/translation_provider.dart';
import 'translation_header.dart';
import 'translation_result_cards.dart';

// 촬영/선택한 이미지, 인식/번역 결과, 다시 촬영/다시 선택 버튼
// 번역 결과 화면을 구성하는 위젯
class TranslationResultView extends StatefulWidget {
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
  State<TranslationResultView> createState() => _TranslationResultViewState();
}

class _TranslationResultViewState extends State<TranslationResultView> {
  final PageController _pageController = PageController();

  int _currentPageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRecognizedText = widget.recognizedText.trim().isNotEmpty;
    final hasTranslatedText = widget.translatedText.trim().isNotEmpty;
    final shouldShowTextSlider = hasRecognizedText || hasTranslatedText;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslationHeader(
            sourceLanguageCode: widget.sourceLanguageCode,
            targetLanguageCode: widget.targetLanguageCode,
            languages: widget.languages,
            onSourceLanguageChanged: widget.onSourceLanguageChanged,
            onTargetLanguageChanged: widget.onTargetLanguageChanged,
            onSwapLanguages: widget.onSwapLanguages,
          ),
          const SizedBox(height: 18),

          if (widget.selectedImagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(
                File(widget.selectedImagePath!),
                width: double.infinity,

                // 촬영 이미지가 너무 길게 표시되어 결과 영역까지 많이 스크롤되는 문제를 줄이기 위해 높이를 제한함.
                height: 260,
                fit: BoxFit.cover,
              ),
            ),

          const SizedBox(height: 18),

          if (widget.status == TranslationStatus.recognizing)
            const TranslationProcessingCard(message: '문자를 인식하고 있습니다.'),

          if (widget.status == TranslationStatus.translating)
            const TranslationProcessingCard(message: '번역하고 있습니다.'),

          if (widget.errorMessage != null)
            TranslationMessageCard(
              message: widget.errorMessage!,
              icon: Icons.info_outline,
            ),

          if (shouldShowTextSlider) ...[
            const SizedBox(height: 6),
            const Text(
              '좌우로 밀어서 원문과 번역 결과를 확인하세요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 10),

            // 인식된 원문과 번역 결과를 세로로 쌓지 않고 PageView로 묶어 화면 스크롤을 줄임.
            SizedBox(
              height: 260,
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPageIndex = index;
                  });
                },
                children: [
                  _buildTextSlideCard(
                    title: '인식된 원문',
                    text: widget.recognizedText,
                    emptyMessage: '인식된 원문이 없습니다.',
                  ),
                  _buildTextSlideCard(
                    title: '번역 결과',
                    text: widget.translatedText,
                    emptyMessage: widget.status == TranslationStatus.translating
                        ? '번역하고 있습니다.'
                        : '번역 결과가 없습니다.',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            _buildPageIndicator(),
          ],

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.isProcessing
                      ? null
                      : () {
                          widget.onRetake();
                        },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('다시 촬영'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.isProcessing
                      ? null
                      : () {
                          widget.onPickFromGallery();
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

  // 원문/번역 결과를 PageView 안에서 보여주기 위한 카드.
  // 긴 텍스트는 화면 전체가 아니라 카드 내부에서만 스크롤되도록 처리함.
  Widget _buildTextSlideCard({
    required String title,
    required String text,
    required String emptyMessage,
  }) {
    final displayText = text.trim().isEmpty ? emptyMessage : text.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                displayText,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 현재 원문/번역 중 어떤 페이지를 보고 있는지 표시하는 점 indicator.
  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        final isSelected = _currentPageIndex == index;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isSelected ? 18 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.green.shade700 : Colors.black26,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}