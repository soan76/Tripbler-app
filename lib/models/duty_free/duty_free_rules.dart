/// 입국 면세 기준과 계산에 쓰는 환율(docs/mockups/duty-free.md 2절).
///
/// 지금은 앱 안의 예시 값([isExample])이다. 서버 규칙 API로 바꾸면 같은 모양으로 받는다.
class DutyFreeRules {
  const DutyFreeRules({
    required this.country,
    required this.basisDate,
    required this.generalLimitUsd,
    required this.liquorBottles,
    required this.liquorLiters,
    required this.liquorUsd,
    required this.tobaccoPacks,
    required this.perfumeMl,
    required this.taxRate,
    required this.selfReportDiscount,
    required this.krwPerUsd,
    required this.usdPerUnit,
    required this.checkedAt,
    this.isExample = false,
    this.stale = false,
  });

  /// 입국 국가 이름(지금은 한국만).
  final String country;

  /// 기준일.
  final DateTime basisDate;
  final double generalLimitUsd;
  final int liquorBottles;
  final double liquorLiters;
  final double liquorUsd;
  final int tobaccoPacks;
  final double perfumeMl;

  /// 일반 물품 초과분 예시 세율(0~1).
  final double taxRate;

  /// 자진신고 감면 비율(0~1).
  final double selfReportDiscount;
  final double krwPerUsd;

  /// 통화 1단위가 몇 달러인지. 없는 통화는 환산하지 못한다.
  final Map<String, double> usdPerUnit;

  /// 기준·환율을 확인한 시각.
  final DateTime checkedAt;

  /// 실제 기준이 아닌 예시 값인지.
  final bool isExample;

  /// 새로 받지 못해 저장된 값을 쓰는지.
  final bool stale;

  /// [amount] [currency]를 달러로. 환율이 없으면 null.
  double? toUsd(double amount, String currency) {
    final rate = usdPerUnit[currency];
    return rate == null ? null : amount * rate;
  }

  /// 달러를 [currency]로. 환율이 없으면 null.
  double? fromUsd(double usd, String currency) {
    final rate = usdPerUnit[currency];
    return rate == null || rate == 0 ? null : usd / rate;
  }
}
