import '../../models/duty_free/duty_free_rules.dart';

/// 면세 규칙(한도·별도 기준·세율·환율)을 준다.
///
/// 지금은 앱 안의 예시 값을 돌려준다. 서버 규칙 API(예: `GET /api/v1/duty-free/rules`)가
/// 생기면 이 클래스만 바꾸고(받기·마지막 성공값 캐시, 실패 때 `stale`), 화면과 계산은 그대로 둔다.
class DutyFreeRulesService {
  const DutyFreeRulesService({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// 받지 못하면 예외를 던진다(저장된 값도 없을 때). 지금 예시 값은 실패하지 않는다.
  Future<DutyFreeRules> fetch() async => example(_now());

  /// 예시 값. 실제 관세청 기준이 아니다.
  static DutyFreeRules example(DateTime checkedAt) {
    return DutyFreeRules(
      country: '한국',
      basisDate: DateTime(2026, 11, 1),
      generalLimitUsd: 800,
      liquorBottles: 2,
      liquorLiters: 2,
      liquorUsd: 400,
      tobaccoPacks: 10,
      perfumeMl: 100,
      taxRate: 0.2,
      selfReportDiscount: 0.3,
      krwPerUsd: 1390,
      usdPerUnit: const {'JPY': 0.0067, 'USD': 1, 'EUR': 1.08, 'KRW': 1 / 1390},
      checkedAt: checkedAt,
      isExample: true,
    );
  }
}
