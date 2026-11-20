import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/map/map_state.dart';
import 'package:tripbler/widgets/map/map_search_view_rules.dart';
import 'package:tripbler/widgets/map/place_search_bar.dart';

void main() {
  group('availabilityOf', () {
    test('로그인 상태면 검색할 수 있다', () {
      expect(
        MapSearchViewRules.availabilityOf(
          isAuthenticated: true,
          sessionRestoreFailed: false,
        ),
        PlaceSearchAvailability.ready,
      );
    });

    test('복구 실패로 대기 중이면 복구 대기, 아니면 비로그인', () {
      expect(
        MapSearchViewRules.availabilityOf(
          isAuthenticated: false,
          sessionRestoreFailed: true,
        ),
        PlaceSearchAvailability.restorePending,
      );
      expect(
        MapSearchViewRules.availabilityOf(
          isAuthenticated: false,
          sessionRestoreFailed: false,
        ),
        PlaceSearchAvailability.signedOut,
      );
    });
  });

  group('isNewSelection', () {
    test('선택이 없다가 생기거나 다른 장소로 바뀌면 새 선택이다', () {
      expect(
        MapSearchViewRules.isNewSelection(previousId: null, currentId: 'a'),
        isTrue,
      );
      expect(
        MapSearchViewRules.isNewSelection(previousId: 'a', currentId: 'b'),
        isTrue,
      );
    });

    test('같은 장소 유지(상세 갱신)나 선택 해제는 새 선택이 아니다', () {
      expect(
        MapSearchViewRules.isNewSelection(previousId: 'a', currentId: 'a'),
        isFalse,
      );
      expect(
        MapSearchViewRules.isNewSelection(previousId: 'a', currentId: null),
        isFalse,
      );
      expect(
        MapSearchViewRules.isNewSelection(previousId: null, currentId: null),
        isFalse,
      );
    });
  });

  group('shouldResetSearchInput', () {
    bool reset(
      PlaceSearchAvailability previous,
      PlaceSearchAvailability current,
    ) {
      return MapSearchViewRules.shouldResetSearchInput(
        previous: previous,
        current: current,
      );
    }

    test('로그아웃·세션 만료로 검색할 수 없게 되면 비운다', () {
      expect(
        reset(PlaceSearchAvailability.ready, PlaceSearchAvailability.signedOut),
        isTrue,
      );
    });

    test('복구 대기에서 비로그인이 확인되거나 복구 대기로 바뀌면 비운다', () {
      expect(
        reset(
          PlaceSearchAvailability.restorePending,
          PlaceSearchAvailability.signedOut,
        ),
        isTrue,
      );
      expect(
        reset(
          PlaceSearchAvailability.signedOut,
          PlaceSearchAvailability.restorePending,
        ),
        isTrue,
      );
    });

    test('로그인하거나 상태가 그대로면 비우지 않는다', () {
      expect(
        reset(PlaceSearchAvailability.signedOut, PlaceSearchAvailability.ready),
        isFalse,
      );
      expect(
        reset(
          PlaceSearchAvailability.restorePending,
          PlaceSearchAvailability.ready,
        ),
        isFalse,
      );
      expect(
        reset(PlaceSearchAvailability.ready, PlaceSearchAvailability.ready),
        isFalse,
      );
      expect(
        reset(
          PlaceSearchAvailability.signedOut,
          PlaceSearchAvailability.signedOut,
        ),
        isFalse,
      );
    });
  });

  group('shouldResetOnAuthChange', () {
    const ready = PlaceSearchAvailability.ready;
    const signedOut = PlaceSearchAvailability.signedOut;
    const restorePending = PlaceSearchAvailability.restorePending;

    bool reset(
      PlaceSearchAvailability previous,
      PlaceSearchAvailability current, {
      required bool sessionChanged,
    }) {
      return MapSearchViewRules.shouldResetOnAuthChange(
        previous: previous,
        current: current,
        sessionChanged: sessionChanged,
      );
    }

    test('검색할 수 없게 되면 세션 번호와 상관없이 비운다', () {
      expect(reset(ready, signedOut, sessionChanged: false), isTrue);
      expect(reset(ready, signedOut, sessionChanged: true), isTrue);
      expect(reset(signedOut, restorePending, sessionChanged: false), isTrue);
    });

    test('로그아웃→재로그인이 합쳐져 ready 그대로 세션만 바뀌면 비운다', () {
      expect(reset(ready, ready, sessionChanged: true), isTrue);
    });

    test('ready 그대로 세션도 같으면 비우지 않는다', () {
      expect(reset(ready, ready, sessionChanged: false), isFalse);
    });

    test('ready로 들어오는 로그인은 세션이 바뀌어도 비우지 않는다', () {
      expect(reset(signedOut, ready, sessionChanged: true), isFalse);
      expect(reset(restorePending, ready, sessionChanged: true), isFalse);
    });

    test('ready가 아닌 상태가 그대로면 세션이 바뀌어도 비우지 않는다', () {
      expect(reset(signedOut, signedOut, sessionChanged: true), isFalse);
    });
  });

  group('hasBackStep', () {
    bool hasBackStep({
      bool hasSelectedPlace = false,
      bool resultsExpanded = false,
      MapSearchStatus searchStatus = MapSearchStatus.idle,
      bool hasSearchText = false,
    }) {
      return MapSearchViewRules.hasBackStep(
        hasSelectedPlace: hasSelectedPlace,
        resultsExpanded: resultsExpanded,
        searchStatus: searchStatus,
        hasSearchText: hasSearchText,
      );
    }

    test('아무것도 없고 검색 전(idle)이면 되돌릴 단계가 없다', () {
      expect(hasBackStep(), isFalse);
    });

    test('카드·목록 펼침·검색어 중 하나라도 있으면 되돌릴 단계가 있다', () {
      expect(hasBackStep(hasSelectedPlace: true), isTrue);
      expect(hasBackStep(resultsExpanded: true), isTrue);
      expect(hasBackStep(hasSearchText: true), isTrue);
    });

    test('검색 상태가 idle이 아니면 되돌릴 단계가 있다', () {
      for (final status in [
        MapSearchStatus.loading,
        MapSearchStatus.success,
        MapSearchStatus.failure,
      ]) {
        expect(hasBackStep(searchStatus: status), isTrue, reason: '$status');
      }
    });
  });

  group('shouldFitResultsOnTabEnter', () {
    bool fit({
      bool fitResults = true,
      MapSearchStatus searchStatus = MapSearchStatus.success,
      bool hasSelectedPlace = false,
    }) {
      return MapSearchViewRules.shouldFitResultsOnTabEnter(
        fitResults: fitResults,
        searchStatus: searchStatus,
        hasSelectedPlace: hasSelectedPlace,
      );
    }

    test('맞춤을 미뤄 뒀고 검색 성공, 선택 장소가 없으면 맞춘다', () {
      expect(fit(), isTrue);
    });

    test('미뤄 둔 맞춤이 없으면 맞추지 않는다', () {
      expect(fit(fitResults: false), isFalse);
    });

    test('검색이 성공 상태가 아니면 맞추지 않는다', () {
      for (final status in [
        MapSearchStatus.idle,
        MapSearchStatus.loading,
        MapSearchStatus.failure,
      ]) {
        expect(fit(searchStatus: status), isFalse, reason: '$status');
      }
    });

    test('그사이 장소를 골라 카드가 열려 있으면 맞추지 않는다', () {
      expect(fit(hasSelectedPlace: true), isFalse);
    });
  });
}
