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
    return Positioned(
      right: 16,
      bottom: bottom,
      child: FloatingActionButton(
        heroTag: 'currentLocationButton',
        onPressed: isLoading ? null : onPressed,
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
