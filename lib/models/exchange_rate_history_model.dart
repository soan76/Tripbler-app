// 특정 날짜의 환율 기록을 저장하는 모델 클래스
class ExchangeRateHistoryModel {
  final DateTime date;
  final double rate;
  final String baseCurrencyCode;
  final String targetCurrencyCode;

  const ExchangeRateHistoryModel({
    required this.date,
    required this.rate,
    required this.baseCurrencyCode,
    required this.targetCurrencyCode,
  });

  // 환율 기록 객체를 JSON 형태의 Map으로 변환
  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'rate': rate,
      'baseCurrencyCode': baseCurrencyCode,
      'targetCurrencyCode': targetCurrencyCode,
    };
  }

  // JSON 형태의 Map을 환율 기록 객체로 변환
  factory ExchangeRateHistoryModel.fromJson(Map<String, dynamic> json) {
    return ExchangeRateHistoryModel(
      date: DateTime.parse(json['date'] as String),
      rate: (json['rate'] as num).toDouble(),
      baseCurrencyCode: json['baseCurrencyCode'] as String,
      targetCurrencyCode: json['targetCurrencyCode'] as String,
    );
  }

  factory ExchangeRateHistoryModel.fromBackendJson(
    Map<String, dynamic> json, {
    required String baseCurrencyCode,
    required String targetCurrencyCode,
  }) {
    return ExchangeRateHistoryModel(
      date: DateTime.parse(json['date'] as String),
      rate: (json['rate'] as num).toDouble(),
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
    );
  }
}

// 환율 차트에서 선택할 수 있는 조회 기간 - 수정 예정
enum ChartPeriod {
  sevenDays,
  oneMonth,
  threeMonths,
  sixMonths,
  oneYear,
  twoYears,
  fiveYears,
}

extension ChartPeriodExtension on ChartPeriod {
  // 사용자 화면에 표시할 한글 기간 이름 - 수정 예정
  String get label {
    switch (this) {
      case ChartPeriod.sevenDays:
        return '7일';
      case ChartPeriod.oneMonth:
        return '1개월';
      case ChartPeriod.threeMonths:
        return '3개월';
      case ChartPeriod.sixMonths:
        return '6개월';
      case ChartPeriod.oneYear:
        return '1년';
      case ChartPeriod.twoYears:
        return '2년';
      case ChartPeriod.fiveYears:
        return '5년';
    }
  }

  // 사용자 화면에 표시할 짧은 기간 이름 - 수정 예정
  String get shortLabel {
    switch (this) {
      case ChartPeriod.sevenDays:
        return '7d';
      case ChartPeriod.oneMonth:
        return '1m';
      case ChartPeriod.threeMonths:
        return '3m';
      case ChartPeriod.sixMonths:
        return '6m';
      case ChartPeriod.oneYear:
        return '1y';
      case ChartPeriod.twoYears:
        return '2y';
      case ChartPeriod.fiveYears:
        return '5y';
    }
  }

  // 특정 기간의 시작 날짜를 계산하는 메서드 - 수정 예정
  DateTime startDateFrom(DateTime endDate) {
    switch (this) {
      case ChartPeriod.sevenDays:
        return endDate.subtract(const Duration(days: 7));
      case ChartPeriod.oneMonth:
        return DateTime(endDate.year, endDate.month - 1, endDate.day);
      case ChartPeriod.threeMonths:
        return DateTime(endDate.year, endDate.month - 3, endDate.day);
      case ChartPeriod.sixMonths:
        return DateTime(endDate.year, endDate.month - 6, endDate.day);
      case ChartPeriod.oneYear:
        return DateTime(endDate.year - 1, endDate.month, endDate.day);
      case ChartPeriod.twoYears:
        return DateTime(endDate.year - 2, endDate.month, endDate.day);
      case ChartPeriod.fiveYears:
        return DateTime(endDate.year - 5, endDate.month, endDate.day);
    }
  }

  // 차트 X축 날짜 라벨을 표시할 간격
  int get xAxisLabelInterval {
    switch (this) {
      case ChartPeriod.sevenDays:
        return 1;
      case ChartPeriod.oneMonth:
        return 5;
      case ChartPeriod.threeMonths:
        return 15;
      case ChartPeriod.sixMonths:
        return 30;
      case ChartPeriod.oneYear:
        return 60;
      case ChartPeriod.twoYears:
        return 120;
      case ChartPeriod.fiveYears:
        return 365;
    }
  }
}
