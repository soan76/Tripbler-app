import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth/auth_provider.dart';

/// 로그아웃 결과를 SnackBar로 알린다.
///
/// 기기에 저장된 로그인 정보(토큰)를 지우지 못했으면, 다음 실행 때 세션이 다시 살아날 수
/// 있으므로 "다시 시도"를 둔다. 다시 시도도 실패하면 같은 안내를 다시 띄운다.
/// 안내가 떠 있거나 대기 중일 때 새로 로그인하면 더 지울 것이 없으므로 안내를 닫는다.
///
/// 호출하는 화면(서랍, 내 정보)이 먼저 닫힐 수 있어 [messenger]와 [notifier]를 미리 받아 둔다.
void showLogoutResult({
  required ScaffoldMessengerState messenger,
  required AuthNotifier notifier,
  required bool localTokensCleared,
}) {
  if (!messenger.mounted) {
    return;
  }

  messenger.hideCurrentSnackBar();

  if (localTokensCleared) {
    messenger.showSnackBar(
      const SnackBar(content: Text(logoutSucceededMessage)),
    );
    return;
  }

  // 화면(서랍 등)이 닫혀도 남아 있는 앱의 상태 컨테이너로 로그인 여부를 확인한다.
  // [messenger]가 ProviderScope 아래에 있어야 한다(앱은 main.dart의 buildAppScope가
  // MaterialApp 전체를 감싸므로 ScaffoldMessenger도 그 아래에 있다).
  final container = ProviderScope.containerOf(messenger.context, listen: false);
  bool isAuthenticated() => container.read(authProvider).isAuthenticated;

  final notice = _LogoutFailureNotice(messenger);

  notice.controller = messenger.showSnackBar(
    SnackBar(
      content: _ShownNotifier(
        onShown: notice.onShown,
        child: const Text(localTokenClearFailedMessage),
      ),
      // 기기에 정보가 남아 있으므로 사용자가 직접 닫거나 다시 시도할 때까지 둔다.
      persist: true,
      showCloseIcon: true,
      action: SnackBarAction(
        label: '다시 시도',
        onPressed: () async {
          final cleared = await notifier.retryClearLocalTokens();

          // 다시 시도하는 사이 새로 로그인했으면 로그아웃 안내를 띄우지 않는다.
          if (isAuthenticated()) {
            return;
          }

          showLogoutResult(
            messenger: messenger,
            notifier: notifier,
            localTokensCleared: cleared,
          );
        },
      ),
    ),
  );

  notice.listenForSignIn(container);
}

/// 지금 남아 있는 로그아웃 실패 안내의 로그인 구독 수. 테스트에서 구독이 쌓이지 않는지 본다.
@visibleForTesting
int get debugLogoutFeedbackSubscriptionCount => _activeSubscriptionCount;

int _activeSubscriptionCount = 0;

/// 로그아웃 실패 안내 하나. 새로 로그인하면 이 안내만 닫는다.
///
/// `ScaffoldFeatureController.close`는 그 SnackBar가 대기열 맨 앞일 때만 써야 한다
/// (아니면 디버그에서는 assert, 릴리스에서는 지금 보이는 다른 SnackBar를 닫는다).
/// SnackBar 내용은 맨 앞일 때만 그려지므로, 내용이 그려졌으면 닫힐 때까지 맨 앞이다.
/// 그려지기 전(다른 SnackBar 뒤에서 대기 중)에 로그인했으면 그려지는 즉시 닫는다.
class _LogoutFailureNotice {
  _LogoutFailureNotice(this.messenger);

  final ScaffoldMessengerState messenger;

  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  controller;

  ProviderSubscription<bool>? _subscription;

  /// 내용이 그려졌는지(대기열 맨 앞인지).
  bool _shown = false;

  /// 닫혔거나 닫기를 요청했는지. 같은 안내를 두 번 닫지 않는다.
  bool _closed = false;

  /// 대기 중에 로그인해, 그려지는 즉시 닫아야 하는지.
  bool _closeWhenShown = false;

  void listenForSignIn(ProviderContainer container) {
    _subscription = container.listen<bool>(
      authProvider.select((auth) => auth.isAuthenticated),
      (_, authenticated) {
        if (authenticated) {
          _onSignedIn();
        }
      },
    );
    _activeSubscriptionCount++;

    // 안내가 닫히면 구독도 끝낸다.
    controller.closed.whenComplete(() {
      _closed = true;
      _endSubscription();
    });
  }

  void _onSignedIn() {
    // ScaffoldMessenger가 폐기되면 closed가 끝나지 않으므로 여기서 구독을 정리한다.
    if (!messenger.mounted) {
      _endSubscription();
      return;
    }

    if (_closed) {
      return;
    }

    if (!_shown) {
      _closeWhenShown = true;
      return;
    }

    _closeSafely();
  }

  /// 내용이 처음 그려질 때(빌드 중) 불린다.
  void onShown() {
    _shown = true;

    if (!_closeWhenShown) {
      return;
    }

    _closeWhenShown = false;
    _closeSafely();
  }

  /// 빌드 중에는 SnackBar를 닫을 수 없으므로 그때는 프레임이 끝난 뒤 닫는다.
  void _closeSafely() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _close());
      return;
    }

    _close();
  }

  void _close() {
    if (_closed || !messenger.mounted) {
      return;
    }

    _closed = true;
    controller.close();
  }

  void _endSubscription() {
    final subscription = _subscription;

    if (subscription == null) {
      return;
    }

    _subscription = null;
    _activeSubscriptionCount--;
    subscription.close();
  }
}

/// SnackBar 내용. 처음 그려질 때 [onShown]으로 알린다.
///
/// `lib/widgets/map/tab_scoped_snack_bar.dart`의 `_BuildNotifier`와 같은 방식이다.
class _ShownNotifier extends StatefulWidget {
  const _ShownNotifier({required this.onShown, required this.child});

  final VoidCallback onShown;
  final Widget child;

  @override
  State<_ShownNotifier> createState() => _ShownNotifierState();
}

class _ShownNotifierState extends State<_ShownNotifier> {
  @override
  void initState() {
    super.initState();
    widget.onShown();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const String logoutSucceededMessage = '로그아웃되었습니다.';

const String localTokenClearFailedMessage =
    '기기에 저장된 로그인 정보를 삭제하지 못했습니다. 다시 시도해 주세요.';
