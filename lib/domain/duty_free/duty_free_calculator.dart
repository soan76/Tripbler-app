import '../../models/duty_free/duty_free_item.dart';
import '../../models/duty_free/duty_free_rules.dart';

/// 일반 물품 한도 계산 결과.
class GeneralLimitSummary {
  const GeneralLimitSummary({
    required this.spentUsd,
    required this.limitUsd,
    required this.unconvertible,
  });

  /// 한도의 90% 이상이면 경고한다.
  static const double nearRatio = 0.9;

  final double spentUsd;
  final double limitUsd;

  /// 환율이 없어 합계에서 빠진 물건 수.
  final int unconvertible;

  double get remainingUsd => limitUsd - spentUsd;
  bool get over => spentUsd > limitUsd;
  double get overUsd => over ? spentUsd - limitUsd : 0;
  double get ratio => limitUsd <= 0 ? 1 : spentUsd / limitUsd;
  bool get near => !over && ratio >= nearRatio;
}

/// 별도 기준 한 줄의 상태.
enum SeparateLimitStatus { none, within, over }

class LiquorSummary {
  const LiquorSummary({
    required this.bottles,
    required this.liters,
    required this.usd,
    required this.status,
    this.unconvertible = 0,
  });

  final int bottles;
  final double liters;

  /// 달러로 바꾼 금액. 환율이 없는 주류는 빠진다.
  final double usd;
  final SeparateLimitStatus status;

  /// 환율이 없어 [usd]에서 빠진 주류 수. 0보다 크면 금액 기준 판정을 믿을 수 없다.
  final int unconvertible;
}

class TobaccoSummary {
  const TobaccoSummary({required this.packs, required this.status});

  final int packs;
  final SeparateLimitStatus status;
}

class PerfumeSummary {
  const PerfumeSummary({required this.ml, required this.status});

  final double ml;
  final SeparateLimitStatus status;
}

/// 일반 물품 초과분의 예상 세금(예시). 별도 기준 초과분은 세율이 달라 계산하지 않는다.
class TaxEstimate {
  const TaxEstimate({
    required this.overUsd,
    required this.overKrw,
    required this.taxKrw,
    required this.discountKrw,
  });

  final double overUsd;
  final double overKrw;
  final double taxKrw;
  final double discountKrw;

  double get totalKrw => taxKrw - discountKrw;
}

/// 면세 화면 요약.
class DutyFreeSummary {
  const DutyFreeSummary({
    required this.general,
    required this.liquor,
    required this.tobacco,
    required this.perfume,
    required this.tax,
  });

  final GeneralLimitSummary general;
  final LiquorSummary liquor;
  final TobaccoSummary tobacco;
  final PerfumeSummary perfume;

  /// 일반 물품 한도를 넘었을 때만.
  final TaxEstimate? tax;

  bool get liquorOver => liquor.status == SeparateLimitStatus.over;
  bool get tobaccoOver => tobacco.status == SeparateLimitStatus.over;
  bool get perfumeOver => perfume.status == SeparateLimitStatus.over;
  bool get separateOver => liquorOver || tobaccoOver || perfumeOver;
  bool get anyOver => general.over || separateOver;

  /// 신고 안내에 보일 초과 항목 이름.
  List<String> get overReasons => [
    if (general.over) '일반 물품 한도 초과',
    if (liquorOver) '주류 기준 초과',
    if (tobaccoOver) '담배 기준 초과',
    if (perfumeOver) '향수 기준 초과',
  ];
}

/// 산 물건과 규칙으로 일반 한도와 별도 기준을 나눠 계산한다(docs/mockups/duty-free.md 2절).
class DutyFreeCalculator {
  const DutyFreeCalculator();

  DutyFreeSummary summarize({
    required List<DutyFreeItem> items,
    required DutyFreeRules rules,
    required bool adult,
  }) {
    var spent = 0.0;
    var unconvertible = 0;
    var bottles = 0;
    var liters = 0.0;
    var liquorUsd = 0.0;
    var liquorUnconvertible = 0;
    var packs = 0;
    var ml = 0.0;
    for (final item in items) {
      final usd = rules.toUsd(item.amount, item.currency);
      switch (item.category) {
        case DutyFreeCategory.general:
          if (usd == null) {
            unconvertible++;
          } else {
            spent += usd;
          }
        case DutyFreeCategory.liquor:
          bottles += item.quantity;
          liters += item.totalVolume;
          if (usd == null) {
            liquorUnconvertible++;
          } else {
            liquorUsd += usd;
          }
        case DutyFreeCategory.tobacco:
          packs += item.quantity;
        case DutyFreeCategory.perfume:
          ml += item.totalVolume;
      }
    }

    SeparateLimitStatus status(bool has, bool over) => !has
        ? SeparateLimitStatus.none
        : over
        ? SeparateLimitStatus.over
        : SeparateLimitStatus.within;

    final general = GeneralLimitSummary(
      spentUsd: spent,
      limitUsd: rules.generalLimitUsd,
      unconvertible: unconvertible,
    );
    return DutyFreeSummary(
      general: general,
      liquor: LiquorSummary(
        bottles: bottles,
        liters: liters,
        usd: liquorUsd,
        unconvertible: liquorUnconvertible,
        status: status(
          bottles > 0,
          !adult ||
              bottles > rules.liquorBottles ||
              liters > rules.liquorLiters + 1e-9 ||
              liquorUsd > rules.liquorUsd,
        ),
      ),
      tobacco: TobaccoSummary(
        packs: packs,
        status: status(packs > 0, !adult || packs > rules.tobaccoPacks),
      ),
      perfume: PerfumeSummary(
        ml: ml,
        status: status(ml > 0, ml > rules.perfumeMl + 1e-9),
      ),
      tax: general.over ? _tax(general.overUsd, rules) : null,
    );
  }

  TaxEstimate _tax(double overUsd, DutyFreeRules rules) {
    final krw = overUsd * rules.krwPerUsd;
    final tax = krw * rules.taxRate;
    return TaxEstimate(
      overUsd: overUsd,
      overKrw: krw,
      taxKrw: tax,
      discountKrw: tax * rules.selfReportDiscount,
    );
  }
}
