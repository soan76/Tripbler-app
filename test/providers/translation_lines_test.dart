import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/translation/line_translation_result.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/translation_provider.dart';
import 'package:tripbler/repositories/auth/auth_exceptions.dart';
import 'package:tripbler/services/line_translation_api_service.dart';
import 'package:tripbler/services/ocr_service.dart';
import 'package:tripbler/services/translation_service.dart';

import '../helpers/fake_auth_notifier.dart';

/// 줄 단위 인식과 통번역 인식을 각각 기록한다.
class _FakeOcrService extends OcrService {
  _FakeOcrService({this.lines = const <String>[], this.text = ''});

  final List<String> lines;
  final String text;
  int lineCalls = 0;
  int textCalls = 0;

  @override
  Future<List<String>> recognizeLines({
    required String imagePath,
    required String sourceLanguageCode,
  }) async {
    lineCalls++;
    return lines;
  }

  @override
  Future<String> recognizeText({
    required String imagePath,
    required String sourceLanguageCode,
  }) async {
    textCalls++;
    return text;
  }
}

/// 요청마다 Completer를 만들어 테스트가 응답 순서·실패를 정한다.
class _FakeLineApi extends LineTranslationApiService {
  final List<
    ({
      List<String> lines,
      String source,
      String target,
      String header,
      Completer<LineTranslationResult> completer,
    })
  >
  calls = [];

  @override
  Future<LineTranslationResult> translateLines({
    required List<String> lines,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    required String authorizationHeader,
  }) {
    final completer = Completer<LineTranslationResult>();
    calls.add((
      lines: lines,
      source: sourceLanguageCode,
      target: targetLanguageCode,
      header: authorizationHeader,
      completer: completer,
    ));
    return completer.future;
  }
}

class _FakeTranslationService extends TranslationService {
  int calls = 0;

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    calls++;
    return '통번역';
  }
}

LineTranslationResult _result(List<String> originals, {String target = 'ko'}) {
  return LineTranslationResult(
    sourceLanguageCode: 'ja',
    targetLanguageCode: target,
    lines: [
      for (final original in originals)
        TranslatedLine(
          original: original,
          translated: '$target:$original',
          pronunciation: '발음',
        ),
    ],
  );
}

void main() {
  late _FakeOcrService ocr;
  late _FakeLineApi api;
  late _FakeTranslationService translator;
  late FakeAuthNotifier auth;
  late ProviderContainer container;
  late Object? runnerError;

  ProviderContainer create({required bool signedIn, List<String>? lines}) {
    ocr = _FakeOcrService(
      lines: lines ?? const ['醤油ラーメン 980円', '食券'],
      text: '醤油ラーメン 980円\n食券',
    );
    api = _FakeLineApi();
    translator = _FakeTranslationService();
    auth = FakeAuthNotifier(initiallySignedIn: signedIn);
    runnerError = null;

    return ProviderContainer.test(
      overrides: [
        ocrServiceProvider.overrideWithValue(ocr),
        lineTranslationApiServiceProvider.overrideWithValue(api),
        translationServiceProvider.overrideWithValue(translator),
        authProvider.overrideWith(() => auth),
        authorizedRequestRunnerProvider.overrideWithValue(<T>(
          Future<T> Function(String) request,
        ) async {
          final error = runnerError;
          if (error != null) {
            throw error;
          }
          return request('Bearer test');
        }),
      ],
    );
  }

  TranslationNotifier notifier() =>
      container.read(translationProvider.notifier);
  TranslationState state() => container.read(translationProvider);

  test('로그인했으면 줄 단위로 읽어 줄별 번역을 보여 준다', () async {
    container = create(signedIn: true);

    final processing = notifier().processImage('a.jpg');
    await pumpEventQueue();

    expect(ocr.lineCalls, 1);
    expect(ocr.textCalls, 0);
    expect(api.calls.single.lines, ['醤油ラーメン 980円', '食券']);
    expect(api.calls.single.source, 'auto');
    expect(api.calls.single.header, 'Bearer test');
    expect(state().status, TranslationStatus.translating);

    api.calls.single.completer.complete(_result(['醤油ラーメン 980円', '食券']));
    await processing;

    expect(state().status, TranslationStatus.completed);
    expect(state().lineResult!.lines, hasLength(2));
    expect(state().translatedText, 'ko:醤油ラーメン 980円\nko:食券');
    expect(translator.calls, 0);
  });

  test('로그인하지 않았으면 지금처럼 통번역을 쓴다', () async {
    container = create(signedIn: false);

    await notifier().processImage('a.jpg');

    expect(ocr.textCalls, 1);
    expect(ocr.lineCalls, 0);
    expect(api.calls, isEmpty);
    expect(state().lineResult, isNull);
    expect(state().translatedText, '통번역');
  });

  test('언어를 바꾸면 이전 줄 결과를 지우고 새 언어로 다시 요청하며 늦은 응답은 버린다', () async {
    container = create(signedIn: true);

    final processing = notifier().processImage('a.jpg');
    await pumpEventQueue();
    notifier().changeTargetLanguage('en');
    await pumpEventQueue();

    expect(api.calls.map((call) => call.target), ['ko', 'en']);
    expect(state().lineResult, isNull);

    api.calls[1].completer.complete(
      _result(['醤油ラーメン 980円', '食券'], target: 'en'),
    );
    await pumpEventQueue();
    api.calls[0].completer.complete(_result(['醤油ラーメン 980円', '食券']));
    await processing;

    expect(state().lineResult!.targetLanguageCode, 'en');
    expect(state().lineResult!.lines.first.translated, 'en:醤油ラーメン 980円');
  });

  test('다시 찍으면 진행 중이던 줄별 번역 응답은 반영하지 않는다', () async {
    container = create(signedIn: true);

    final processing = notifier().processImage('a.jpg');
    await pumpEventQueue();
    notifier().resetForRetake();
    api.calls.single.completer.complete(_result(['醤油ラーメン 980円', '食券']));
    await processing;

    expect(state().lineResult, isNull);
    expect(state().recognizedLines, isEmpty);
    expect(state().status, TranslationStatus.cameraReady);
  });

  test('서버 오류는 서버가 준 안내 문구로 실패 상태가 된다', () async {
    container = create(signedIn: true);

    final processing = notifier().processImage('a.jpg');
    await pumpEventQueue();
    api.calls.single.completer.completeError(
      const ApiException(
        statusCode: 429,
        code: 'TOO_MANY_REQUESTS',
        message: '요청이 너무 많습니다.',
      ),
    );
    await processing;

    expect(state().status, TranslationStatus.failed);
    expect(state().errorMessage, '요청이 너무 많습니다.');
    expect(state().lineResult, isNull);
  });

  test('세션이 만료되면 다시 로그인하라고 안내한다', () async {
    container = create(signedIn: true);
    runnerError = const SessionExpiredException(1);

    await notifier().processImage('a.jpg');

    expect(state().status, TranslationStatus.failed);
    expect(state().errorMessage, contains('로그인이 만료'));
  });

  test('요청 중 세션이 바뀌었다는 오류면 다시 찍으라고 안내한다', () async {
    container = create(signedIn: true);
    runnerError = const SessionChangedException();

    await notifier().processImage('a.jpg');

    expect(state().status, TranslationStatus.failed);
    expect(state().errorMessage, contains('로그인 상태가 바뀌었습니다'));
    expect(state().lineResult, isNull);
  });

  test('네트워크 오류는 서비스가 준 연결 안내 문구를 그대로 보여 준다', () async {
    container = create(signedIn: true);

    final processing = notifier().processImage('a.jpg');
    await pumpEventQueue();
    api.calls.single.completer.completeError(
      const ApiException(message: '번역 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.'),
    );
    await processing;

    expect(state().status, TranslationStatus.failed);
    expect(state().errorMessage, '번역 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.');
  });

  test('줄 단위로 읽은 뒤 번역 전에 로그인이 풀리면 이어 붙인 원문으로 통번역한다', () async {
    container = create(signedIn: true);

    final processing = notifier().processImage('a.jpg');
    await pumpEventQueue();
    api.calls.single.completer.complete(_result(['醤油ラーメン 980円', '食券']));
    await processing;

    // 세션 번호는 그대로 두고 로그인 여부만 바꾼다(다음 번역 직전에 로그인이 풀린 상황).
    auth.isAuthenticated = false;
    notifier().changeTargetLanguage('en');
    await pumpEventQueue();

    expect(api.calls, hasLength(1));
    expect(translator.calls, 1);
    expect(state().lineResult, isNull);
    expect(state().translatedText, '통번역');
    expect(state().status, TranslationStatus.completed);
  });

  group('로그인 세션이 바뀌면', () {
    test('진행 중이던 줄별 번역을 버리고 사진·결과를 지워 카메라 화면으로 돌아간다', () async {
      container = create(signedIn: true);

      final processing = notifier().processImage('a.jpg');
      await pumpEventQueue();
      expect(state().status, TranslationStatus.translating);

      auth.signOut();
      api.calls.single.completer.complete(_result(['醤油ラーメン 980円', '食券']));
      await processing;

      expect(state().status, TranslationStatus.cameraReady);
      expect(state().selectedImagePath, isNull);
      expect(state().recognizedText, isEmpty);
      expect(state().recognizedLines, isEmpty);
      expect(state().lineResult, isNull);
      expect(state().translatedText, isEmpty);
      expect(state().errorMessage, isNull);
    });

    test('끝난 줄별 결과도 로그아웃하면 지운다', () async {
      container = create(signedIn: true);

      final processing = notifier().processImage('a.jpg');
      await pumpEventQueue();
      api.calls.single.completer.complete(_result(['醤油ラーメン 980円', '食券']));
      await processing;
      expect(state().lineResult, isNotNull);

      auth.signOut();

      expect(state().status, TranslationStatus.cameraReady);
      expect(state().lineResult, isNull);
      expect(state().selectedImagePath, isNull);
    });

    test('로그아웃→재로그인이 한 번에 와도 이전 계정의 결과를 지운다', () async {
      container = create(signedIn: true);

      final processing = notifier().processImage('a.jpg');
      await pumpEventQueue();
      api.calls.single.completer.complete(_result(['醤油ラーメン 980円', '食券']));
      await processing;

      auth.signOutAndInAtOnce();

      expect(state().lineResult, isNull);
      expect(state().status, TranslationStatus.cameraReady);
    });

    test('로그인하지 않고 찍은 통번역 결과도 로그인하면 지운다', () async {
      container = create(signedIn: false);

      await notifier().processImage('a.jpg');
      expect(state().translatedText, '통번역');

      auth.signIn();

      expect(state().translatedText, isEmpty);
      expect(state().selectedImagePath, isNull);
      expect(state().status, TranslationStatus.cameraReady);
    });

    test('결과가 없는 권한 확인·카메라 상태는 그대로 둔다', () {
      container = create(signedIn: true);
      notifier().setStatus(TranslationStatus.permissionDenied);

      auth.signOut();

      expect(state().status, TranslationStatus.permissionDenied);
    });
  });

  test('원문과 번역 언어가 같으면 서버에 보내지 않고 원문을 그대로 보여 준다', () async {
    container = create(signedIn: true);
    notifier().changeSourceLanguage('ko');
    notifier().changeTargetLanguage('ko');

    await notifier().processImage('a.jpg');

    expect(api.calls, isEmpty);
    expect(state().lineResult!.lines.first.translated, '醤油ラーメン 980円');
    expect(state().lineResult!.lines.first.pronunciation, isNull);
  });

  group('linesForRequest', () {
    test('빈 줄은 빼고 앞뒤 공백을 지운다', () {
      final (lines, omitted) = TranslationNotifier.linesForRequest([
        ' a ',
        '',
        '  ',
        'b',
      ]);

      expect(lines, ['a', 'b']);
      expect(omitted, 0);
    });

    test('50줄을 넘으면 뒤 줄은 빼고 뺀 줄 수를 돌려준다', () {
      final (lines, omitted) = TranslationNotifier.linesForRequest([
        for (var i = 0; i < 53; i++) 'line $i',
      ]);

      expect(lines, hasLength(50));
      expect(lines.last, 'line 49');
      expect(omitted, 3);
    });

    test('200자를 넘는 줄은 자르되 두 단위 문자를 반으로 자르지 않는다', () {
      final long = '${'a' * 199}😀tail';
      final (lines, _) = TranslationNotifier.linesForRequest([long]);

      expect(lines.single, 'a' * 199);
    });

    test('합계 5000자를 넘기는 줄부터는 뺀다', () {
      final (lines, omitted) = TranslationNotifier.linesForRequest([
        for (var i = 0; i < 26; i++) 'x' * 200,
      ]);

      expect(lines, hasLength(25));
      expect(omitted, 1);
    });
  });
}
