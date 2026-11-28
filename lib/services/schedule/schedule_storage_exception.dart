/// 일정 저장소를 열거나 쓰지 못했다. 이때 계속 쓰면 기존 일정을 잃을 수 있어, 상태는
/// 불러오기 실패(다시 시도)로 두고 추가·백업·되살리기를 막는다.
class ScheduleStorageException implements Exception {
  const ScheduleStorageException(this.message);

  final String message;

  @override
  String toString() => 'ScheduleStorageException: $message';
}
