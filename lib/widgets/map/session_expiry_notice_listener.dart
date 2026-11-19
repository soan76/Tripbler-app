import 'package:flutter/material.dart';

import 'tab_scoped_snack_bar.dart';

/// 지도 화면의 세션 만료 안내를 지도 탭이 보일 때만 한 번 띄운다.
///
/// `MapScreen`은 다른 탭에서도 살아 있으므로 [isActive](지도 탭이 선택됨)일 때만
/// 안내를 표시하고 [onConsume]으로 소비한다. 다른 탭에 있는 동안 생긴 안내는
/// 지도 탭으로 돌아왔을 때, 그때까지 유효하면 한 번 표시한다.
class SessionExpiryNoticeListener extends StatefulWidget {
  const SessionExpiryNoticeListener({
    super.key,
    required this.isActive,
    required this.hasNotice,
    required this.onConsume,
    required this.onLogin,
    required this.child,
  });

  final bool isActive;
  final bool hasNotice;
  final VoidCallback onConsume;
  final VoidCallback onLogin;
  final Widget child;

  static const String message = '로그인이 만료되었습니다. 다시 로그인하면 장소를 검색할 수 있습니다.';

  /// 로그인 버튼이 있는 안내의 표시 시간.
  static const Duration displayDuration = Duration(seconds: 6);

  @override
  State<SessionExpiryNoticeListener> createState() =>
      _SessionExpiryNoticeListenerState();
}

class _SessionExpiryNoticeListenerState
    extends State<SessionExpiryNoticeListener> {
  bool _scheduled = false;

  /// 이 리스너가 띄운 안내. 지도 탭을 떠나면 닫는다.
  late final TabScopedSnackBar _notice = TabScopedSnackBar(
    isActive: () => mounted && widget.isActive,
  );

  @override
  void initState() {
    super.initState();
    _maybeShow();
  }

  @override
  void didUpdateWidget(covariant SessionExpiryNoticeListener oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive && !widget.isActive) {
      _notice.closeForInactiveTab();
    } else if (!oldWidget.isActive && widget.isActive) {
      // 대기 중인 안내가 그려지기 전에 지도 탭으로 돌아왔으면 그대로 보여준다.
      _notice.cancelPendingClose();
    }

    _maybeShow();
  }

  void _maybeShow() {
    if (_scheduled || !widget.isActive || !widget.hasNotice) {
      return;
    }

    _scheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;

      // 프레임 사이에 탭을 옮겼거나, 다시 로그인해 안내가 무효가 됐으면 띄우지 않는다.
      if (!mounted || !widget.isActive || !widget.hasNotice) {
        return;
      }

      widget.onConsume();

      _notice.show(
        ScaffoldMessenger.of(context),
        content: const Text(SessionExpiryNoticeListener.message),
        // 두 문장을 읽고 로그인 버튼까지 누를 시간을 둔다(기본 4초).
        duration: SessionExpiryNoticeListener.displayDuration,
        action: SnackBarAction(label: '로그인', onPressed: widget.onLogin),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
