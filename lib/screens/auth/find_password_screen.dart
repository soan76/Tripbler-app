import 'package:flutter/material.dart';

import 'reset_password_screen.dart';

class FindPasswordScreen extends StatefulWidget {
  const FindPasswordScreen({super.key});

  @override
  State<FindPasswordScreen> createState() => _FindPasswordScreenState();
}

class _FindPasswordScreenState extends State<FindPasswordScreen> {
  final TextEditingController _loginIdController = TextEditingController();

  bool _loginIdHasError = false;

  @override
  void dispose() {
    _loginIdController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goToResetPassword() {
    final loginId = _loginIdController.text.trim();

    if (loginId.isEmpty) {
      setState(() {
        _loginIdHasError = true;
      });

      _showMessage('아이디를 입력해 주세요.');
      return;
    }

    setState(() {
      _loginIdHasError = false;
    });

    FocusScope.of(context).unfocus();

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResetPasswordScreen(loginId: loginId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          '비밀번호 찾기',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),

                  Text(
                    '비밀번호 찾기',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    '가입한 아이디를 입력하여 비밀번호를 재설정 하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 48),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          '아이디',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),

                      Expanded(
                        child: TextField(
                          controller: _loginIdController,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          onChanged: (_) {
                            if (_loginIdHasError) {
                              setState(() {
                                _loginIdHasError = false;
                              });
                            }
                          },
                          onSubmitted: (_) {
                            _goToResetPassword();
                          },
                          decoration: _buildInputDecoration(
                            context,
                            hintText: '아이디를 입력하세요',
                            hasError: _loginIdHasError,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  Divider(color: colorScheme.outlineVariant),

                  const SizedBox(height: 24),

                  Center(
                    child: SizedBox(
                      width: 180,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _goToResetPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '재설정',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
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

  InputDecoration _buildInputDecoration(
    BuildContext context, {
    required String hintText,
    required bool hasError,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
      filled: true,
      fillColor: colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: hasError ? colorScheme.error : colorScheme.outlineVariant,
          width: hasError ? 1.5 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: hasError ? colorScheme.error : colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
  }
}