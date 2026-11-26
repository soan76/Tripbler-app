import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 사진 전송 동의 안내를 띄운다. 동의하면 [onAccept]를, 취소·뒤로가기·바깥 누르기면 [onCancel]을 한 번 부른다.
///
/// 돌려받은 [PhotoConsentPrompt.close]로 코드에서 닫을 수 있다(상태가 바뀌어 더 묻지 않아도 될 때).
/// 이때도 [onCancel]이 불리므로 [onCancel]은 아직 동의를 기다리는지 확인하고 처리해야 한다.
PhotoConsentPrompt showPhotoConsentDialog(
  BuildContext context, {
  required VoidCallback onAccept,
  required VoidCallback onCancel,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<bool>(
    context: context,
    builder: (_) => const PhotoConsentDialog(),
  );
  final done = navigator.push(route).then((accepted) {
    if (accepted == true) {
      onAccept();
    } else {
      onCancel();
    }
  });
  return PhotoConsentPrompt._(navigator, route, done);
}

/// 띄운 동의 대화상자. [close]는 이 대화상자 경로만 닫는다(그 아래 경로는 건드리지 않는다).
class PhotoConsentPrompt {
  PhotoConsentPrompt._(this._navigator, this._route, this.done);

  final NavigatorState _navigator;
  final Route<bool> _route;

  /// 대화상자가 닫히고 콜백까지 부른 뒤 끝난다.
  final Future<void> done;

  /// 아직 떠 있으면 닫는다. 이미 닫혔으면(사용자가 닫은 직후 등) 아무것도 하지 않는다.
  void close() {
    if (!_route.isActive) {
      return;
    }
    if (_route.isCurrent) {
      _navigator.pop();
    } else {
      _navigator.removeRoute(_route);
    }
  }
}

class PhotoConsentDialog extends StatelessWidget {
  const PhotoConsentDialog({super.key});

  static const String message =
      '번역을 위해 촬영한 사진과 인식된 글자를 Tripbler 서버 및 AI 제공업체에 전송합니다.';
  static const String acceptLabel = '동의하고 번역';
  static const String cancelLabel = '취소';

  @override
  Widget build(BuildContext context) {
    // 앱의 다른 버튼·입력창과 같은 둥글기(4)로 맞춘다.
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppTheme.cornerRadius)),
      ),
      title: const Text('사진 전송 안내'),
      content: const SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(acceptLabel),
        ),
      ],
    );
  }
}
