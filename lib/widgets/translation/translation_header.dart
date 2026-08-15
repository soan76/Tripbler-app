import 'package:flutter/material.dart';

import '../../providers/translation_provider.dart';
// 카메라 번역 제목 + 언어 선택 영역
// 번역 화면의 헤더를 구성하는 위젯
class TranslationHeader extends StatelessWidget {
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslationLanguage> languages;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;
  final VoidCallback onSwapLanguages;

  const TranslationHeader({
    super.key,
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.languages,
    required this.onSourceLanguageChanged,
    required this.onTargetLanguageChanged,
    required this.onSwapLanguages,
  });
  // 헤더 위젯을 구성하는 build 메서드
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final targetLanguages = languages
        .where((language) => language.code != 'auto')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '카메라 번역',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _LanguageDropdown(
                label: '원문',
                value: sourceLanguageCode,
                languages: languages,
                onChanged: onSourceLanguageChanged,
              ),
            ),
            IconButton(
              onPressed: sourceLanguageCode == 'auto' ? null : onSwapLanguages,
              icon: const Icon(Icons.swap_horiz),
            ),
            Expanded(
              child: _LanguageDropdown(
                label: '번역',
                value: targetLanguageCode,
                languages: targetLanguages,
                onChanged: onTargetLanguageChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
// 언어 선택 드롭다운 위젯
class _LanguageDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<TranslationLanguage> languages;
  final ValueChanged<String> onChanged;

  const _LanguageDropdown({
    required this.label,
    required this.value,
    required this.languages,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final safeValue = languages.any((language) => language.code == value)
        ? value
        : languages.first.code;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,

          // 드롭다운 메뉴 자체 배경
          dropdownColor: colorScheme.surfaceContainerHighest,

          // 선택된 값의 글자/아이콘 색상
          style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          iconEnabledColor: colorScheme.onSurfaceVariant,

          items: languages.map((language) {
            return DropdownMenuItem<String>(
              value: language.code,
              child: Text('$label: ${language.label}'),
            );
          }).toList(),
          onChanged: (selectedValue) {
            if (selectedValue == null) {
              return;
            }

            onChanged(selectedValue);
          },
        ),
      ),
    );
  }
}
