import '../../crypto/models/crypto_history.dart';
import '../../models/exchange_rate_history_model.dart';

/// 통화 종류별로 조회할 수 있는 차트 기간을 정한다.
/// 암호화폐는 API와 같은 기준([CryptoHistory.supportedPeriods])을 따르고,
/// 국가 통화는 모든 기간을 지원한다.
abstract final class ChartPeriodPolicy {
  static bool supports(ChartPeriod period, {required bool crypto}) =>
      !crypto || CryptoHistory.supports(period);
}
