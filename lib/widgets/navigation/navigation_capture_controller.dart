import 'package:flutter/material.dart';

/// 화면이 소유한 촬영 동작을 메뉴에 연결한다. 카메라 자체는 화면이 관리한다.
class NavigationCaptureController {
  final action = ValueNotifier<VoidCallback?>(null);

  /// 등록한 화면이 사진을 찍는 중인지. 메뉴가 현재 화면 아이콘 자리에 진행 표시를 보인다.
  final busy = ValueNotifier<bool>(false);

  /// 등록한 화면이 촬영 화면(카메라 대기)인지. 권한 확인·카메라 준비 중에도 true이고, 권한 안내나
  /// 카메라를 쓸 수 없는 화면은 false다. 메뉴가 탭을 고른 프레임에 바로 쓰도록 화면은 탭 선택과
  /// 상관없이 알리고, 메뉴 쪽이 탭으로 거른다. 메뉴가 안쪽 버튼을 카메라 아이콘으로, 촬영할 수 없으면 흐리게 보인다.
  final cameraScreen = ValueNotifier<bool>(false);
  final expansion = ValueNotifier<double>(0);
  bool _disposed = false;
  Object? _owner;

  // ValueNotifier는 값이 같으면 알리지 않으므로, 같은 콜백·같은 상태로 다시 등록해도 메뉴를 다시 그리지 않는다.
  void register(
    Object owner,
    VoidCallback? callback, {
    bool busy = false,
    bool cameraScreen = false,
  }) {
    if (_disposed) return;
    _owner = owner;
    action.value = callback;
    this.busy.value = busy;
    this.cameraScreen.value = cameraScreen;
  }

  void unregister(Object owner) {
    if (_disposed || _owner != owner) return;
    _owner = null;
    action.value = null;
    busy.value = false;
    cameraScreen.value = false;
  }

  void dispose() {
    _disposed = true;
    action.dispose();
    busy.dispose();
    cameraScreen.dispose();
    expansion.dispose();
  }
}

/// 부모 메뉴를 build 도중 갱신하지 않고, 최신 화면의 촬영 가능 상태만 등록한다.
class NavigationCaptureBinding extends StatefulWidget {
  const NavigationCaptureBinding({
    super.key,
    required this.controller,
    required this.onCapture,
    this.busy = false,
    this.cameraScreen = false,
    required this.child,
  });

  final NavigationCaptureController? controller;

  /// 같은 값이면 알리지 않도록 build마다 새로 만드는 클로저 대신 메서드 tear-off를 넘긴다.
  final VoidCallback? onCapture;
  final bool busy;
  final bool cameraScreen;
  final Widget child;

  @override
  State<NavigationCaptureBinding> createState() => _CaptureBindingState();
}

class _CaptureBindingState extends State<NavigationCaptureBinding> {
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      widget.controller?.register(
        this,
        widget.onCapture,
        busy: widget.busy,
        cameraScreen: widget.cameraScreen,
      );
    });
    return widget.child;
  }

  @override
  void didUpdateWidget(NavigationCaptureBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final previous = oldWidget.controller;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => previous?.unregister(this),
      );
    }
  }

  @override
  void dispose() {
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => controller?.unregister(this),
    );
    super.dispose();
  }
}

/// 메뉴가 퍼지는 동안 보조 조작과 안내만 숨긴다. 미리보기/사진 제스처는 유지한다.
class NavigationCaptureControls extends StatelessWidget {
  const NavigationCaptureControls({
    super.key,
    this.controller,
    required this.child,
  });
  final NavigationCaptureController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = controller;
    if (value == null) return child;
    return ValueListenableBuilder<double>(
      valueListenable: value.expansion,
      child: child,
      builder: (context, progress, child) => IgnorePointer(
        ignoring: progress > 0,
        child: ExcludeSemantics(
          excluding: progress > 0,
          child: Opacity(opacity: 1 - progress.clamp(0, 1), child: child),
        ),
      ),
    );
  }
}
