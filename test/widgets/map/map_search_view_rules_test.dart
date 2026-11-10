import 'package:flutter_test/flutter_test.dart';
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
}
