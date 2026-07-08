import 'dart:math' as math;

/// ATR (Average True Range) 计算服务
///
/// 标准 Wilder ATR 算法：
///   TR(i) = max(high-low, |high-prevClose|, |low-prevClose|)
///   ATR(n) = Wilder 平滑移动平均（等价于 EMA 系数 1/n）
///
/// 默认周期 14（行业标准），可自定义。
class AtrService {
  AtrService._();

  /// 从 K 线列表计算最新 ATR 值
  ///
  /// [klines]  日 K 数据列表（按时间升序），每条须含 high/low/close 字段
  /// [period]  ATR 周期，默认 14
  /// 返回 null 表示数据不足或解析失败
  static double? calculate(
    List<Map<String, dynamic>> klines, {
    int period = 14,
  }) {
    if (klines.length < period + 1) return null;

    final highs = <double>[];
    final lows = <double>[];
    final closes = <double>[];

    for (final k in klines) {
      final h = _n(k['high']);
      final l = _n(k['low']);
      final c = _n(k['close']);
      if (h == null || l == null || c == null || c <= 0) continue;
      highs.add(h);
      lows.add(l);
      closes.add(c);
    }

    if (closes.length < period + 1) return null;

    // 计算每日真实波动幅度
    final trList = <double>[];
    for (int i = 1; i < closes.length; i++) {
      final tr = _trueRange(
        high: highs[i],
        low: lows[i],
        prevClose: closes[i - 1],
      );
      trList.add(tr);
    }

    if (trList.length < period) return null;

    // 用前 period 个 TR 的简单均值作为初始 ATR（Wilder 标准做法）
    double atr = trList.take(period).reduce((a, b) => a + b) / period;

    // Wilder 平滑：ATR(i) = (ATR(i-1) * (n-1) + TR(i)) / n
    for (int i = period; i < trList.length; i++) {
      atr = (atr * (period - 1) + trList[i]) / period;
    }

    // 保留 4 位有效小数
    return double.parse(atr.toStringAsFixed(4));
  }

  /// 真实波幅
  static double _trueRange({
    required double high,
    required double low,
    required double prevClose,
  }) {
    return math.max(
      high - low,
      math.max((high - prevClose).abs(), (low - prevClose).abs()),
    );
  }

  static double? _n(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
