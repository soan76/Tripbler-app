import 'package:flutter/material.dart';

typedef NicknameSubmitCallback = Future<String?> Function(String nickname);

/// 닉네임 입력과 수정 요청 상태를 관리하는 다이얼로그다.
///
/// 닉네임은 앞뒤 공백을 제거한 뒤 1~20자로 검증하고,
/// 저장 중에는 최소 1초 동안 로딩 상태를 표시한다.
class NicknameEditDialog extends StatefulWidget {
  const NicknameEditDialog({
    super.key,
    required this.initialNickname,
    required this.onSubmit,
  });

  final String? initialNickname;
  final NicknameSubmitCallback onSubmit;

  static Future<bool> show(
    BuildContext context, {
    required String? initialNickname,
    required NicknameSubmitCallback onSubmit,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NicknameEditDialog(
        initialNickname: initialNickname,
        onSubmit: onSubmit,
      ),
    );

    return result ?? false;
  }

  @override
  State<NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<NicknameEditDialog> {
  late final TextEditingController _controller;

  bool _isSubmitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.initialNickname ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final nickname = _controller.text.trim();

    if (nickname.isEmpty) {
      setState(() {
        _errorText = '닉네임을 입력해 주세요.';
      });
      return;
    }

    if (nickname.length > 20) {
      setState(() {
        _errorText = '닉네임은 1자 이상 20자 이하여야 합니다.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final minimumLoadingFuture = Future<void>.delayed(
      const Duration(seconds: 1),
    );

    String? errorMessage;

    try {
      errorMessage = await widget.onSubmit(nickname);
      await minimumLoadingFuture;
    } catch (_) {
      await minimumLoadingFuture;
      errorMessage = '닉네임 변경 중 오류가 발생했습니다.';
    }

    if (!mounted) {
      return;
    }

    if (errorMessage != null) {
      setState(() {
        _isSubmitting = false;
        _errorText = errorMessage;
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: const Text('닉네임 변경'),
        content: TextField(
          controller: _controller,
          enabled: !_isSubmitting,
          autofocus: true,
          maxLength: 20,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: '닉네임',
            hintText: '변경할 닉네임을 입력하세요.',
            errorText: _errorText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    Navigator.of(context).pop(false);
                  },
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('확인'),
          ),
        ],
      ),
    );
  }
}