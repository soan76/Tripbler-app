import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripbler/core/config/api_config.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/services/line_translation_api_service.dart';

http.Response _json(Object body, int status) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<Object?> _call(
  MockClient client, {
  List<String> lines = const ['醤油ラーメン 980円', '食券'],
  Duration timeout = LineTranslationApiService.defaultTimeout,
}) async {
  final service = LineTranslationApiService(client: client, timeout: timeout);

  try {
    return await service.translateLines(
      lines: lines,
      sourceLanguageCode: 'auto',
      targetLanguageCode: 'ko',
      authorizationHeader: 'Bearer token',
    );
  } on ApiException catch (error) {
    return error;
  }
}

void main() {
  test('토큰과 줄 목록을 보내고 번역·발음·가격을 읽는다', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return _json({
        'sourceLanguageCode': 'ja',
        'targetLanguageCode': 'ko',
        'lines': [
          {
            'original': '醤油ラーメン 980円',
            'translated': '간장 라멘 980엔',
            'pronunciation': '쇼유 라멘',
            'price': {
              'text': '980円',
              'amount': 980,
              'currency': 'JPY',
              'krwAmount': 9060,
              'krwRate': 9.245,
              'rateFetchedAt': '2026-11-22T09:30:00',
              'rateStale': false,
            },
          },
          {
            'original': '食券',
            'translated': '식권',
            'pronunciation': ' ',
            'price': null,
          },
        ],
      }, 200);
    });

    final result = await _call(client);

    expect(sent.method, 'POST');
    expect(sent.url, ApiConfig.translationLinesUri);
    expect(sent.headers['Authorization'], 'Bearer token');
    expect(jsonDecode(sent.body), {
      'lines': ['醤油ラーメン 980円', '食券'],
      'sourceLanguageCode': 'auto',
      'targetLanguageCode': 'ko',
    });

    final lines = (result! as dynamic).lines as List;
    final first = lines[0];
    expect(first.translated, '간장 라멘 980엔');
    expect(first.pronunciation, '쇼유 라멘');
    expect(first.price.krwAmount, 9060);
    expect(first.price.currency, 'JPY');
    expect(first.price.rateFetchedAt, DateTime(2026, 11, 22, 9, 30));
    // 공백뿐인 발음은 없는 것으로 본다.
    expect(lines[1].pronunciation, isNull);
    expect(lines[1].price, isNull);
  });

  test('줄 수가 요청과 다르면 형식 오류로 본다', () async {
    final client = MockClient(
      (_) async => _json({
        'sourceLanguageCode': 'ja',
        'targetLanguageCode': 'ko',
        'lines': [
          {'original': 'a', 'translated': 'b'},
        ],
      }, 200),
    );

    final error = await _call(client) as ApiException;

    expect(error.message, '번역 응답 형식이 올바르지 않습니다.');
  });

  test('429는 서버 문구와 코드를 그대로 쓴다', () async {
    final client = MockClient(
      (_) async => _json({
        'status': 429,
        'code': 'TOO_MANY_REQUESTS',
        'message': '요청이 너무 많습니다. 30초 뒤 다시 시도해 주세요.',
      }, 429),
    );

    final error = await _call(client) as ApiException;

    expect(error.statusCode, 429);
    expect(error.code, 'TOO_MANY_REQUESTS');
    expect(error.message, '요청이 너무 많습니다. 30초 뒤 다시 시도해 주세요.');
  });

  test('401은 상태 코드를 담아 던져 토큰 재발급이 동작하게 한다', () async {
    final client = MockClient((_) async => http.Response('', 401));

    final error = await _call(client) as ApiException;

    expect(error.statusCode, 401);
  });

  test('503은 서버 문구 대신 일시적 사용 불가 안내를 쓴다', () async {
    final client = MockClient(
      (_) async => _json({
        'code': 'TRANSLATION_PROVIDER_UNAVAILABLE',
        'message': '현재 번역 서비스를 이용할 수 없습니다.',
      }, 503),
    );

    final error = await _call(client) as ApiException;

    expect(error.statusCode, 503);
    expect(error.message, contains('일시적으로'));
  });

  test('시간 초과와 연결 실패는 네트워크 오류다', () async {
    final slow = MockClient((_) => Completer<http.Response>().future);
    final timeout =
        await _call(slow, timeout: const Duration(milliseconds: 10))
            as ApiException;
    expect(timeout.isNetworkError, isTrue);
    expect(timeout.message, contains('시간이 초과'));

    final broken = MockClient((_) async => throw http.ClientException('down'));
    final offline = await _call(broken) as ApiException;
    expect(offline.isNetworkError, isTrue);
  });

  test('서버 최악 처리 시간(Claude 90초 + Google 8초 + 환율 5초)보다 여유 있게 기다린다', () {
    const serverWorstCase = Duration(seconds: 90 + 8 + 5);

    expect(
      LineTranslationApiService.defaultTimeout,
      greaterThanOrEqualTo(serverWorstCase + const Duration(seconds: 10)),
    );
  });
}
