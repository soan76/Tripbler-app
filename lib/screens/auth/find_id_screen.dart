import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'find_id_result_screen.dart';

class FindIdScreen extends StatefulWidget {
  const FindIdScreen({super.key});

  @override
  State<FindIdScreen> createState() => _FindIdScreenState();
}

class _FindIdScreenState extends State<FindIdScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  // 인증번호가 정상적으로 발송되었는지 여부
  bool _isVerificationSent = false;

  // 인증번호가 입력되었는지 여부
  bool get _canVerify => _codeController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
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
          '아이디 찾기',
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
                    '아이디가 생각나지 않으세요?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    '계정에 연동한 Google 이메일을 입력해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    '연동된 이메일로 인증코드를 보내드립니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 48),

                  //
                  // 이메일 입력
                  //
                  Text(
                    '이메일',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          decoration: _buildInputDecoration(
                            context,
                            hintText: '연동된 이메일을 입력하세요',
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _sendVerificationCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            '인증하기',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  //
                  // 인증번호 발송 성공 후에만 표시
                  //
                  if (_isVerificationSent) ...[
                    const SizedBox(height: 28),

                    Text(
                      '인증확인',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            maxLength: 6,
                            onChanged: (_) {
                              setState(() {});
                            },
                            decoration: _buildInputDecoration(
                              context,
                              hintText: '6자리 인증코드 입력',
                            ).copyWith(counterText: ''),
                          ),
                        ),

                        const SizedBox(width: 10),

                        SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _resendVerificationCode,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.primary,
                              side: BorderSide(color: colorScheme.primary),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              '재전송',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 40),

                  Divider(color: colorScheme.outlineVariant),

                  const SizedBox(height: 24),

                  Center(
                    child: SizedBox(
                      width: 180,
                      height: 52,
                      child: ElevatedButton(
                        // 인증번호가 전송됐고,
                        // 인증번호 입력값이 있을 때만 활성화
                        onPressed: _isVerificationSent && _canVerify
                            ? _verifyCode
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,

                          // disabled일 때 회색으로 표시
                          disabledBackgroundColor:
                              colorScheme.surfaceContainerHighest,
                          disabledForegroundColor: colorScheme.onSurfaceVariant,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '확인',
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

  // 처음 인증번호 발송
  Future<void> _sendVerificationCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('이메일을 입력해 주세요.');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('올바른 이메일 형식을 입력해 주세요.');
      return;
    }

    final authProvider = context.read<AuthProvider>();

    final success = await authProvider.sendFindIdVerificationCode(email: email);

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(authProvider.errorMessage ?? '인증코드 전송에 실패했습니다.');
      return;
    }

    setState(() {
      _isVerificationSent = true;
      _codeController.clear();
    });

    _showMessage('인증코드를 이메일로 전송했습니다.');
  }

  // 인증번호 재전송
  Future<void> _resendVerificationCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('이메일을 입력해 주세요.');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('올바른 이메일 형식을 입력해 주세요.');
      return;
    }

    final authProvider = context.read<AuthProvider>();

    final success = await authProvider.sendFindIdVerificationCode(email: email);

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(authProvider.errorMessage ?? '인증코드 재전송에 실패했습니다.');
      return;
    }

    setState(() {
      _codeController.clear();
    });

    _showMessage('인증코드를 다시 전송했습니다.');
  }

  // 인증번호 검증
  Future<void> _verifyCode() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      return;
    }

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showMessage('인증코드는 6자리 숫자로 입력해 주세요.');
      return;
    }

    final authProvider = context.read<AuthProvider>();

    final loginId = await authProvider.verifyFindIdVerificationCode(
      email: email,
      code: code,
    );

    if (!mounted) {
      return;
    }

    if (loginId == null) {
      _showMessage(authProvider.errorMessage ?? '인증코드 확인에 실패했습니다.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FindIdResultScreen(loginId: loginId)),
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    ).hasMatch(email);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _buildInputDecoration(
    BuildContext context, {
    required String hintText,
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
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    );
  }
}