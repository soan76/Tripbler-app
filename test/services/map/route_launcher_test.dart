import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/services/map/route_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

PlaceModel _place({
  String id = 'ChIJN1t_tDeuEmsRUsoyG83frY4',
  String name = '국립중앙박물관',
  double? latitude = 37.5,
  double? longitude = 126.9,
}) {
  return PlaceModel(
    id: id,
    name: name,
    latitude: latitude,
    longitude: longitude,
    address: '주소',
    rating: null,
    category: 'museum',
    openNow: null,
  );
}

void main() {
  group('directionsUri', () {
    test('Google 지도 길찾기 형식에 이름과 장소 ID를 넣고 출발지·이동 수단은 넣지 않는다', () {
      final uri = RouteLauncher.directionsUri(_place());

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters, {
        'api': '1',
        'destination': '국립중앙박물관',
        'destination_place_id': 'ChIJN1t_tDeuEmsRUsoyG83frY4',
      });
    });

    test('이름의 &·#·공백·한글이 인코딩돼 다른 파라미터로 새지 않는다', () {
      final uri = RouteLauncher.directionsUri(_place(name: '카페 A&B #서울'));

      expect(uri.queryParameters['destination'], '카페 A&B #서울');
      expect(uri.queryParameters.keys, [
        'api',
        'destination',
        'destination_place_id',
      ]);
      expect(uri.fragment, isEmpty);
      expect(uri.toString(), isNot(contains('#')));
      expect(uri.toString(), contains('%26'));
    });

    test('좌표가 없는 장소도 장소 ID로 URL을 만든다', () {
      final uri = RouteLauncher.directionsUri(
        _place(latitude: null, longitude: null),
      );

      expect(
        uri.queryParameters['destination_place_id'],
        'ChIJN1t_tDeuEmsRUsoyG83frY4',
      );
    });
  });

  group('openDirections', () {
    test('외부 앱 모드로 한 번 열고 성공을 돌려준다', () async {
      final calls = <(Uri, LaunchMode)>[];
      final launcher = RouteLauncher(
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          calls.add((url, mode));
          return true;
        },
      );

      final result = await launcher.openDirections(_place());

      expect(result, RouteLaunchResult.opened);
      expect(calls, hasLength(1));
      expect(calls.single.$1, RouteLauncher.directionsUri(_place()));
      expect(calls.single.$2, LaunchMode.externalApplication);
    });

    test('false를 돌려받으면 실패로 알린다', () async {
      final launcher = RouteLauncher(
        launch: (url, {mode = LaunchMode.platformDefault}) async => false,
      );

      expect(await launcher.openDirections(_place()), RouteLaunchResult.failed);
      expect(launcher.isLaunching, isFalse);
    });

    test('PlatformException이 나면 실패로 알리고 다음 요청을 받는다', () async {
      var calls = 0;
      final launcher = RouteLauncher(
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          calls++;
          if (calls == 1) {
            throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
          }
          return true;
        },
      );

      expect(await launcher.openDirections(_place()), RouteLaunchResult.failed);
      expect(launcher.isLaunching, isFalse);
      expect(await launcher.openDirections(_place()), RouteLaunchResult.opened);
      expect(calls, 2);
    });

    test('PlatformException 외의 예외도 실패로 알리고 다음 요청을 받는다', () async {
      final errors = <Object>[
        MissingPluginException('no url_launcher'),
        UnimplementedError('unsupported platform'),
        ArgumentError('bad url'),
      ];

      for (final error in errors) {
        final launcher = RouteLauncher(
          launch: (url, {mode = LaunchMode.platformDefault}) async =>
              throw error,
        );

        expect(
          await launcher.openDirections(_place()),
          RouteLaunchResult.failed,
          reason: '$error',
        );
        expect(launcher.isLaunching, isFalse);
      }
    });

    test('열기가 끝나기 전에 다시 누르면 무시하고, 끝난 뒤에는 다시 연다', () async {
      final pending = Completer<bool>();
      var calls = 0;
      final launcher = RouteLauncher(
        launch: (url, {mode = LaunchMode.platformDefault}) {
          calls++;
          return calls == 1 ? pending.future : Future.value(true);
        },
      );

      final first = launcher.openDirections(_place());
      expect(launcher.isLaunching, isTrue);
      expect(
        await launcher.openDirections(_place()),
        RouteLaunchResult.ignored,
      );
      expect(calls, 1);

      pending.complete(true);
      expect(await first, RouteLaunchResult.opened);
      expect(launcher.isLaunching, isFalse);

      expect(await launcher.openDirections(_place()), RouteLaunchResult.opened);
      expect(calls, 2);
    });
  });
}
