/// 在排雷→播种→持仓→收割流程中跨页面传递的标的上下文。
/// 所有字段均为可选，接收页按需读取，缺失时降级为手动输入。
class StockContext {
  final String? code;
  final String? name;
  final String? assetType; // 'stock' | 'fund'
  final String? market;    // 'SH' | 'SZ'

  /// 来自排雷页
  final double? pePercentile;
  final double? pbPercentile;
  final String? industryCycle; // 'up' | 'neutral' | 'down'
  final double? currentPrice;

  /// 来自持仓（用于收割计算）
  final double? remainingCost;   // effectiveRemainingCost
  final double? remainingQty;    // totalRemaining
  final double? avgCostPrice;    // avgHoldingCost

  /// 来自播种计划（用于记录入账预填）
  final double? planBuyPrice;
  final double? planQuantity;

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
    );
  }
}
