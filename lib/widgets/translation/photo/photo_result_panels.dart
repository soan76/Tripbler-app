part of 'photo_result_view.dart';

// 결과 화면 위에 얹는 조각: 위 막대, 진행 표시, 실패 안내, 결과 안내 묶음.
// 상태마다 모양을 달리한다. 진행은 사진을 살짝 덮고 가운데에, 실패는 사진이 보이게 아래에(엄지가 닿는 곳)
// 다음 행동과 함께, 결과 안내는 아래에 작은 묶음 하나로 보인다.

/// 안내 묶음이 넓은 화면에서 지나치게 늘어나지 않게 하는 최대 폭.
const double _panelMaxWidth = 480;

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onRetake,
    required this.showingOriginal,
    required this.onToggleOriginal,
  });

  final VoidCallback onRetake;

  /// 원문을 보고 있는지. 결과가 없으면(진행·실패) null이고 원문 보기 버튼을 숨긴다.
  final bool? showingOriginal;
  final VoidCallback onToggleOriginal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final plain = TextButton.styleFrom(
      foregroundColor: colorScheme.onSurface,
      minimumSize: const Size(48, 48),
    );
    final showingOriginal = this.showingOriginal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Flexible(
            child: TextButton.icon(
              style: plain,
              onPressed: onRetake,
              icon: const Icon(Icons.arrow_back),
              label: const Text(PhotoResultView.retakeLabel),
            ),
          ),
          const Spacer(),
          if (showingOriginal != null)
            Flexible(
              // 원문을 보는 중(상자를 숨김)이면 눌린 상태로 보여 지금 상태를 알 수 있게 한다.
              child: showingOriginal
                  ? FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: onToggleOriginal,
                      child: const Text(PhotoResultView.showTranslationLabel),
                    )
                  : TextButton(
                      style: plain,
                      onPressed: onToggleOriginal,
                      child: const Text(PhotoResultView.showOriginalLabel),
                    ),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 사진을 먼저 보여 주므로 살짝만 어둡게 덮는다.
    return ColoredBox(
      color: theme.colorScheme.scrim.withValues(alpha: 0.4),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _Panel(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(label, style: theme.textTheme.titleMedium),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.failed,
    required this.message,
    required this.hasPhoto,
    required this.onRetry,
    required this.onRetake,
  });

  /// 번역 실패면 제목과 오류 표시를, 글자 없음·지원하지 않는 사진이면 안내 표시만 쓴다.
  final bool failed;
  final String? message;
  final bool hasPhoto;
  final VoidCallback? onRetry;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = this.message;
    final onRetry = this.onRetry;
    const buttonSize = Size.fromHeight(48);

    return Align(
      alignment: hasPhoto ? Alignment.bottomCenter : Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _panelMaxWidth),
          child: _Panel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      failed ? Icons.error_outline : Icons.info_outline,
                      color: failed
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (failed)
                            Text(
                              PhotoResultView.failedTitle,
                              style: theme.textTheme.titleMedium,
                            ),
                          if (failed && message != null)
                            const SizedBox(height: 4),
                          if (message != null)
                            Text(
                              message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: failed
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 다음 행동: 다시 보낼 수 있으면 다시 시도가 먼저, 아니면 재촬영이 주 버튼이다.
                if (onRetry != null) ...[
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: buttonSize),
                    onPressed: onRetry,
                    child: const Text(PhotoResultView.retryLabel),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: buttonSize),
                    onPressed: onRetake,
                    child: const Text(PhotoResultView.retakeLabel),
                  ),
                ] else
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: buttonSize),
                    onPressed: onRetake,
                    child: const Text(PhotoResultView.retakeLabel),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 결과 안내(대체 번역·빠진 문단·일부만 번역)를 하나로 묶어 아래에 둔다. 길어지면 안에서 스크롤한다.
class _NoticePanel extends StatelessWidget {
  const _NoticePanel({required this.notices, required this.maxHeight});

  final List<String> notices;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _panelMaxWidth,
            maxHeight: maxHeight,
          ),
          child: _Panel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상자의 대체 번역 표시와 같은 아이콘을 써서 둘을 이어 읽게 한다.
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < notices.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                            child: Text(
                              notices[i],
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 사진 위에 얹는 단색 바탕. 사진과 구분되도록 테마의 높은 표면색을 쓴다.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
