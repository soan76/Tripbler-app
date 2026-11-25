import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripbler/core/config/api_config.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/services/photo_normalizer.dart';
import 'package:tripbler/services/photo_translation_api_service.dart';

http.Response _json(Object body, int status) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

const _paragraphs = [
  OcrParagraph(
    id: 'p1',
    text: '醤油ラーメン 980円',
    box: Rect.fromLTWH(10, 20, 300, 40),
  ),
  OcrParagraph(id: 'p2', text: '食券', box: Rect.fromLTWH(10, 80, 100, 30)),
];

Map<String, dynamic> _body(List<Map<String, dynamic>> paragraphs) => {
  'sourceLanguageCode': 'ja',
  'targetLanguageCode': 'ko',
  'paragraphs': paragraphs,
};

Map<String, dynamic> _para(String id, {Map<String, dynamic>? extra}) => {
  'id': id,
  'original': 'o$id',
  'translated': 't$id',
  'uncertain': false,
  'translationSource': 'AI',
  'pronunciation': null,
  'prices': <Object>[],
  ...?extra,
};

void main() {
  late Directory dir;
  late NormalizedPhoto photo;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('photo_api_test');
    final file = File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3]);
    photo = NormalizedPhoto(path: file.path, width: 1200, height: 900);
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<Object?> call(
    MockClient client, {
    Duration timeout = PhotoTranslationApiService.defaultTimeout,
  }) async {
    final service = PhotoTranslationApiService(
      client: client,
      timeout: timeout,
    );

    try {
      return await service.translate(
        photo: photo,
        paragraphs: _paragraphs,
        sourceLanguageCode: 'ja',
        targetLanguageCode: 'ko',
        authorizationHeader: 'Bearer token',
      );
    } on ApiException catch (error) {
      return error;
    }
  }

  test('sendsMultipartWithImageAndJsonParts', () async {
    late http.BaseRequest sent;
    late String raw;
    final client = MockClient.streaming((request, stream) async {
      sent = request;
      raw = latin1.decode(await stream.toBytes());
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(_body([_para('p1')])))),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await call(client);

    expect(sent.method, 'POST');
    expect(sent.url, ApiConfig.translationPhotoUri);
    expect(sent.headers['Authorization'], 'Bearer token');
    expect(sent.headers['content-type'], startsWith('multipart/form-data'));
    expect(raw, contains('name="image"'));
    expect(raw, contains('filename="photo.jpg"'));
    expect(raw, contains('content-type: image/jpeg'));
    expect(raw, contains('name="request"'));
    expect(raw, contains('content-type: application/json'));

    final jsonStart = raw.indexOf('{');
    final jsonEnd = raw.lastIndexOf('}') + 1;
    final json =
        jsonDecode(
              utf8.decode(latin1.encode(raw.substring(jsonStart, jsonEnd))),
            )
            as Map<String, dynamic>;
    expect(json['sourceLanguageCode'], 'ja');
    expect(json['targetLanguageCode'], 'ko');
    expect(json['imageWidth'], 1200);
    expect(json['imageHeight'], 900);
    final paragraphs = json['paragraphs'] as List;
    expect(paragraphs[0]['id'], 'p1');
    expect(paragraphs[0]['text'], '醤油ラーメン 980円');
    expect(paragraphs[0]['box'], {
      'left': 10,
      'top': 20,
      'width': 300,
      'height': 40,
    });
  });

  test('parsesParagraphsAndPrices', () async {
    final client = MockClient(
      (_) async => _json(
        _body([
          _para(
            'p1',
            extra: {
              'pronunciation': '쇼유 라멘',
              'prices': [
                {
                  'text': '980円',
                  'amount': 980,
                  'currency': 'JPY',
                  'confirmed': true,
                  'krwAmount': 9060,
                  'krwRate': 9.245,
                  'rateFetchedAt': '2026-11-22T09:30:00',
                  'rateStale': true,
                },
              ],
            },
          ),
          _para('p2'),
        ]),
        200,
      ),
    );

    final result = await call(client) as PhotoTranslationResult;

    expect(result.sourceLanguageCode, 'ja');
    expect(result.paragraphs, hasLength(2));
    final first = result.paragraphs[0];
    expect(first.translated, 'tp1');
    expect(first.pronunciation, '쇼유 라멘');
    final price = first.prices.single;
    expect(price.amount, 980.0);
    expect(price.currency, 'JPY');
    expect(price.confirmed, isTrue);
    expect(price.krwAmount, 9060.0);
    expect(price.krwRate, 9.245);
    expect(price.rateFetchedAt, DateTime(2026, 11, 22, 9, 30));
    expect(price.rateStale, isTrue);
    expect(result.paragraphs[1].pronunciation, isNull);
  });

  test('ignoresUnknownAndDuplicateIds', () async {
    final client = MockClient(
      (_) async => _json(
        _body([
          _para('p1'),
          _para('p9'),
          _para('p1', extra: {'translated': '두번째'}),
          _para('p2'),
        ]),
        200,
      ),
    );

    final result = await call(client) as PhotoTranslationResult;

    expect(result.paragraphs.map((p) => p.id), ['p1', 'p2']);
    expect(result.paragraphs[0].translated, 'tp1');
  });

  test('missingIds_resultHasFewerParagraphs', () async {
    final client = MockClient((_) async => _json(_body([_para('p2')]), 200));

    final result = await call(client) as PhotoTranslationResult;

    expect(result.paragraphs.map((p) => p.id), ['p2']);
  });

  test('uncertainAndOcrTextSourceParsed', () async {
    final client = MockClient(
      (_) async => _json(
        _body([
          _para(
            'p1',
            extra: {'uncertain': true, 'translationSource': 'OCR_TEXT'},
          ),
        ]),
        200,
      ),
    );

    final result = await call(client) as PhotoTranslationResult;

    expect(result.paragraphs.single.uncertain, isTrue);
    expect(result.paragraphs.single.source, PhotoTranslationSource.ocrText);
  });

  test('unknownTranslationSource_throwsApiException', () async {
    final client = MockClient(
      (_) async => _json(
        _body([
          _para('p1', extra: {'translationSource': 'ORIGINAL'}),
        ]),
        200,
      ),
    );

    final error = await call(client) as ApiException;

    expect(error.message, '번역 응답 형식이 올바르지 않습니다.');
  });

  test('unconfirmedPriceHasNullKrw', () async {
    final client = MockClient(
      (_) async => _json(
        _body([
          _para(
            'p1',
            extra: {
              'prices': [
                {
                  'text': '12',
                  'amount': null,
                  'currency': null,
                  'confirmed': false,
                  'krwAmount': null,
                  'krwRate': null,
                  'rateFetchedAt': null,
                  'rateStale': false,
                },
              ],
            },
          ),
        ]),
        200,
      ),
    );

    final result = await call(client) as PhotoTranslationResult;
    final price = result.paragraphs.single.prices.single;

    expect(price.confirmed, isFalse);
    expect(price.amount, isNull);
    expect(price.currency, isNull);
    expect(price.krwAmount, isNull);
    expect(price.rateFetchedAt, isNull);
  });

  test('http429_throwsApiExceptionWithCode', () async {
    final client = MockClient(
      (_) async => _json({
        'code': 'TOO_MANY_REQUESTS',
        'message': '요청이 너무 많습니다. 30초 뒤 다시 시도해 주세요.',
      }, 429),
    );

    final error = await call(client) as ApiException;

    expect(error.statusCode, 429);
    expect(error.code, 'TOO_MANY_REQUESTS');
    expect(error.message, '요청이 너무 많습니다. 30초 뒤 다시 시도해 주세요.');
  });

  test('http413_usesPhotoTooLargeMessage', () async {
    final client = MockClient(
      (_) async => _json({'code': 'PAYLOAD_TOO_LARGE', 'message': 'x'}, 413),
    );

    final error = await call(client) as ApiException;

    expect(error.statusCode, 413);
    expect(error.code, 'PAYLOAD_TOO_LARGE');
    expect(error.message, contains('사진이 너무 커서'));
  });

  test('timeout_throwsNetworkApiException', () async {
    final slow = MockClient((_) => Completer<http.Response>().future);
    final timeout =
        await call(slow, timeout: const Duration(milliseconds: 10))
            as ApiException;
    expect(timeout.isNetworkError, isTrue);
    expect(timeout.message, contains('시간이 초과'));

    final broken = MockClient((_) async => throw http.ClientException('down'));
    final offline = await call(broken) as ApiException;
    expect(offline.isNetworkError, isTrue);
  });

  test('brokenJson_throwsApiException', () async {
    final client = MockClient((_) async => http.Response('not json', 200));

    final error = await call(client) as ApiException;

    expect(error.statusCode, 200);
    expect(error.message, '번역 응답 형식이 올바르지 않습니다.');
  });
}
