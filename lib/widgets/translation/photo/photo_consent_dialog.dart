import 'package:flutter/material.dart';

/// 사진 전송 동의 안내. 동의하면 [onAccept]를, 취소·뒤로가기·바깥 누르기면 [onCancel]을 한 번 부른다.
///
/// 부르는 쪽이 대화상자를 코드로 닫으면(상태가 바뀌어 더 묻지 않아도 될 때) [onCancel]도 불린다.
/// 그래서 [onCancel]은 아직 동의를 기다리는지 확인하고 처리해야 한다.
Future<void> showPhotoConsentDialog(
  BuildContext context, {
  required VoidCallback onAccept,
  required VoidCallback onCancel,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (_) => const PhotoConsentDialog(),
  );
  if (accepted == true) {
    onAccept();
  } else {
    onCancel();
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
    return AlertDialog(
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
