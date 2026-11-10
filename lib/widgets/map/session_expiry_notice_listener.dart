import 'package:flutter/material.dart';

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

  /// 이 리스너가 띄웠고 아직 닫히지 않은 안내. 다른 화면의 SnackBar는 보관하지 않는다.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _notice;

  /// [_notice]가 화면에 그려졌는지(SnackBar 대기열의 맨 앞인지).
  ///
  /// `ScaffoldFeatureController.close`는 그 SnackBar가 대기열 맨 앞일 때만 써야 한다
  /// (아니면 지금 보이는 다른 SnackBar를 닫는다). SnackBar는 맨 앞일 때만 그려지므로
  /// 내용이 한 번 그려졌으면 닫힐 때까지 맨 앞이다.
  bool _noticeBuilt = false;

  /// 대기 중에 탭을 옮겨, 그려지는 즉시 닫아야 하는지.
  bool _closeWhenBuilt = false;

  @override
  void initState() {
    super.initState();
    _maybeShow();
  }

  @override
  void didUpdateWidget(covariant SessionExpiryNoticeListener oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive && !widget.isActive) {
      _closeNotice();
    } else if (!oldWidget.isActive && widget.isActive) {
      // 대기 중인 안내가 그려지기 전에 지도 탭으로 돌아왔으면 그대로 보여준다.
      _closeWhenBuilt = false;
    }

    _maybeShow();
  }

  /// 지도 탭을 떠나면 이 리스너가 띄운 안내만 닫는다. 이미 닫혔으면 아무것도 하지 않는다.
  void _closeNotice() {
    final notice = _notice;

    if (notice == null) {
      return;
    }

    if (!_noticeBuilt) {
      _closeWhenBuilt = true;
      return;
    }

    _closeAfterFrame(notice);
  }

  void _onNoticeBuilt(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> notice,
  ) {
    if (!identical(_notice, notice)) {
      return;
    }

    _noticeBuilt = true;

    if (!_closeWhenBuilt) {
      return;
    }

    _closeWhenBuilt = false;
    _closeAfterFrame(notice);
  }

  /// 그리는 중에는 SnackBar를 닫을 수 없어 프레임이 끝난 뒤, 그때도 지도 탭이
  /// 아니면 닫는다.
  void _closeAfterFrame(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> notice,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_notice, notice) && !(mounted && widget.isActive)) {
        _notice = null;
        notice.close();
      }
    });
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

      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();

      late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
      notice;
      notice = messenger.showSnackBar(
        SnackBar(
          content: _NoticeContent(onBuilt: () => _onNoticeBuilt(notice)),
          // 두 문장을 읽고 로그인 버튼까지 누를 시간을 둔다(기본 4초).
          duration: SessionExpiryNoticeListener.displayDuration,
          action: SnackBarAction(label: '로그인', onPressed: widget.onLogin),
        ),
      );

      _notice = notice;
      _noticeBuilt = false;
      _closeWhenBuilt = false;

      notice.closed.whenComplete(() {
        if (identical(_notice, notice)) {
          _notice = null;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 만료 안내 문구. 처음 그려질 때 [onBuilt]로 알린다.
class _NoticeContent extends StatefulWidget {
  const _NoticeContent({required this.onBuilt});

  final VoidCallback onBuilt;

  @override
  State<_NoticeContent> createState() => _NoticeContentState();
}

class _NoticeContentState extends State<_NoticeContent> {
  @override
  void initState() {
    super.initState();
    widget.onBuilt();
  }

  @override
  Widget build(BuildContext context) =>
      const Text(SessionExpiryNoticeListener.message);
}
