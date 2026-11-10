import 'package:flutter/material.dart';

import '../../utils/map/search_query_normalizer.dart';

/// 검색창을 지금 쓸 수 있는지.
enum PlaceSearchAvailability {
  /// 로그인 상태: 검색할 수 있다.
  ready,

  /// 비로그인: 검색창을 누르면 로그인 안내를 보여준다.
  signedOut,

  /// 일시적 장애로 세션 복구를 기다리는 중: 검색 요청을 보내지 않고 상단 배너의 다시 시도를 안내한다.
  restorePending,
}

/// 지도 상단 장소 검색창.
///
/// 검색 버튼이나 키보드 검색 키로 제출한다. 검색어 판정은 [SearchQueryNormalizer]
/// (MapProvider와 같은 기준)를 쓰며, 100자를 넘으면 안내 문구를 보이고 제출하지 않는다.
class PlaceSearchBar extends StatelessWidget {
  const PlaceSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.availability,
    required this.isSearching,
    required this.onSubmitted,
    required this.onCleared,
    required this.onUnavailable,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PlaceSearchAvailability availability;
  final bool isSearching;

  /// 정리 후 유효한 검색어일 때만 원래 입력을 넘긴다.
  final ValueChanged<String> onSubmitted;

  /// X 버튼: 입력과 검색 결과를 함께 지운다.
  final VoidCallback onCleared;

  /// 비로그인 상태에서 검색창을 누르거나, 세션 복구 대기 중 제출했을 때.
  final VoidCallback onUnavailable;

  static const String tooLongMessage =
      '검색어는 ${SearchQueryNormalizer.maxSearchQueryLength}자까지 입력할 수 있습니다.';

  /// 비로그인 안내. 폭 320에서도 검색 버튼 옆에 한 줄로 들어가게 짧게 쓴다.
  static const String signedOutHint = '로그인 후 장소 검색';

  void _submit() {
    if (availability != PlaceSearchAvailability.ready) {
      onUnavailable();
      return;
    }

    final text = controller.text;

    if (SearchQueryNormalizer.normalize(text) == null) {
      return;
    }

    onSubmitted(text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSignedOut = availability == PlaceSearchAvailability.signedOut;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final isTooLong = SearchQueryNormalizer.isTooLong(text);
        final canSubmit = SearchQueryNormalizer.normalize(text) != null;

        return Material(
          color: colorScheme.surface,
          elevation: 2,
          // 밝은 지도 위와 다크 모드에서 그림자만으로는 경계가 흐려 테두리를 함께 둔다.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              readOnly: isSignedOut,
              onTap: isSignedOut ? onUnavailable : null,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              style: textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: isSignedOut ? signedOutHint : '장소 검색',
                hintStyle: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                // 앱 테마의 채움색을 끄고 검색창 표면색 하나만 보이게 한다.
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                errorText: isTooLong ? tooLongMessage : null,
                errorMaxLines: 2,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (text.isNotEmpty && !isSignedOut)
                      IconButton(
                        tooltip: '검색어 지우기',
                        icon: const Icon(Icons.close),
                        onPressed: onCleared,
                      ),
                    if (isSearching)
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: '검색',
                        icon: const Icon(Icons.search),
                        onPressed: isSignedOut || canSubmit ? _submit : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
