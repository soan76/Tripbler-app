import 'package:flutter/material.dart';

/// 한 탭(지도)에서 띄운 SnackBar를 그 탭을 떠날 때 닫는다.
///
/// `MapScreen`은 다른 탭에서도 살아 있고 SnackBar는 앱 전체가 함께 쓰므로, 지도에서 띄운
/// 안내가 다른 탭에 남지 않게 한다. 자기가 띄운 SnackBar만 닫고 다른 화면의 SnackBar는
/// 건드리지 않는다.
class TabScopedSnackBar {
  TabScopedSnackBar({required this.isActive});

  /// 지금 그 탭이 보이는지. 닫기를 미룬 뒤 실제로 닫을지 정할 때 다시 읽는다.
  final bool Function() isActive;

  /// 이 객체가 띄웠고 아직 닫히지 않은 SnackBar.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _current;

  /// [_current]가 화면에 그려졌는지(SnackBar 대기열의 맨 앞인지).
  ///
  /// `ScaffoldFeatureController.close`는 그 SnackBar가 대기열 맨 앞일 때만 써야 한다
  /// (아니면 지금 보이는 다른 SnackBar를 닫는다). SnackBar는 맨 앞일 때만 그려지므로
  /// 내용이 한 번 그려졌으면 닫힐 때까지 맨 앞이다.
  bool _built = false;

  /// 대기 중에 탭을 옮겨, 그려지는 즉시 닫아야 하는지.
  bool _closeWhenBuilt = false;

  /// 지금 보이는 SnackBar를 내리고 [content]를 띄운다.
  void show(
    ScaffoldMessengerState messenger, {
    required Widget content,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    messenger.hideCurrentSnackBar();

    late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
    controller;
    controller = messenger.showSnackBar(
      SnackBar(
        content: _BuildNotifier(
          onBuilt: () => _onBuilt(controller),
          child: content,
        ),
        duration: duration,
        action: action,
        // Flutter 3.50부터 버튼이 있는 SnackBar는 기본으로 저절로 닫히지 않는다.
        // 지도 안내는 [duration]이 지나면 닫히도록 둔다.
        persist: false,
      ),
    );

    _current = controller;
    _built = false;
    _closeWhenBuilt = false;

    controller.closed.whenComplete(() {
      if (identical(_current, controller)) {
        _current = null;
      }
    });
  }

  /// 탭을 떠났다: 이 객체가 띄운 SnackBar만 닫는다. 이미 닫혔으면 아무것도 하지 않는다.
  void closeForInactiveTab() {
    final controller = _current;

    if (controller == null) {
      return;
    }

    if (!_built) {
      _closeWhenBuilt = true;
      return;
    }

    _closeAfterFrame(controller);
  }

  /// 대기 중인 SnackBar가 그려지기 전에 탭으로 돌아왔다: 닫지 않고 그대로 보여준다.
  void cancelPendingClose() {
    _closeWhenBuilt = false;
  }

  void _onBuilt(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller,
  ) {
    if (!identical(_current, controller)) {
      return;
    }

    _built = true;

    if (!_closeWhenBuilt) {
      return;
    }

    _closeWhenBuilt = false;
    _closeAfterFrame(controller);
  }

  /// 그리는 중에는 SnackBar를 닫을 수 없어 프레임이 끝난 뒤, 그때도 탭이 보이지
  /// 않으면 닫는다.
  void _closeAfterFrame(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_current, controller) && !isActive()) {
        _current = null;
        controller.close();
      }
    });
  }
}

/// SnackBar 내용. 처음 그려질 때 [onBuilt]로 알린다.
class _BuildNotifier extends StatefulWidget {
  const _BuildNotifier({required this.onBuilt, required this.child});

  final VoidCallback onBuilt;
  final Widget child;

  @override
  State<_BuildNotifier> createState() => _BuildNotifierState();
}

class _BuildNotifierState extends State<_BuildNotifier> {
  @override
  void initState() {
    super.initState();
    widget.onBuilt();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
