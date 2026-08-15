import 'package:flutter/material.dart';

import '../../models/place_model.dart';

class PlaceDetailCard extends StatelessWidget {
  final PlaceModel place;
  final VoidCallback onClose;
  final VoidCallback? onDetailPressed;
  final VoidCallback? onRoutePressed;

  const PlaceDetailCard({
    super.key,
    required this.place,
    required this.onClose,
    this.onDetailPressed,
    this.onRoutePressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // 라이트/다크 모드에 따라 카드 배경 변경
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place, color: colorScheme.error, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    place.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  tooltip: '닫기',
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              place.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  context: context,
                  icon: Icons.category_outlined,
                  label: place.category,
                ),

                if (place.rating != null)
                  _buildInfoChip(
                    context: context,
                    icon: Icons.star,
                    label: place.rating!.toStringAsFixed(1),
                  ),

                if (place.openNow != null)
                  _buildInfoChip(
                    context: context,
                    icon: place.openNow!
                        ? Icons.check_circle_outline
                        : Icons.highlight_off_outlined,
                    label: place.openNow! ? '영업 중' : '영업 종료',
                  ),
              ],
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDetailPressed,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('상세 보기'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onRoutePressed,
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('길찾기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        // 라이트/다크 모드에 따라 Chip 배경 변경
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
