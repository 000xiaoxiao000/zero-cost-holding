import 'dart:math' as math;

import 'atr_service.dart';

/// 播种算法类型
enum SeedAlgo {
  pyramid,   // 正金字塔：越跌越重（低估值/深回撤区）
  grid,      // 网格：震荡区间下轨触发，间距自适应
  dca,       // 定投/轻仓试探：强趋势向上，避免追高
  equal,     // 等额：保守默认
}

extension SeedAlgoInfo on SeedAlgo {
  String get label {
    switch (this) {
      case SeedAlgo.pyramid: return '正金字塔播种';
      case SeedAlgo.grid:    return '网格播种';
      case SeedAlgo.dca:     return '定投轻仓试探';
      case SeedAlgo.equal:   return '等额分批';
    }
  }

  /// 对应 seed_plan_screen 的 WeightMode 名称（用于跨页面预填）
  String get weightModeKey {
    switch (this) {
      case SeedAlgo.pyramid: return 'pyramid';
      case SeedAlgo.grid:    return 'equal';
      case SeedAlgo.dca:     return 'inverted';
      case SeedAlgo.equal:   return 'equal';
    }
  }
}

/// 收割算法类型
enum HarvestAlgo {
  grid,        // 网格：震荡高抛低吸
  chandelier,  // 吊灯移动止盈：趋势里让利润奔跑
  percentile,  // 分位止盈：高估值分批减
}

extension HarvestAlgoInfo on HarvestAlgo {
  String get label {
    switch (this) {
      case HarvestAlgo.grid:       return '网格高抛低吸';
      case HarvestAlgo.chandelier: return '吊灯移动止盈';
      case HarvestAlgo.percentile: return '估值分位止盈';
    }
  }

  /// 对应 harvest_calculator_screen 的 mode 名称
  String get modeKey {
    switch (this) {
      case HarvestAlgo.grid:       return 'grid';
      case HarvestAlgo.chandelier: return 'chandelier';
      case HarvestAlgo.percentile: return 'grid';
    }
  }
}

/// 标的行情特征（全部由本地 K 线离线计算）
class MarketFeatures {
  final double? atr;          // Wilder ATR(14) 绝对值
  final double? atrPct;       // ATR / 现价，波动率百分比（0~1）
  final double trendStrength; // 线性回归 R²（0~1），越大越"趋势"
  final double trendSlope;    // 归一化斜率（每日涨跌幅），正为上行
  final double pricePercentile; // 近N日价格分位（0~1），基金估值替代
  final double drawdown;      // 距近N日高点回撤（0~1）
  final int sampleCount;      // 有效样本数

  const MarketFeatures({
    this.atr,
    this.atrPct,
    required this.trendStrength,
    required this.trendSlope,
    required this.pricePercentile,
    required this.drawdown,
    required this.sampleCount,
  });

  bool get hasEnoughData => sampleCount >= 30;
  String get trendLabel {
    if (!hasEnoughData) return 'neutral';
    if (trendStrength >= 0.5 && trendSlope > 0.0015) return 'up';
    if (trendStrength >= 0.5 && trendSlope < -0.0015) return 'down';
    return 'neutral';
  }
}

/// 综合推荐结果
class StrategyAdvice {
  final MarketFeatures features;
  final SeedAlgo seedAlgo;
  final HarvestAlgo harvestAlgo;
  final int seedCount;         // 推荐播种批数
  final double dropStepPct;    // 推荐下跌间距（%）
  final double gridStepPct;    // 推荐收割网格间距（%）
  final double atrMultiple;    // 推荐 ATR / 吊灯倍数
  final String seedReason;
  final String harvestReason;
  final String summary;

  const StrategyAdvice({
    required this.features,
    required this.seedAlgo,
    required this.harvestAlgo,
    required this.seedCount,
    required this.dropStepPct,
    required this.gridStepPct,
    required this.atrMultiple,
    required this.seedReason,
    required this.harvestReason,
    required this.summary,
  });
}

/// 策略顾问：根据本地 K 线特征自动路由播种/收割算法并推荐参数。
/// 全程离线可算，不引入新数据源。
class StrategyAdvisorService {
  StrategyAdvisorService._();

  /// 从日 K 线（时间升序，含 high/low/close）提取行情特征。
  static MarketFeatures extractFeatures(List<Map<String, dynamic>> klines) {
    final closes = <double>[];
    for (final k in klines) {
      final c = _n(k['close']);
      if (c != null && c > 0) closes.add(c);
    }
    final n = closes.length;
    if (n < 30) {
      return MarketFeatures(
        atr: null, atrPct: null, trendStrength: 0, trendSlope: 0,
        pricePercentile: 0.5, drawdown: 0, sampleCount: n,
      );
    }

    final atr = AtrService.calculate(klines);
    final lastPrice = closes.last;
    final atrPct = (atr != null && lastPrice > 0) ? atr / lastPrice : null;

    // 线性回归：以序号为 x，收盘价为 y，求 R² 与归一化斜率
    final reg = _linearRegression(closes);
    final meanPrice = closes.reduce((a, b) => a + b) / n;
    final slopeNorm = meanPrice > 0 ? reg.slope / meanPrice : 0.0;

    // 近 N 日价格分位
    final sorted = [...closes]..sort();
    final below = sorted.where((v) => v < lastPrice).length;
    final pricePercentile = below / n;

    // 距高点回撤
    final highest = closes.reduce(math.max);
    final drawdown = highest > 0 ? (highest - lastPrice) / highest : 0.0;

    return MarketFeatures(
      atr: atr,
      atrPct: atrPct,
      trendStrength: reg.rSquared,
      trendSlope: slopeNorm,
      pricePercentile: pricePercentile,
      drawdown: drawdown.clamp(0.0, 1.0),
      sampleCount: n,
    );
  }

  /// 综合推荐。[pePercentile]/[pbPercentile] 为 0~100 分位（股票），基金传 null。
  static StrategyAdvice advise({
    required List<Map<String, dynamic>> klines,
    double? pePercentile,
    double? pbPercentile,
    bool isFund = false,
  }) {
    final f = extractFeatures(klines);
    // 估值分位（0~1）：股票优先用 PE/PB，缺失或基金用价格分位兜底
    final valPct = _valuationPercentile(pePercentile, pbPercentile, f, isFund);

    // ATR% 兜底为 4%（数据不足时的经验值）
    final atrPct = (f.atrPct != null && f.atrPct! > 0) ? f.atrPct! : 0.04;
    final trend = f.trendLabel;

    // ── 播种算法路由 ──
    final SeedAlgo seedAlgo;
    final String seedReason;
    if (valPct <= 0.30 || f.drawdown >= 0.25) {
      seedAlgo = SeedAlgo.pyramid;
      seedReason = valPct <= 0.30
          ? '估值/价格处于历史低位（${(valPct * 100).round()}分位），越跌越重更划算'
          : '距高点回撤${(f.drawdown * 100).round()}%，已进入播种区，正金字塔重仓吸筹';
    } else if (trend == 'up' && f.trendStrength >= 0.6) {
      seedAlgo = SeedAlgo.dca;
      seedReason = '强趋势向上（R²=${f.trendStrength.toStringAsFixed(2)}），轻仓试探避免追高，等回调加码';
    } else if (f.trendStrength < 0.4) {
      seedAlgo = SeedAlgo.grid;
      seedReason = '趋势弱、区间震荡（R²=${f.trendStrength.toStringAsFixed(2)}），网格下轨分批更稳';
    } else {
      seedAlgo = SeedAlgo.equal;
      seedReason = '趋势与估值均中性，等额分批保守建仓';
    }

    // ── 收割算法路由 ──
    final HarvestAlgo harvestAlgo;
    final String harvestReason;
    if (!isFund && valPct >= 0.80) {
      harvestAlgo = HarvestAlgo.percentile;
      harvestReason = '估值处于历史高位（${(valPct * 100).round()}分位），触及高分位分批止盈';
    } else if (trend == 'up' && f.trendStrength >= 0.5) {
      harvestAlgo = HarvestAlgo.chandelier;
      harvestReason = '单边上行趋势，吊灯移动止盈让利润奔跑，避免过早离场';
    } else {
      harvestAlgo = HarvestAlgo.grid;
      harvestReason = '区间震荡，网格高抛低吸持续降低成本';
    }

    // ── 参数推荐（随波动率自适应）──
    // 下跌间距 ≈ ATR% × 2（限 4%~15%）
    final dropStep = (atrPct * 200).clamp(4.0, 15.0);
    // 网格间距 ≈ ATR%（限 3%~12%）
    final gridStep = (atrPct * 100).clamp(3.0, 12.0);
    // 批数：波动越大批数越多（4~8）
    final seedCount = (atrPct * 100).clamp(4.0, 8.0).round();
    // ATR/吊灯倍数：趋势越强倍数越大（2.0~3.5）
    final atrMult = (2.0 + f.trendStrength * 1.5).clamp(2.0, 3.5);

    final summary = _buildSummary(
      f, trend, atrPct, seedAlgo, harvestAlgo, dropStep, gridStep);

    return StrategyAdvice(
      features: f,
      seedAlgo: seedAlgo,
      harvestAlgo: harvestAlgo,
      seedCount: seedCount,
      dropStepPct: double.parse(dropStep.toStringAsFixed(1)),
      gridStepPct: double.parse(gridStep.toStringAsFixed(1)),
      atrMultiple: double.parse(atrMult.toStringAsFixed(1)),
      seedReason: seedReason,
      harvestReason: harvestReason,
      summary: summary,
    );
  }

  static double _valuationPercentile(
      double? pe, double? pb, MarketFeatures f, bool isFund) {
    if (!isFund) {
      final vals = <double>[];
      if (pe != null) vals.add(pe / 100);
      if (pb != null) vals.add(pb / 100);
      if (vals.isNotEmpty) return vals.reduce((a, b) => a + b) / vals.length;
    }
    return f.pricePercentile; // 基金或缺失时用价格分位
  }

  static String _buildSummary(
    MarketFeatures f, String trend, double atrPct,
    SeedAlgo seed, HarvestAlgo harvest, double dropStep, double gridStep,
  ) {
    if (!f.hasEnoughData) {
      return '历史K线不足（${f.sampleCount}根），推荐参数为经验默认值，请人工复核。';
    }
    final trendCn = trend == 'up' ? '上行趋势' : trend == 'down' ? '下行趋势' : '区间震荡';
    final volCn = atrPct >= 0.05 ? '波动较大' : atrPct >= 0.03 ? '波动中等' : '波动较小';
    return '近${f.sampleCount}日$trendCn、$volCn（ATR ${(atrPct * 100).toStringAsFixed(1)}%）。'
        '建议${seed.label}（间距${dropStep.toStringAsFixed(1)}%）、'
        '${harvest.label}（网格${gridStep.toStringAsFixed(1)}%）。';
  }

  static ({double slope, double rSquared}) _linearRegression(
      List<double> y) {
    final n = y.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += y[i];
      sumXY += i * y[i];
      sumXX += i * i.toDouble();
    }
    final denom = n * sumXX - sumX * sumX;
    if (denom == 0) return (slope: 0.0, rSquared: 0.0);
    final slope = (n * sumXY - sumX * sumY) / denom;
    final intercept = (sumY - slope * sumX) / n;

    final meanY = sumY / n;
    double ssTot = 0, ssRes = 0;
    for (int i = 0; i < n; i++) {
      final pred = slope * i + intercept;
      ssTot += (y[i] - meanY) * (y[i] - meanY);
      ssRes += (y[i] - pred) * (y[i] - pred);
    }
    final r2 = ssTot == 0 ? 0.0 : (1 - ssRes / ssTot).clamp(0.0, 1.0);
    return (slope: slope, rSquared: r2);
  }

  static double? _n(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
