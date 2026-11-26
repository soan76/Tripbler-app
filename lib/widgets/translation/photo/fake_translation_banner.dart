import 'package:flutter/material.dart';

/// 개발용 가짜 번역 모드임을 알리는 띠. 촬영·결과·상세 화면에서 같은 모양으로 쓴다.
class FakeTranslationBanner extends StatelessWidget {
  const FakeTranslationBanner({super.key, required this.message});

  /// 촬영 화면: 아직 아무것도 보내지 않았다는 안내.
  static const String captureMessage = '개발용 가짜 번역 · 사진과 글자를 보내지 않아요';

  /// 결과 화면: 보이는 번역이 실제 번역이 아니라는 안내.
  static const String resultMessage = '가짜 번역 결과 · 실제 번역이 아니에요 (개발용)';

  /// 상세 화면: 번역·발음·가격이 모두 가짜라는 안내.
  static const String detailMessage = '가짜 번역 결과예요. 번역·발음·가격은 실제 값이 아니에요.';

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: message,
      excludeSemantics: true,
      child: ColoredBox(
        color: colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          // 글자 배율이 커져 문구가 여러 줄이 되어도 아이콘이 첫 줄에 붙어 있게 위쪽에 맞춘다.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.science_outlined,
                  size: 20,
                  color: colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
