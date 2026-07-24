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

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'rate': rate,
      'baseCurrencyCode': baseCurrencyCode,
      'targetCurrencyCode': targetCurrencyCode,
    };
  }

  factory ExchangeRateHistoryModel.fromJson(Map<String, dynamic> json) {
    return ExchangeRateHistoryModel(
      date: DateTime.parse(json['date'] as String),
      rate: (json['rate'] as num).toDouble(),
      baseCurrencyCode: json['baseCurrencyCode'] as String,
      targetCurrencyCode: json['targetCurrencyCode'] as String,
    );
  }
}

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
