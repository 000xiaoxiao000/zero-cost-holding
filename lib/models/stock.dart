class Stock {
  final String code;
  final String name;
  final String market; // SH / SZ
  final bool isFund;   // true = ETF/LOF/基金，false = 普通股票
  double price;
  double change;
  double changePercent;
  double volume;
  double turnover;
  double high;
  double low;
  double open;
  double preClose;
  double pe;
  double pb;
  double marketCap;
  double turnoverRate;
  DateTime updatedAt;
  /// 数据源自身的行情时间（如 sqt 返回的 20240709153005），可能与本地拉取时间不同。
  /// 为空表示数据源未提供时间戳。
  final DateTime? dataTime;

  Stock({
    required this.code,
    required this.name,
    required this.market,
    this.isFund = false,
    this.price = 0.0,
    this.change = 0.0,
    this.changePercent = 0.0,
    this.volume = 0.0,
    this.turnover = 0.0,
    this.high = 0.0,
    this.low = 0.0,
    this.open = 0.0,
    this.preClose = 0.0,
    this.pe = 0.0,
    this.pb = 0.0,
    this.marketCap = 0.0,
    this.turnoverRate = 0.0,
    this.dataTime,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  String get fullCode => '$market$code';

  bool get isUp => change >= 0;

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'market': market,
      'is_fund': isFund ? 1 : 0,
      'price': price,
      'change': change,
      'change_percent': changePercent,
      'volume': volume,
      'turnover': turnover,
      'high': high,
      'low': low,
      'open': open,
      'pre_close': preClose,
      'pe': pe,
      'pb': pb,
      'market_cap': marketCap,
      'turnover_rate': turnoverRate,
      'data_time': dataTime?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Stock.fromMap(Map<String, dynamic> map) {
    return Stock(
      code: map['code'] ?? '',
      name: map['name'] ?? '',
      market: map['market'] ?? 'SH',
      isFund: (map['is_fund'] ?? 0) == 1,
      price: (map['price'] ?? 0.0).toDouble(),
      change: (map['change'] ?? 0.0).toDouble(),
      changePercent: (map['change_percent'] ?? 0.0).toDouble(),
      volume: (map['volume'] ?? 0.0).toDouble(),
      turnover: (map['turnover'] ?? 0.0).toDouble(),
      high: (map['high'] ?? 0.0).toDouble(),
      low: (map['low'] ?? 0.0).toDouble(),
      open: (map['open'] ?? 0.0).toDouble(),
      preClose: (map['pre_close'] ?? 0.0).toDouble(),
      pe: (map['pe'] ?? 0.0).toDouble(),
      pb: (map['pb'] ?? 0.0).toDouble(),
      marketCap: (map['market_cap'] ?? 0.0).toDouble(),
      turnoverRate: (map['turnover_rate'] ?? 0.0).toDouble(),
      dataTime: map['data_time'] != null
          ? DateTime.tryParse(map['data_time'])
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  Stock copyWith({String? name}) => Stock(
        code: code,
        name: name ?? this.name,
        market: market,
        isFund: isFund,
        price: price,
        change: change,
        changePercent: changePercent,
        volume: volume,
        turnover: turnover,
        high: high,
        low: low,
        open: open,
        preClose: preClose,
        pe: pe,
        pb: pb,
        marketCap: marketCap,
        turnoverRate: turnoverRate,
        dataTime: dataTime,
        updatedAt: updatedAt,
      );
}

/// 市场指数
class MarketIndex {
  final String code;
  final String name;
  final double price;
  final double change;
  final double changePercent;

  const MarketIndex({
    required this.code,
    required this.name,
    required this.price,
    required this.change,
    required this.changePercent,
  });

  bool get isUp => change >= 0;
}
