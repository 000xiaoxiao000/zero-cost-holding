/// 自选股
class Watchlist {
  final int? id;
  final String stockCode;
  final String stockName;
  final String market;
  final DateTime addedAt;
  final String? note;
  double? targetPrice;
  double? alertPrice;

  Watchlist({
    this.id,
    required this.stockCode,
    required this.stockName,
    required this.market,
    DateTime? addedAt,
    this.note,
    this.targetPrice,
    this.alertPrice,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'stock_code': stockCode,
      'stock_name': stockName,
      'market': market,
      'added_at': addedAt.toIso8601String(),
      'note': note,
      'target_price': targetPrice,
      'alert_price': alertPrice,
    };
  }

  factory Watchlist.fromMap(Map<String, dynamic> map) {
    return Watchlist(
      id: map['id'],
      stockCode: map['stock_code'] ?? '',
      stockName: map['stock_name'] ?? '',
      market: map['market'] ?? 'SH',
      addedAt: DateTime.parse(map['added_at']),
      note: map['note'],
      targetPrice: map['target_price']?.toDouble(),
      alertPrice: map['alert_price']?.toDouble(),
    );
  }
}

/// K线数据点
class KlineData {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double? ma5;
  final double? ma10;
  final double? ma20;
  final double? ma30;

  KlineData({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.ma5,
    this.ma10,
    this.ma20,
    this.ma30,
  });

  bool get isUp => close >= open;

  factory KlineData.fromMap(Map<String, dynamic> map) {
    return KlineData(
      date: DateTime.parse(map['date'] ?? map['时间'] ?? '2000-01-01'),
      open: (map['open'] ?? map['开盘'] ?? 0.0).toDouble(),
      high: (map['high'] ?? map['最高'] ?? 0.0).toDouble(),
      low: (map['low'] ?? map['最低'] ?? 0.0).toDouble(),
      close: (map['close'] ?? map['收盘'] ?? 0.0).toDouble(),
      volume: (map['volume'] ?? map['成交量'] ?? 0.0).toDouble(),
    );
  }
}
