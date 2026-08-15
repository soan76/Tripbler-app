import 'package:flutter/material.dart';

class CurrentLocationButton extends StatelessWidget {
  final bool isLoading;
  final double bottom;
  final VoidCallback? onPressed;

  const CurrentLocationButton({
    super.key,
    required this.isLoading,
    required this.bottom,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      right: 16,
      bottom: bottom,
      child: FloatingActionButton(
        heroTag: 'currentLocationButton',
        onPressed: isLoading ? null : onPressed,
        // 라이트/다크 모드에 따라 버튼 배경색 변경
        backgroundColor: colorScheme.primaryContainer,

        // 버튼 아이콘 색상
        foregroundColor: colorScheme.onPrimaryContainer,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }
}
