class Stock {
  final String code;
  final String name;
  final String market; // SH / SZ
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
  DateTime updatedAt;

  Stock({
    required this.code,
    required this.name,
    required this.market,
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
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  String get fullCode => '$market$code';

  bool get isUp => change >= 0;

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'market': market,
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
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Stock.fromMap(Map<String, dynamic> map) {
    return Stock(
      code: map['code'] ?? '',
      name: map['name'] ?? '',
      market: map['market'] ?? 'SH',
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
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }
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
