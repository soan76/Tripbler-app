import 'package:flutter/material.dart';
// 로딩 화면, 권한 거부 화면, 에러 화면
// 번역 화면의 상태에 따라 적절한 뷰를 표시하는 위젯들을 정의하는 파일
class TranslationLoadingView extends StatelessWidget {
  final String message;

  const TranslationLoadingView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// 번역 화면의 상태에 따라 적절한 뷰를 표시하는 위젯들을 정의하는 파일
class TranslationPermissionView extends StatelessWidget {
  final String title;
  final String description;
  final String primaryButtonText;
  final Future<void> Function() onPrimaryPressed;
  final String? bottomText;

  const TranslationPermissionView({
    super.key,
    required this.title,
    required this.description,
    required this.primaryButtonText,
    required this.onPrimaryPressed,
    this.bottomText,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 56,
                color: Colors.black87,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    onPrimaryPressed();
                  },
                  child: Text(primaryButtonText),
                ),
              ),
              if (bottomText != null) ...[
                const SizedBox(height: 14),
                Text(
                  bottomText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black45),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
// 번역 화면의 상태에 따라 적절한 뷰를 표시하는 위젯들을 정의하는 파일
class TranslationErrorView extends StatelessWidget {
  final String message;
  final String buttonText;
  final Future<void> Function() onPressed;

  const TranslationErrorView({
    super.key,
    required this.message,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 52,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  onPressed();
                },
                child: Text(buttonText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
