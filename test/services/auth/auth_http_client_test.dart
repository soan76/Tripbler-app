import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/services/auth/auth_api_messages.dart';
import 'package:tripbler/services/auth/auth_http_client.dart';

class _RecordingClient extends http.BaseClient {
  http.BaseRequest? capturedRequest;
  int sendCallCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCallCount++;
    capturedRequest = request;

    return http.StreamedResponse(Stream<List<int>>.value(<int>[]), 200);
  }
}

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'tripbler_auth_http_client_test_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<String> createTestFile(String fileName) async {
    final file = File('${tempDirectory.path}/$fileName');

    await file.writeAsBytes(<int>[0, 1, 2]);

    return file.path;
  }

  AuthHttpClient createHttpClient(_RecordingClient client) {
    return AuthHttpClient(
      client: client,
      messages: const KoreanAuthApiMessages(),
    );
  }

  group('AuthHttpClient putMultipart', () {
    test('JPG 파일을 image/jpeg MIME 타입으로 전송한다', () async {
      final client = _RecordingClient();
      final httpClient = createHttpClient(client);

      addTearDown(httpClient.dispose);

      final filePath = await createTestFile('profile.jpg');

      await httpClient.putMultipart(
        uri: Uri.parse('http://localhost:8080/api/v1/users/me/profile-image'),
        authorizationHeader: '  Bearer access-token  ',
        fieldName: 'file',
        filePath: filePath,
      );

      final request = client.capturedRequest;

      expect(request, isA<http.MultipartRequest>());

      final multipartRequest = request as http.MultipartRequest;

      expect(multipartRequest.method, 'PUT');

      expect(multipartRequest.headers['Authorization'], 'Bearer access-token');

      expect(multipartRequest.headers['Accept'], 'application/json');

      expect(multipartRequest.files, hasLength(1));

      final file = multipartRequest.files.single;

      expect(file.field, 'file');
      expect(file.filename, 'profile.jpg');

      expect(file.contentType.mimeType, 'image/jpeg');
    });

    test('JPEG 파일을 image/jpeg MIME 타입으로 전송한다', () async {
      final client = _RecordingClient();
      final httpClient = createHttpClient(client);

      addTearDown(httpClient.dispose);

      final filePath = await createTestFile('profile.jpeg');

      await httpClient.putMultipart(
        uri: Uri.parse('http://localhost:8080/api/v1/users/me/profile-image'),
        authorizationHeader: 'Bearer access-token',
        fieldName: 'file',
        filePath: filePath,
      );

      final multipartRequest = client.capturedRequest as http.MultipartRequest;

      final file = multipartRequest.files.single;

      expect(file.filename, 'profile.jpeg');
      expect(file.contentType.mimeType, 'image/jpeg');
    });

    test('PNG 파일을 image/png MIME 타입으로 전송한다', () async {
      final client = _RecordingClient();
      final httpClient = createHttpClient(client);

      addTearDown(httpClient.dispose);

      final filePath = await createTestFile('profile.png');

      await httpClient.putMultipart(
        uri: Uri.parse('http://localhost:8080/api/v1/users/me/profile-image'),
        authorizationHeader: 'Bearer access-token',
        fieldName: 'file',
        filePath: filePath,
      );

      final multipartRequest = client.capturedRequest as http.MultipartRequest;

      final file = multipartRequest.files.single;

      expect(file.filename, 'profile.png');

      expect(file.contentType.mimeType, 'image/png');
    });

    test('WebP 파일을 image/webp MIME 타입으로 전송한다', () async {
      final client = _RecordingClient();
      final httpClient = createHttpClient(client);

      addTearDown(httpClient.dispose);

      final filePath = await createTestFile('profile.webp');

      await httpClient.putMultipart(
        uri: Uri.parse('http://localhost:8080/api/v1/users/me/profile-image'),
        authorizationHeader: 'Bearer access-token',
        fieldName: 'file',
        filePath: filePath,
      );

      final multipartRequest = client.capturedRequest as http.MultipartRequest;

      expect(multipartRequest.files.single.contentType.mimeType, 'image/webp');
    });

    test('GIF 파일을 image/gif MIME 타입으로 전송한다', () async {
      final client = _RecordingClient();
      final httpClient = createHttpClient(client);

      addTearDown(httpClient.dispose);

      final filePath = await createTestFile('profile.gif');

      await httpClient.putMultipart(
        uri: Uri.parse('http://localhost:8080/api/v1/users/me/profile-image'),
        authorizationHeader: 'Bearer access-token',
        fieldName: 'file',
        filePath: filePath,
      );

      final multipartRequest = client.capturedRequest as http.MultipartRequest;

      expect(multipartRequest.files.single.contentType.mimeType, 'image/gif');
    });

    test('지원하지 않는 확장자는 요청을 보내기 전에 거부한다', () async {
      final client = _RecordingClient();
      final httpClient = createHttpClient(client);

      addTearDown(httpClient.dispose);

      expect(
        () => httpClient.putMultipart(
          uri: Uri.parse('http://localhost:8080/api/v1/users/me/profile-image'),
          authorizationHeader: 'Bearer access-token',
          fieldName: 'file',
          filePath: 'profile.bmp',
        ),
        throwsA(isA<ApiException>()),
      );

      expect(client.sendCallCount, 0);
    });
  });
}
