import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'signup_screen.dart';
import 'find_id_screen.dart';
import 'find_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginIdController  = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _loginIdFocusNode  = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;

  bool _loginIdHasError = false;
  bool _passwordHasError = false;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();

    _loginIdFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  Future<void> _login() async {
    final loginId = _loginIdController.text.trim();
    final password = _passwordController.text;

    final loginIdMissing = loginId.isEmpty;
    final passwordMissing = password.isEmpty;

    if (loginIdMissing || passwordMissing) {
      setState(() {
        _loginIdHasError = loginIdMissing;
        _passwordHasError = passwordMissing;
      });

      _showMessage('아이디와 비밀번호를 입력해 주세요.');
      return;
    }

    setState(() {
      _loginIdHasError = false;
      _passwordHasError = false;
    });

    FocusScope.of(context).unfocus();

    final authProvider = context.read<AuthProvider>();

    final success = await authProvider.login(
      loginId: loginId,
      password: password,
    );

    if (!mounted) {
      return;
    }

    if (success) {
      Navigator.of(context).pop();
    } else {
      // 로그인 인증 실패 시 어느 값이 틀렸는지는
      // 보안상 구분하지 않으므로 두 입력칸 모두 오류 표시
      setState(() {
        _loginIdHasError = true;
        _passwordHasError = true;
      });

      final message = authProvider.errorMessage;

      if (message != null) {
        _showMessage(message);
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.clearSnackBars();

    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: authProvider.isLoading
              ? null
              : () {
                  Navigator.of(context).pop();
                },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 36),

                  // 앱 이름
                  Text(
                    'Tripbler',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // 아이디
                  TextField(
                    controller: _loginIdController,
                    focusNode: _loginIdFocusNode,
                    enabled: !authProvider.isLoading,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.username],
                    onChanged: (_) {
                      if (_loginIdHasError) {
                        setState(() {
                          _loginIdHasError = false;
                        });
                      }
                    },
                    onSubmitted: (_) {
                      _passwordFocusNode.requestFocus();
                    },
                    decoration: _buildInputDecoration(
                      context: context,
                      hintText: '아이디',
                      hasError: _loginIdHasError,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 비밀번호
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    enabled: !authProvider.isLoading,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onChanged: (_) {
                      if (_passwordHasError) {
                        setState(() {
                          _passwordHasError = false;
                        });
                      }
                    },
                    onSubmitted: (_) {
                      if (!authProvider.isLoading) {
                        _login();
                      }
                    },
                    decoration: _buildInputDecoration(
                      context: context,
                      hintText: '비밀번호',
                      hasError: _passwordHasError,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 로그인 버튼
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: authProvider.isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        disabledBackgroundColor: colorScheme.primary.withValues(
                          alpha: 0.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: authProvider.isLoading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : const Text(
                              '로그인',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      TextButton(
                        onPressed: authProvider.isLoading
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const FindIdScreen(),
                                  ),
                                );
                              },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '아이디 찾기',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '|',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.outlineVariant,
                          ),
                        ),
                      ),

                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const FindPasswordScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '비밀번호 찾기',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),

                  Divider(color: colorScheme.outlineVariant),

                  const SizedBox(height: 22),

                  // 회원가입
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '계정이 없으신가요? ',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),

                      GestureDetector(
                        onTap: authProvider.isLoading
                            ? null
                            : () async {
                                context.read<AuthProvider>().clearError();
                                
                                final success = await Navigator.of(context)
                                    .push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => const SignupScreen(),
                                      ),
                                    );

                                if (!context.mounted) {
                                  return;
                                }

                                if (success == true) {
                                  _showMessage('회원가입이 완료되었습니다. 로그인해 주세요.');
                                }
                              },
                        child: Text(
                          '회원가입',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required BuildContext context,
    required String hintText,
    Widget? suffixIcon,
    bool hasError = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      filled: true,
      fillColor: colorScheme.surface,
      suffixIcon: suffixIcon,

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

      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: hasError ? colorScheme.error : colorScheme.outlineVariant,
        ),
      ),
    );
  }
}
