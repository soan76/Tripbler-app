import 'package:flutter/material.dart';

/// 배너 본문. 네트워크 장애, 서버 장애, 403, 재발급 뒤 401 등 여러 원인을 함께 다루므로
/// 원인을 단정하지 않고 실제로 할 수 있는 행동(잠시 후 다시 시도, 다시 로그인)을 안내한다.
const String sessionRestoreBannerDetail =
    '로그인 정보는 그대로 있습니다. 잠시 후 다시 시도해 주세요. 문제가 계속되면 다시 로그인해 주세요.';

/// 앱을 켤 때 로그인 정보를 확인하지 못했음을 알리는 상단 배너.
/// 세션 만료가 확인되지 않은 모든 복구 실패(네트워크·서버 장애, 403 등)에 쓴다.
///
/// 저장된 로그인 정보는 그대로 남아 있으므로, 사용자가 연결을 확인한 뒤
/// [onRetry]로 다시 시도할 수 있다. 앱 사용을 막지 않는 안내라서 오류 색 대신
/// 중립 표면색을 쓴다.
class SessionRestoreBanner extends StatelessWidget {
  const SessionRestoreBanner({
    super.key,
    required this.isRetrying,
    required this.onRetry,
  });

  final bool isRetrying;
  final VoidCallback onRetry;

  /// 이 배율 이상으로 글자를 키우면 버튼을 문구 아래로 내려 문구 폭을 확보한다.
  static const double _stackedTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) >= _stackedTextScale;

    final message = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '로그인 정보를 확인하지 못했습니다',
          style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          sessionRestoreBannerDetail,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final retryButton = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        disabledForegroundColor: colorScheme.onSurfaceVariant,
        textStyle: textTheme.labelLarge,
        minimumSize: const Size(64, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onPressed: isRetrying ? null : onRetry,
      child: isRetrying
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('확인 중'),
              ],
            )
          : const Text('다시 시도'),
    );

    final icon = Icon(
      Icons.cloud_off_outlined,
      size: 20,
      color: colorScheme.onSurfaceVariant,
    );

    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 글자가 커져 여러 줄이 되면 아이콘을 제목 첫 줄에 맞춘다.
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: icon,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: message),
                          ],
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: retryButton,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(child: message),
                      const SizedBox(width: 8),
                      retryButton,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
