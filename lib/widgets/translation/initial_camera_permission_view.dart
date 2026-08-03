import 'package:flutter/material.dart';
// 처음 권한 요청 화면
// 번역 화면에서 카메라 권한이 필요한 경우 표시되는 초기 권한 요청 뷰
class InitialCameraPermissionView extends StatelessWidget {
  final Future<void> Function() onRequestPermission;

  const InitialCameraPermissionView({
    super.key,
    required this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          children: [
            const Spacer(),
            // 카메라 권한 요청 이미지
            Image.asset(
              'assets/images/camera_permission.png',
              width: 180,
              height: 180,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 32),
            // 카메라 권한 요청 텍스트
            const Text(
              '번역을 위해 촬영 권한이 필요합니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  onRequestPermission();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  '접근 권한 허용',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
