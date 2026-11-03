import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_snapshot_store.dart';

/// 기기 저장소 대신 메모리에 차트 스냅샷을 두는 테스트용 저장소.
/// 실제 저장소의 정적 쓰기 큐를 거치지 않으므로, 앞선 위젯 테스트가 남긴
/// 쓰기 때문에 다음 테스트의 읽기·쓰기가 멈추지 않는다.
class MemorySnapshots extends ChartSnapshotStore {
  final Map<String, ChartData> saved = {};
  final List<String> reads = [];

  @override
  Future<ChartData?> read(String key, {required bool crypto}) async {
    reads.add(key);
    return saved[key];
  }

  @override
  Future<void> write(String key, ChartData data) async => saved[key] = data;
}
