import 'package:flutter/material.dart';

import '../../models/schedule/schedule_item.dart';
import '../../utils/schedule/schedule_labels.dart';

/// 장소 고르기 화면 아래의 장소 카드. 지도 탭 카드의 "길찾기" 자리에 "이 장소 선택"이 있다.
///
/// 높이가 제한되면 카드 안에서 스크롤한다(지도 위 배치가 남은 높이만큼만 준다).
class PlacePickerCard extends StatelessWidget {
  const PlacePickerCard({
    super.key,
    required this.place,
    required this.onSelect,
    required this.onClose,
  });

  static const String selectLabel = '이 장소 선택';

  final ScheduledPlace place;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final address = place.address;
    final coordinates = ScheduleLabels.coordinates(place);

    return Material(
      color: colorScheme.surface,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        header: true,
                        child: Text(
                          place.name,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    tooltip: '장소 카드 닫기',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (address != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        address,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (coordinates != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        coordinates,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onSelect,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(selectLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
