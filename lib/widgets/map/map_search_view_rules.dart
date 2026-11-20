import '../../providers/map/map_state.dart';
import 'place_search_bar.dart';

/// 지도 화면 검색 UI의 상태 전환 규칙.
///
/// `MapScreen`은 지도 플랫폼 뷰 때문에 위젯 테스트가 어려워, 판단만 따로 떼어
/// 단위 테스트한다.
class MapSearchViewRules {
  const MapSearchViewRules._();

  /// 로그인 상태로 검색창을 쓸 수 있는지 정한다.
  static PlaceSearchAvailability availabilityOf({
    required bool isAuthenticated,
    required bool sessionRestoreFailed,
  }) {
    if (isAuthenticated) {
      return PlaceSearchAvailability.ready;
    }

    // 일시적 장애로 복구를 기다리는 중이면 검색을 보류하고 상단 배너의 다시 시도를 쓴다.
    if (sessionRestoreFailed) {
      return PlaceSearchAvailability.restorePending;
    }

    return PlaceSearchAvailability.signedOut;
  }

  /// 장소가 새로 선택된 순간인지. 이때 결과 목록을 접는다.
  ///
  /// 선택 해제(null)나 같은 장소의 상세 갱신은 해당하지 않으므로, 카드가 열린 채
  /// 사용자가 펼친 목록은 그대로 둔다.
  static bool isNewSelection({
    required String? previousId,
    required String? currentId,
  }) {
    return currentId != null && currentId != previousId;
  }

  /// 검색 입력과 목록 펼침을 비워야 하는지.
  ///
  /// 검색할 수 있는 상태에서 벗어났거나(로그아웃·세션 만료), 비로그인·복구 대기로
  /// 바뀐 순간이다. MapNotifier가 검색 결과를 비우는 것과 맞춰 화면 상태도 비운다.
  static bool shouldResetSearchInput({
    required PlaceSearchAvailability previous,
    required PlaceSearchAvailability current,
  }) {
    return previous != current && current != PlaceSearchAvailability.ready;
  }

  /// 인증 상태가 바뀌었을 때 검색 입력과 목록 펼침을 비워야 하는지.
  ///
  /// [shouldResetSearchInput]에 더해, 다른 탭에 있는 동안 로그아웃→재로그인이 하나로
  /// 합쳐져 도착한 경우(검색 가능 상태는 그대로 ready지만 세션 번호가 바뀜)에도 비운다.
  static bool shouldResetOnAuthChange({
    required PlaceSearchAvailability previous,
    required PlaceSearchAvailability current,
    required bool sessionChanged,
  }) {
    return shouldResetSearchInput(previous: previous, current: current) ||
        (sessionChanged &&
            previous == PlaceSearchAvailability.ready &&
            current == PlaceSearchAvailability.ready);
  }

  /// Android 뒤로가기로 되돌릴 단계(카드 닫기·목록 접기·검색 해제)가 남았는지.
  static bool hasBackStep({
    required bool hasSelectedPlace,
    required bool resultsExpanded,
    required MapSearchStatus searchStatus,
    required bool hasSearchText,
  }) {
    return hasSelectedPlace ||
        resultsExpanded ||
        searchStatus != MapSearchStatus.idle ||
        hasSearchText;
  }

  /// 지도 탭에 돌아왔을 때 미뤄 둔 결과 카메라 맞춤을 할지.
  ///
  /// 그사이 장소를 골라 카드가 열려 있으면 그 장소를 보고 있으므로 옮기지 않는다.
  static bool shouldFitResultsOnTabEnter({
    required bool fitResults,
    required MapSearchStatus searchStatus,
    required bool hasSelectedPlace,
  }) {
    return fitResults &&
        searchStatus == MapSearchStatus.success &&
        !hasSelectedPlace;
  }
}
