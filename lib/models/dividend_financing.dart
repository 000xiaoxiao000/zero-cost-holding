/// 分红送转单条记录（对应 F10「分红送配」一行）
class DividendRecord {
  final String reportPeriod; // 报告期，如 2025年报 / 2025三季报
  final String plan;         // 分红方案，如 10派0.7元(实施方案)
  final String recordDate;   // 股权登记日
  final String exDate;       // 除权除息日
  final double cashPer10;    // 每10股税前派息(元)，用于统计

  const DividendRecord({
    required this.reportPeriod,
    required this.plan,
    required this.recordDate,
    required this.exDate,
    this.cashPer10 = 0.0,
  });
}

/// 融资单条记录（首发/增发/配股）
class FinancingRecord {
  final String date;    // 发行/上市日期
  final String type;    // 类型：首发 / 增发 / 配股
  final double amount;  // 募集资金净额(元)
  final double? shares; // 实际发行股数
  final double? price;  // 发行价格(元/股)

  const FinancingRecord({
    required this.date,
    required this.type,
    this.amount = 0.0,
    this.shares,
    this.price,
  });
}

/// 个股分红 & 融资汇总数据（估值参考下方展示）
class DividendFinancingData {
  final int dividendCount;        // A股派现次数
  final double? dividendTotal;    // A股累计派现金额(元)
  final int financingCount;       // A股融资次数(增发/配股/首发)
  final double? financingTotal;   // A股累计融资金额(元)

  final double? ipoTotal;         // 首发募集净额(元)
  final double? refinanceTotal;   // 再融资净额(元) = 增发 + 配股

  final double? dividendYield;    // 股息率(%)
  final double? payoutRatio;      // 股利支付率(%)
  final double? divFinRatio;      // 派现融资比(%) = 累计派现 / 累计融资 × 100

  final List<DividendRecord> records;         // 分红送转历史
  final List<FinancingRecord> financingRecords; // 融资历史
  final List<String> sourceNotes;
  final bool isFund;              // 基金无融资维度，UI 据此置灰融资页签

  const DividendFinancingData({
    this.dividendCount = 0,
    this.dividendTotal,
    this.financingCount = 0,
    this.financingTotal,
    this.ipoTotal,
    this.refinanceTotal,
    this.dividendYield,
    this.payoutRatio,
    this.divFinRatio,
    this.records = const [],
    this.financingRecords = const [],
    this.sourceNotes = const [],
    this.isFund = false,
  });

  bool get hasData =>
      dividendCount > 0 ||
      financingCount > 0 ||
      records.isNotEmpty ||
      financingRecords.isNotEmpty ||
      dividendYield != null;

  /// 潜在派现概率（基于历史分红连续性 + 派现融资比的启发式判断）
  /// high / mid / low
  String get potentialLevel {
    final years = dividendYears;
    final ratio = divFinRatio ?? 0;
    if (dividendCount >= 8 && years >= 5 && ratio >= 30) return 'high';
    if (dividendCount == 0) return 'low';
    if (years >= 3 || ratio >= 15) return 'mid';
    return 'low';
  }

  int get dividendYears {
    final years = <String>{};
    for (final r in records) {
      if (r.cashPer10 <= 0) continue;
      final d = r.exDate.isNotEmpty ? r.exDate : r.recordDate;
      if (d.length >= 4) years.add(d.substring(0, 4));
    }
    return years.length;
  }
}
