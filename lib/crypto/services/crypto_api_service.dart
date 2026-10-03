import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../models/api_error_response.dart';
import '../models/crypto_coin.dart';
import '../models/crypto_price.dart';
import '../models/crypto_history.dart';

/// Tripbler 서버만 호출한다.
class CryptoApiService {
  CryptoApiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<CryptoCoin>> fetchCoins() async {
    final json = await _get('coins');
    if (json is! List) throw const FormatException('잘못된 코인 목록');
    final coins = json
        .map((e) => CryptoCoin.fromJson(e as Map<String, dynamic>))
        .toList();
    if (coins.map((e) => e.symbol).toSet().length != coins.length) {
      throw const FormatException('중복 코인 심볼');
    }
    return coins;
  }

  Future<CryptoPrice> fetchPrice(String symbol) async {
    final json = await _get('price', {'coin': symbol, 'currency': 'KRW'});
    final price = CryptoPrice.fromJson(json as Map<String, dynamic>);
    if (price.symbol != symbol) throw const FormatException('요청과 다른 코인 응답');
    return price;
  }

  Future<CryptoHistory> fetchHistory({
    required String symbol,
    required String period,
  }) async {
    // UI에는 2Y/5Y도 유지하지만 Demo 제한을 넘는 요청은 서버에 보내지 않는다.
    if (!CryptoHistory.supportedPeriods.containsKey(period)) {
      throw const ApiException(
        message: '암호화폐 차트를 불러오지 못했습니다. 현재 최대 1년까지 지원합니다.',
      );
    }
    final json = await _get('history', {
      'coin': symbol,
      'currency': 'KRW',
      'period': period,
    });
    final history = CryptoHistory.fromJson(json as Map<String, dynamic>);
    if (history.symbol != symbol || history.period != period) {
      throw const FormatException('요청과 다른 암호화폐 과거 시세 응답');
    }
    return history;
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/crypto/$path',
      ).replace(queryParameters: query);
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        ApiErrorResponse? error;
        try {
          error = ApiErrorResponse.fromJson(
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
          );
        } catch (_) {
          /* JSON이 아닌 오류 응답은 기본 메시지 사용. */
        }
        throw ApiException(
          statusCode: response.statusCode,
          code: error?.code,
          message: error?.message ?? '암호화폐 정보를 불러오지 못했습니다.',
        );
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on TimeoutException {
      throw const ApiException(message: '암호화폐 조회 시간이 초과되었습니다.');
    } on http.ClientException {
      throw const ApiException(message: '암호화폐 서버에 연결하지 못했습니다.');
    }
  }

  void dispose() => _client.close();
}
