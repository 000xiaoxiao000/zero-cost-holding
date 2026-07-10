/// 播种批次 - 记录每一次资产配置动作
class HoldingBatch {
  final int? id;
  final String assetType; // stock / fund
  final String market; // SH / SZ / BJ
  final String stockCode;
  final String stockName;
  final double buyPrice;
  final double quantity;
  final double commission;
  final DateTime buyDate;
  final String? note;
  final double? planRecoverPrice;
  final double? planRecoverQuantity;
  final double? planCapital;
  final double? planStartPrice;
  final int? planSeedCount;
  final double? planDropStep;
  final double? planRebound;
  final double? planCommission;
  final String? planWeightModeKey;
  final double cashIncome;
  double? sellPrice;
  double? sellQuantity;
  DateTime? sellDate;

  HoldingBatch({
    this.id,
    this.assetType = 'stock',
    this.market = 'SH',
    required this.stockCode,
    required this.stockName,
    required this.buyPrice,
    required this.quantity,
    this.commission = 0.0,
    required this.buyDate,
    this.note,
    this.planRecoverPrice,
    this.planRecoverQuantity,
    this.planCapital,
    this.planStartPrice,
    this.planSeedCount,
    this.planDropStep,
    this.planRebound,
    this.planCommission,
    this.planWeightModeKey,
    this.cashIncome = 0.0,
    this.sellPrice,
    this.sellQuantity,
    this.sellDate,
  });

  double get totalCost => buyPrice * quantity + commission;

  double get avgCost => quantity > 0 ? totalCost / quantity : 0.0;

  bool get isFund => assetType == 'fund';

  bool get hasPlanSnapshot =>
      planCapital != null ||
      planRecoverPrice != null ||
      planRecoverQuantity != null ||
      planStartPrice != null ||
      planSeedCount != null ||
      planDropStep != null ||
      planRebound != null ||
      planCommission != null ||
      planWeightModeKey != null;

  String get assetTypeLabel => isFund ? '基金' : '股票';

  String get quantityUnit => isFund ? '份' : '股';

  bool get isPartialSold => sellQuantity != null && sellQuantity! < quantity;

  bool get isFullySold => sellQuantity != null && sellQuantity! >= quantity;

  /// 已回收资金
  double get recoveredAmount {
    if (sellPrice == null || sellQuantity == null) return 0.0;
    return sellPrice! * sellQuantity!;
  }

  /// 仓位回收 + 分红/现金派发等额外回收
  double get totalRecoveredCash => recoveredAmount + cashIncome;

  /// 账面剩余成本（总成本 - 已回收），可能为负数，用于内部核算
  double get remainingCost => totalCost - totalRecoveredCash;

  /// 最新零成本价格口径：超额回收后按 0 展示，不显示负成本
  double get effectiveRemainingCost => remainingCost <= 0 ? 0.0 : remainingCost;

  double get effectiveCostPrice =>
      remainingQuantity > 0 ? effectiveRemainingCost / remainingQuantity : 0.0;

  /// 剩余持仓数量
  double get remainingQuantity => quantity - (sellQuantity ?? 0);

  /// 是否达到零成本（已回收金额 >= 总成本）
  bool get isZeroCost => totalRecoveredCash >= totalCost;

  /// 零成本进度 (0.0 ~ 1.0)
  double get zeroCostProgress {
    if (totalCost <= 0) return 0.0;
    return (totalRecoveredCash / totalCost).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'asset_type': assetType,
      'market': market,
      'stock_code': stockCode,
      'stock_name': stockName,
      'buy_price': buyPrice,
      'quantity': quantity,
      'commission': commission,
      'buy_date': buyDate.toIso8601String(),
      'note': note,
      'plan_recover_price': planRecoverPrice,
      'plan_recover_quantity': planRecoverQuantity,
      'plan_capital': planCapital,
      'plan_start_price': planStartPrice,
      'plan_seed_count': planSeedCount,
      'plan_drop_step': planDropStep,
      'plan_rebound': planRebound,
      'plan_commission': planCommission,
      'plan_weight_mode': planWeightModeKey,
      'cash_income': cashIncome,
      'sell_price': sellPrice,
      'sell_quantity': sellQuantity,
      'sell_date': sellDate?.toIso8601String(),
    };
  }

  factory HoldingBatch.fromMap(Map<String, dynamic> map) {
    return HoldingBatch(
      id: map['id'],
      assetType: map['asset_type'] ?? 'stock',
      market: map['market'] ?? 'SH',
      stockCode: map['stock_code'] ?? '',
      stockName: map['stock_name'] ?? '',
      buyPrice: (map['buy_price'] ?? 0.0).toDouble(),
      quantity: (map['quantity'] ?? 0.0).toDouble(),
      commission: (map['commission'] ?? 0.0).toDouble(),
      buyDate: DateTime.parse(map['buy_date']),
      note: map['note'],
      planRecoverPrice: map['plan_recover_price']?.toDouble(),
      planRecoverQuantity: map['plan_recover_quantity']?.toDouble(),
      planCapital: map['plan_capital']?.toDouble(),
      planStartPrice: map['plan_start_price']?.toDouble(),
      planSeedCount: map['plan_seed_count'],
      planDropStep: map['plan_drop_step']?.toDouble(),
      planRebound: map['plan_rebound']?.toDouble(),
      planCommission: map['plan_commission']?.toDouble(),
      planWeightModeKey: map['plan_weight_mode'],
      cashIncome: (map['cash_income'] ?? 0.0).toDouble(),
      sellPrice: map['sell_price']?.toDouble(),
      sellQuantity: map['sell_quantity']?.toDouble(),
      sellDate:
          map['sell_date'] != null ? DateTime.parse(map['sell_date']) : null,
    );
  }

  HoldingBatch copyWith({
    int? id,
    double? sellPrice,
    double? sellQuantity,
    DateTime? sellDate,
    String? note,
    double? cashIncome,
  }) {
    return HoldingBatch(
      id: id ?? this.id,
      assetType: assetType,
      market: market,
      stockCode: stockCode,
      stockName: stockName,
      buyPrice: buyPrice,
      quantity: quantity,
      commission: commission,
      buyDate: buyDate,
      note: note ?? this.note,
      planRecoverPrice: planRecoverPrice,
      planRecoverQuantity: planRecoverQuantity,
      planCapital: planCapital,
      planStartPrice: planStartPrice,
      planSeedCount: planSeedCount,
      planDropStep: planDropStep,
      planRebound: planRebound,
      planCommission: planCommission,
      planWeightModeKey: planWeightModeKey,
      cashIncome: cashIncome ?? this.cashIncome,
      sellPrice: sellPrice ?? this.sellPrice,
      sellQuantity: sellQuantity ?? this.sellQuantity,
      sellDate: sellDate ?? this.sellDate,
    );
  }
}

/// 持仓汇总 - 对某只股票或基金所有批次的聚合视图
class HoldingPosition {
  final String assetType;
  final String market;
  final String stockCode;
  final String stockName;
  final List<HoldingBatch> batches;
  final double currentPrice;

  HoldingPosition({
    this.assetType = 'stock',
    this.market = 'SH',
    required this.stockCode,
    required this.stockName,
    required this.batches,
    this.currentPrice = 0.0,
  });

  double get totalInvested => batches.fold(0.0, (sum, b) => sum + b.totalCost);

  double get totalRecovered =>
      batches.fold(0.0, (sum, b) => sum + b.totalRecoveredCash);

  double get totalSellRecovered =>
      batches.fold(0.0, (sum, b) => sum + b.recoveredAmount);

  double get totalCashIncome =>
      batches.fold(0.0, (sum, b) => sum + b.cashIncome);

  double get totalRemaining =>
      batches.fold(0.0, (sum, b) => sum + b.remainingQuantity);

  bool get isFund => assetType == 'fund';

  String get assetTypeLabel => isFund ? '基金' : '股票';

  String get quantityUnit => isFund ? '份' : '股';

  double get remainingCost => totalInvested - totalRecovered;

  double get effectiveRemainingCost => remainingCost <= 0 ? 0.0 : remainingCost;

  double get avgHoldingCost =>
      totalRemaining > 0 ? effectiveRemainingCost / totalRemaining : 0.0;

  double get latestZeroCostPrice =>
      isZeroCost || totalRemaining <= 0 ? 0.0 : avgHoldingCost;

  double get freeQuantity => isZeroCost ? totalRemaining : 0.0;

  double get currentValue => currentPrice * totalRemaining;

  double get unrealizedPnl => currentValue - effectiveRemainingCost;

  double get unrealizedPnlPercent => effectiveRemainingCost > 0
      ? (unrealizedPnl / effectiveRemainingCost) * 100
      : 0.0;

  double get zeroCostProgress {
    if (totalInvested <= 0) return 0.0;
    return (totalRecovered / totalInvested).clamp(0.0, 1.0);
  }

  bool get isZeroCost => totalRecovered >= totalInvested;
}
