/// 在排雷→播种→持仓→收割流程中跨页面传递的标的上下文。
/// 所有字段均为可选，接收页按需读取，缺失时降级为手动输入。
class StockContext {
  final String? code;
  final String? name;
  final String? assetType; // 'stock' | 'fund'
  final String? market; // 'SH' | 'SZ'

  /// 来自排雷页
  final double? pePercentile;
  final double? pbPercentile;
  final String? industryCycle; // 'up' | 'neutral' | 'down'
  final double? currentPrice;

  /// 来自持仓（用于收割计算）
  final double? remainingCost; // effectiveRemainingCost
  final double? remainingQty; // totalRemaining
  final double? avgCostPrice; // avgHoldingCost

  /// 来自播种计划（用于记录入账预填）
  final double? planBuyPrice;
  final double? planQuantity;
  final double? planRecoverPrice;
  final double? planRecoverQuantity;
  final double? planCapital;
  final double? planStartPrice;
  final int? planSeedCount;
  final double? planDropStep;
  final double? planRebound;
  final double? planCommission;
  final String? planWeightModeKey;
  final int? planBatchIndex;

  /// 来自排雷页策略顾问的算法推荐（跨页面预填计划参数）
  final String? seedAlgo; // 'pyramid' | 'grid' | 'dca' | 'equal'
  final String? weightModeKey; // 播种页 WeightMode 名称
  final String? harvestAlgo; // 'grid' | 'chandelier' | 'percentile'
  final String? harvestModeKey; // 收割页 mode 名称
  final int? recommendSeedCount; // 推荐批数
  final double? recommendDropStep; // 推荐下跌间距（%）
  final double? recommendGridStep; // 推荐收割网格间距（%）
  final double? recommendAtrMultiple; // 推荐 ATR/吊灯倍数

  const StockContext({
    this.code,
    this.name,
    this.assetType,
    this.market,
    this.pePercentile,
    this.pbPercentile,
    this.industryCycle,
    this.currentPrice,
    this.remainingCost,
    this.remainingQty,
    this.avgCostPrice,
    this.planBuyPrice,
    this.planQuantity,
    this.planRecoverPrice,
    this.planRecoverQuantity,
    this.planCapital,
    this.planStartPrice,
    this.planSeedCount,
    this.planDropStep,
    this.planRebound,
    this.planCommission,
    this.planWeightModeKey,
    this.planBatchIndex,
    this.seedAlgo,
    this.weightModeKey,
    this.harvestAlgo,
    this.harvestModeKey,
    this.recommendSeedCount,
    this.recommendDropStep,
    this.recommendGridStep,
    this.recommendAtrMultiple,
  });

  StockContext copyWith({
    String? code,
    String? name,
    String? assetType,
    String? market,
    double? pePercentile,
    double? pbPercentile,
    String? industryCycle,
    double? currentPrice,
    double? remainingCost,
    double? remainingQty,
    double? avgCostPrice,
    double? planBuyPrice,
    double? planQuantity,
    double? planRecoverPrice,
    double? planRecoverQuantity,
    double? planCapital,
    double? planStartPrice,
    int? planSeedCount,
    double? planDropStep,
    double? planRebound,
    double? planCommission,
    String? planWeightModeKey,
    int? planBatchIndex,
    String? seedAlgo,
    String? weightModeKey,
    String? harvestAlgo,
    String? harvestModeKey,
    int? recommendSeedCount,
    double? recommendDropStep,
    double? recommendGridStep,
    double? recommendAtrMultiple,
  }) {
    return StockContext(
      code: code ?? this.code,
      name: name ?? this.name,
      assetType: assetType ?? this.assetType,
      market: market ?? this.market,
      pePercentile: pePercentile ?? this.pePercentile,
      pbPercentile: pbPercentile ?? this.pbPercentile,
      industryCycle: industryCycle ?? this.industryCycle,
      currentPrice: currentPrice ?? this.currentPrice,
      remainingCost: remainingCost ?? this.remainingCost,
      remainingQty: remainingQty ?? this.remainingQty,
      avgCostPrice: avgCostPrice ?? this.avgCostPrice,
      planBuyPrice: planBuyPrice ?? this.planBuyPrice,
      planQuantity: planQuantity ?? this.planQuantity,
      planRecoverPrice: planRecoverPrice ?? this.planRecoverPrice,
      planRecoverQuantity: planRecoverQuantity ?? this.planRecoverQuantity,
      planCapital: planCapital ?? this.planCapital,
      planStartPrice: planStartPrice ?? this.planStartPrice,
      planSeedCount: planSeedCount ?? this.planSeedCount,
      planDropStep: planDropStep ?? this.planDropStep,
      planRebound: planRebound ?? this.planRebound,
      planCommission: planCommission ?? this.planCommission,
      planWeightModeKey: planWeightModeKey ?? this.planWeightModeKey,
      planBatchIndex: planBatchIndex ?? this.planBatchIndex,
      seedAlgo: seedAlgo ?? this.seedAlgo,
      weightModeKey: weightModeKey ?? this.weightModeKey,
      harvestAlgo: harvestAlgo ?? this.harvestAlgo,
      harvestModeKey: harvestModeKey ?? this.harvestModeKey,
      recommendSeedCount: recommendSeedCount ?? this.recommendSeedCount,
      recommendDropStep: recommendDropStep ?? this.recommendDropStep,
      recommendGridStep: recommendGridStep ?? this.recommendGridStep,
      recommendAtrMultiple: recommendAtrMultiple ?? this.recommendAtrMultiple,
    );
  }
}
