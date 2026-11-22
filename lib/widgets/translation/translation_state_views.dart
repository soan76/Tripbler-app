import 'package:flutter/material.dart';

import '../../providers/translation/translation_provider.dart';
import 'initial_camera_permission_view.dart';

/// 카메라 대기 화면 전 단계(권한 확인·요청·거부, 카메라 준비·오류)를 상태에 맞게 보여 준다.
///
/// 결과 화면과 카메라 대기 화면(cameraReady·capturing) 상태는 화면이 따로 그리므로 여기서는 빈 칸이다.
class TranslationCameraStatusView extends StatelessWidget {
  final TranslationStatus status;
  final String? errorMessage;
  final Future<void> Function() onRequestPermission;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onRetry;

  const TranslationCameraStatusView({
    super.key,
    required this.status,
    required this.errorMessage,
    required this.onRequestPermission,
    required this.onOpenSettings,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case TranslationStatus.checkingPermission:
        return const TranslationLoadingView(message: '카메라 권한을 확인하고 있습니다.');

      case TranslationStatus.permissionRequired:
        return InitialCameraPermissionView(
          onRequestPermission: onRequestPermission,
        );

      case TranslationStatus.permissionDenied:
        return TranslationPermissionView(
          title: '카메라 권한이 허용되지 않았습니다',
          description: '카메라 번역을 사용하려면 카메라 권한을 허용해야 합니다.',
          primaryButtonText: '다시 권한 요청',
          onPrimaryPressed: onRequestPermission,
        );

      case TranslationStatus.permissionPermanentlyDenied:
        return TranslationPermissionView(
          title: '설정에서 카메라 권한을 허용해 주세요',
          description:
              '카메라 권한이 차단되어 있습니다. 기기 설정에서 이 앱의 카메라 권한을 허용한 뒤 다시 돌아와 주세요.',
          primaryButtonText: '앱 설정 열기',
          onPrimaryPressed: onOpenSettings,
        );

      case TranslationStatus.initializingCamera:
        return const TranslationLoadingView(message: '카메라를 준비하고 있습니다.');

      case TranslationStatus.cameraUnavailable:
        return TranslationErrorView(
          message:
              errorMessage ?? '카메라를 시작할 수 없습니다.\n카메라 상태를 확인한 뒤 다시 시도해 주세요.',
          buttonText: '다시 시도',
          onPressed: onRetry,
        );

      case TranslationStatus.cameraReady:
      case TranslationStatus.capturing:
      case TranslationStatus.recognizing:
      case TranslationStatus.translating:
      case TranslationStatus.completed:
      case TranslationStatus.failed:
        return const SizedBox.shrink();
    }
  }
}

// 로딩 화면
class TranslationLoadingView extends StatelessWidget {
  final String message;

  const TranslationLoadingView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),

            const SizedBox(height: 18),

            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 권한 거부 / 권한 설정 안내 화면
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
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            // 시스템 테마에 따라 카드 배경 변경
            color: colorScheme.surfaceContainer,

            borderRadius: BorderRadius.circular(24),

            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 56,
                color: colorScheme.onSurface,
              ),

              const SizedBox(height: 18),

              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: colorScheme.onSurfaceVariant,
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
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// 카메라 오류 화면
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
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            // 시스템 테마에 따라 카드 배경 변경
            color: colorScheme.surfaceContainer,

            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 52,

                // 시스템 오류 색상 사용
                color: colorScheme.error,
              ),

              const SizedBox(height: 16),

              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: colorScheme.onSurface,
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
