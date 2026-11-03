import 'package:flutter/foundation.dart';

import '../../models/chart_point.dart';
import 'chart_data_source.dart';

/// 카드 하나의 차트 조회 상태. 바뀔 때마다 새 객체로 교체한다.
/// 표시 값은 불변 [ChartData]를 그대로 담아, 기록 목록을 밖에서 고칠 수 없고
/// 상태를 바꿔도 같은 목록을 재사용한다.
@immutable
class ChartLoadState {
  const ChartLoadState({
    this.isLoading = false,
    this.hasLoaded = false,
    this.failed = false,
    this.stale = false,
    this.data,
  });

  static const initial = ChartLoadState();

  final bool isLoading;

  /// 표시할 값(저장값 포함)을 한 번이라도 받았는지.
  final bool hasLoaded;

  /// 마지막 조회가 실패했는지. 실패해도 이전 값은 [data]에 남는다.
  final bool failed;

  /// 표시 중인 값이 저장값이거나 갱신에 실패한 마지막 성공값인지.
  /// 화면 표시 판단은 이 값만 쓴다([ChartData.stale]과 다를 수 있다).
  final bool stale;

  /// 마지막으로 받은 값. 갱신에 실패해도 원래 조회 시각과 함께 유지한다.
  /// `data.stale`은 서버가 준 원래 값이라 표시 판단에는 [stale]을 쓴다.
  final ChartData? data;

  List<ChartPoint> get history => data?.history ?? const [];
  double? get currentRate => data?.currentRate;

  /// 표시 중인 값을 서버가 조회한 시각.
  DateTime? get fetchedAt => data?.fetchedAt;
  bool get historicalRate => data?.historicalRate ?? false;

  /// 오래된 값을 보여 주고 있어 안내가 필요한지.
  bool get showsOldData => history.isNotEmpty && (isLoading || stale || failed);

  /// 넘긴 값만 바꾼 새 상태를 만든다. 처음 상태로 되돌릴 때는 [initial]을 쓴다.
  ChartLoadState copyWith({
    bool? isLoading,
    bool? hasLoaded,
    bool? failed,
    bool? stale,
    ChartData? data,
  }) => ChartLoadState(
    isLoading: isLoading ?? this.isLoading,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    failed: failed ?? this.failed,
    stale: stale ?? this.stale,
    data: data ?? this.data,
  );
}
