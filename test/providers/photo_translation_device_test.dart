import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/repositories/auth/auth_exceptions.dart';
import 'package:tripbler/services/translation_service.dart';

import '../helpers/fake_device_translation.dart';
import '../helpers/fake_photo_translation.dart';

// 기본 방식(사진 AI 번역·가짜가 아닐 때): 사진은 보내지 않고 동의도 묻지 않는다.
// 기기 OCR 문단의 글자만 로그인이면 줄별 번역, 아니면 통번역으로 번역한다.
// 진행 중 retake·화면 이탈·세션 변경은 photo_translation_device_lifecycle_test.dart.
void main() {
  late FakeNormalizer normalizer;
  late FakeOcr ocr;
  late FakeConsent consent;
  late FakeApi api;
  late FakeLineApi lineApi;
  late FakeTextService textService;
  late ProviderContainer container;

  ProviderContainer build({required bool signedIn}) =>
      buildDeviceTranslationContainer(
        signedIn: signedIn,
        normalizer: normalizer,
        ocr: ocr,
        consent: consent,
        api: api,
        lineApi: lineApi,
        textService: textService,
      );

  setUp(() {
    normalizer = FakeNormalizer();
    ocr = FakeOcr()
      ..lines = [fakeLine('醤油ラーメン', 0, 10), fakeLine('980円', 1, 100)];
    consent = FakeConsent();
    api = FakeApi();
    lineApi = FakeLineApi();
    textService = FakeTextService();
  });

  tearDown(() => container.dispose());

  PhotoTranslationState state() => container.read(photoTranslationProvider);
  PhotoTranslationNotifier notifier() =>
      container.read(photoTranslationProvider.notifier);

  Future<void> capture() async {
    await notifier().processPhoto('a.jpg');
    await pumpEventQueue();
  }

  /// 결과 문단을 (ID, 원문, 번역)으로 본다.
  List<(String, String, String)> attached() => [
    for (final p in state().result!.paragraphs)
      (p.id, p.original, p.translated),
  ];

  /// 상태의 문단마다 [prefix]를 붙인 번역이 같은 ID에 붙었는지 비교할 값.
  List<(String, String, String)> expectedWith(String prefix) => [
    for (final p in state().paragraphs) (p.id, p.text, '$prefix${p.text}'),
  ];

  test('signedIn_translatesTextOnly_withoutConsentOrPhotoUpload', () async {
    container = build(signedIn: true);

    await capture();

    expect(state().status, PhotoTranslationStatus.completed);
    expect(consent.acceptCalls, 0);
    expect(api.calls, isEmpty);
    expect(textService.calls, isEmpty);
    expect(lineApi.calls.single.header, 'Bearer t');
    expect(lineApi.calls.single.lines, ['醤油ラーメン', '980円']);
    final result = state().result!;
    expect(result.simulated, isFalse);
    expect(attached(), expectedWith('ko:'));
    expect(
      result.paragraphs.every(
        (p) => p.source == PhotoTranslationSource.deviceText,
      ),
      isTrue,
    );
  });

  test('signedOut_usesTextTranslation_perParagraph', () async {
    container = build(signedIn: false);

    await capture();

    expect(state().status, PhotoTranslationStatus.completed);
    expect(lineApi.calls, isEmpty);
    expect(api.calls, isEmpty);
    expect(textService.calls, ['醤油ラーメン', '980円']);
    expect(attached(), expectedWith('통:'));
  });

  test('sameLanguage_keepsOriginal_withoutCallingTranslation', () async {
    container = build(signedIn: false);
    notifier()
      ..changeSourceLanguage('ja')
      ..changeTargetLanguage('ja');

    await capture();

    expect(state().status, PhotoTranslationStatus.completed);
    expect(textService.calls, isEmpty);
    expect(lineApi.calls, isEmpty);
    expect(api.calls, isEmpty);
    expect(attached(), expectedWith(''));
    expect(
      state().result!.paragraphs.every(
        (p) => p.source == PhotoTranslationSource.original,
      ),
      isTrue,
    );
  });

  group('signedOut_textTranslationFailure', () {
    test('showsServiceMessage_andAllowsRetry', () async {
      container = build(signedIn: false);
      textService.errors['醤油ラーメン'] = const TranslationApiException(
        message: '번역 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );

      await capture();

      expect(state().status, PhotoTranslationStatus.failed);
      expect(state().errorMessage, '번역 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.');
      expect(state().canRetry, isTrue);
      expect(state().result, isNull);
    });

    test('retry_resendsSameParagraphs_andCompletes', () async {
      container = build(signedIn: false);
      textService.errors['980円'] = const TranslationApiException(
        message: '번역 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
      await capture();
      expect(state().canRetry, isTrue);

      textService.errors.clear();
      textService.calls.clear();
      await notifier().retry();
      await pumpEventQueue();

      expect(state().status, PhotoTranslationStatus.completed);
      expect(state().errorMessage, isNull);
      expect(textService.calls, ['醤油ラーメン', '980円']);
      expect(attached(), expectedWith('통:'));
    });
  });

  group('signedIn_lineTranslationFailure', () {
    Future<void> failWith(Object error) async {
      container = build(signedIn: true);
      lineApi.error = error;
      await capture();
      expect(state().status, PhotoTranslationStatus.failed);
      expect(state().result, isNull);
    }

    test('503_showsServerMessage_andAllowsRetry', () async {
      await failWith(
        const ApiException(statusCode: 503, message: '번역 서비스를 잠시 쓸 수 없습니다.'),
      );

      expect(state().errorMessage, '번역 서비스를 잠시 쓸 수 없습니다.');
      expect(state().canRetry, isTrue);

      lineApi.error = null;
      await notifier().retry();
      await pumpEventQueue();

      expect(lineApi.calls, hasLength(2));
      expect(state().status, PhotoTranslationStatus.completed);
      expect(attached(), expectedWith('ko:'));
    });

    test('401_doesNotAllowRetry_andRetryIsIgnored', () async {
      await failWith(
        const ApiException(statusCode: 401, message: '인증이 필요합니다.'),
      );

      expect(state().errorMessage, '인증이 필요합니다.');
      expect(state().canRetry, isFalse);

      await notifier().retry();
      await pumpEventQueue();

      expect(lineApi.calls, hasLength(1));
      expect(state().status, PhotoTranslationStatus.failed);
    });

    test('sessionExpired_showsSignInAgainMessage', () async {
      await failWith(const SessionExpiredException());

      expect(state().errorMessage, '로그인이 만료되었습니다.\n다시 로그인한 뒤 찍어 주세요.');
      expect(state().canRetry, isFalse);
    });

    test('sessionChanged_showsRetakeMessage', () async {
      await failWith(const SessionChangedException());

      expect(state().errorMessage, '로그인 상태가 바뀌었습니다.\n다시 찍어 주세요.');
      expect(state().canRetry, isFalse);
    });
  });
}
