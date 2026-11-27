import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/translation/translation_provider.dart'
    show TranslationLanguage;

/// 원문 언어 ⇄ 번역 언어 막대(높이 48, 둥근 알약). 양쪽을 누르면 아래에서 언어 목록이 올라오고,
/// 가운데를 누르면 두 언어를 바꾼다(원문이 자동 감지면 바꿀 언어를 알 수 없어 막는다).
class PhotoLanguagePill extends StatelessWidget {
  const PhotoLanguagePill({
    super.key,
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.languages,
    required this.onSourceLanguageChanged,
    required this.onTargetLanguageChanged,
    this.onSwapLanguages,
  });

  static const String sourceLabel = '원문 언어';
  static const String targetLabel = '번역 언어';
  static const String swapTooltip = '언어 바꾸기';

  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslationLanguage> languages;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;

  /// 언어 바꾸기. 없으면 두 변경 콜백으로 원문·번역 언어를 맞바꾼다.
  final VoidCallback? onSwapLanguages;

  String _labelOf(String code) => languages
      .firstWhere(
        (language) => language.code == code,
        orElse: () => languages.first,
      )
      .label;

  Future<void> _pick(
    BuildContext context,
    String title,
    String current,
    List<TranslationLanguage> options,
    ValueChanged<String> onChanged,
  ) async {
    // 촬영 화면은 어두운 테마로 덮여 있지만, 목록 판은 앱 테마(라이트면 밝은 판)로 띄운다.
    final appTheme = Theme.of(Navigator.of(context).context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: appTheme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.cornerRadius),
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      builder: (context) => Theme(
        data: appTheme,
        // 맨 아래 줄이 제스처 막대·홈 표시줄에 가리지 않게 한다.
        child: SafeArea(
          top: false,
          child: _LanguageSheet(
            title: title,
            current: current,
            options: options,
          ),
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    // 촬영 화면의 어두운 테마 안에서 쓰므로 onSurface는 흰색에 가깝고 scrim은 검정이다.
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = colorScheme.onSurface;
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: foreground);
    final targets = languages.where((language) => language.code != 'auto');
    final canSwap = sourceLanguageCode != 'auto';
    final divider = Container(
      width: 1,
      height: 48,
      color: foreground.withValues(alpha: .25),
    );
    return Material(
      color: colorScheme.scrim.withValues(alpha: .5),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _side(
              context,
              label: sourceLabel,
              value: _labelOf(sourceLanguageCode),
              style: style,
              onTap: () => _pick(
                context,
                sourceLabel,
                sourceLanguageCode,
                languages,
                onSourceLanguageChanged,
              ),
            ),
            divider,
            IconButton(
              tooltip: swapTooltip,
              color: foreground,
              disabledColor: foreground.withValues(alpha: .38),
              onPressed: canSwap
                  ? onSwapLanguages ??
                        () {
                          final source = sourceLanguageCode;
                          onSourceLanguageChanged(targetLanguageCode);
                          onTargetLanguageChanged(source);
                        }
                  : null,
              icon: const Icon(Icons.swap_horiz, size: 20),
            ),
            divider,
            _side(
              context,
              label: targetLabel,
              value: _labelOf(targetLanguageCode),
              style: style,
              onTap: () => _pick(
                context,
                targetLabel,
                targetLanguageCode,
                targets.toList(),
                onTargetLanguageChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _side(
    BuildContext context, {
    required String label,
    required String value,
    required TextStyle? style,
    required VoidCallback onTap,
  }) {
    // 낭독기가 어느 쪽 언어인지 알 수 있게 이름을 붙인다.
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 104),
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: style?.color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// 언어 목록 판(목업: 밝은 판, 제목 아래 구분선으로 나눈 줄, 고른 줄은 강조색과 체크).
class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({
    required this.title,
    required this.current,
    required this.options,
  });

  final String title;
  final String current;
  final List<TranslationLanguage> options;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(title, style: text.titleMedium),
        ),
        for (final language in options) ...[
          const Divider(height: 1),
          _option(context, language, colorScheme, text),
        ],
      ],
    );
  }

  Widget _option(
    BuildContext context,
    TranslationLanguage language,
    ColorScheme colorScheme,
    TextTheme text,
  ) {
    final isSelected = language.code == current;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      minTileHeight: 48,
      selected: isSelected,
      selectedColor: colorScheme.primary,
      title: Text(
        language.label,
        // 고른 줄은 색과 함께 굵기로도 구분한다(titleMedium은 bodyLarge와 크기가 같고 더 굵다).
        style: isSelected
            ? text.titleMedium?.copyWith(color: colorScheme.primary)
            : text.bodyLarge?.copyWith(color: colorScheme.onSurface),
      ),
      trailing: isSelected ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(language.code),
    );
  }
}
