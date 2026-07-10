import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/holding_batch.dart';
import '../models/stock_context.dart';
import '../navigation/app_navigation.dart';
import '../providers/holding_providers.dart';
import '../providers/stock_providers.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class HarvestCalculatorScreen extends ConsumerStatefulWidget {
  final StockContext? stockContext;
  final int? targetBatchId;

  const HarvestCalculatorScreen({
    super.key,
    this.stockContext,
    this.targetBatchId,
  });

  @override
  ConsumerState<HarvestCalculatorScreen> createState() =>
      _HarvestCalculatorScreenState();
}

class _HarvestCalculatorScreenState
    extends ConsumerState<HarvestCalculatorScreen> {
  late final TextEditingController _currentPriceController;
  late final TextEditingController _remainingCostController;
  late final TextEditingController _quantityController;
  late final TextEditingController _gridStepController;
  final _atrController = TextEditingController(text: '0.45');
  late final TextEditingController _atrMultipleController;
  late final TextEditingController _recentHighController;

  late String _assetType;
  late String _mode;
  bool _atrAutoLoading = false;
  bool _atrAutoLoaded = false;
  bool _highAutoLoading = false;
  bool _highAutoLoaded = false;

  @override
  void initState() {
    super.initState();
    final ctx = widget.stockContext;
    _assetType = ctx?.assetType ?? 'stock';
    // 排雷页推荐的收割模式，缺失时默认网格
    _mode = ctx?.harvestModeKey ?? 'grid';
    _currentPriceController = TextEditingController(
      text: ctx?.currentPrice?.toStringAsFixed(3) ?? '10.000',
    );
    _remainingCostController = TextEditingController(
      text: ctx?.remainingCost?.toStringAsFixed(0) ?? '20000',
    );
    _quantityController = TextEditingController(
      text: ctx?.remainingQty?.toStringAsFixed(0) ?? '3000',
    );
    _gridStepController = TextEditingController(
      text: (ctx?.recommendGridStep ?? 8).toString(),
    );
    _atrMultipleController = TextEditingController(
      text: (ctx?.recommendAtrMultiple ?? 2).toString(),
    );
    _recentHighController = TextEditingController(
      text: ctx?.currentPrice?.toStringAsFixed(3) ?? '10.000',
    );
    if (_mode == 'atr' || _mode == 'chandelier') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoLoadAtr();
        if (_mode == 'chandelier') _autoLoadRecentHigh();
      });
    }
  }

  /// 吊灯模式自动拉取近 22 日最高价作为止盈基准
  Future<void> _autoLoadRecentHigh() async {
    final ctx = widget.stockContext;
    if (ctx?.code == null || ctx?.market == null) return;
    if (_highAutoLoaded || _highAutoLoading) return;
    setState(() => _highAutoLoading = true);
    final high =
        await ref.read(recentHighProvider((ctx!.code!, ctx.market!)).future);
    if (mounted && high != null && high > 0) {
      _recentHighController.text = high.toStringAsFixed(3);
      setState(() {
        _highAutoLoading = false;
        _highAutoLoaded = true;
      });
    } else {
      setState(() => _highAutoLoading = false);
    }
  }

  /// 当切换到 ATR 模式且存在 stock context 时自动从 K 线拉取 ATR
  Future<void> _autoLoadAtr() async {
    final ctx = widget.stockContext;
    if (ctx?.code == null || ctx?.market == null) return;
    if (_atrAutoLoaded || _atrAutoLoading) return;
    setState(() => _atrAutoLoading = true);
    final atr = await ref.read(atrProvider((ctx!.code!, ctx.market!)).future);
    if (mounted && atr != null && atr > 0) {
      _atrController.text = atr.toStringAsFixed(4);
      setState(() {
        _atrAutoLoading = false;
        _atrAutoLoaded = true;
      });
    } else {
      setState(() => _atrAutoLoading = false);
    }
  }

  bool get _isFund => _assetType == 'fund';
  double get _currentPrice =>
      double.tryParse(_currentPriceController.text) ?? 0;
  double get _remainingCost =>
      double.tryParse(_remainingCostController.text) ?? 0;
  double get _quantity => double.tryParse(_quantityController.text) ?? 0;
  double get _gridStep =>
      (double.tryParse(_gridStepController.text) ?? 0) / 100;
  double get _atr => double.tryParse(_atrController.text) ?? 0;
  double get _atrMultiple => double.tryParse(_atrMultipleController.text) ?? 0;
  double get _recentHigh => double.tryParse(_recentHighController.text) ?? 0;

  String get _unit => _isFund ? '份' : '股';

  HoldingPosition? _contextPosition() {
    final ctx = widget.stockContext;
    if (ctx?.code == null) return null;
    final key =
        '${ctx!.assetType ?? _assetType}:${ctx.market ?? 'SH'}:${ctx.code}';
    final batches = ref.read(holdingPositionsProvider)[key];
    if (batches == null || batches.isEmpty) return null;
    return HoldingPosition(
      assetType: ctx.assetType ?? _assetType,
      market: ctx.market ?? 'SH',
      stockCode: ctx.code!,
      stockName: ctx.name ?? batches.first.stockName,
      batches: batches,
    );
  }

  Future<void> _recordHarvestPlan(_HarvestPlan plan) async {
    final position = _contextPosition();
    if (position == null || plan.zeroCostSellQty <= 0 || plan.upperPrice <= 0) {
      _showSnack('没有可入账的持仓批次');
      return;
    }

    final actions = _buildSellActions(position, plan.zeroCostSellQty);
    if (actions.isEmpty) {
      _showSnack('没有剩余${position.quantityUnit}数可记录回收');
      return;
    }
    final actionQuantity =
        actions.fold(0.0, (sum, action) => sum + action.quantity);
    final remainingAfterAction = widget.targetBatchId == null
        ? position.totalRemaining - actionQuantity
        : actions.first.batch.remainingQuantity - actionQuantity;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ExecutionConfirmDialog(
        title: widget.targetBatchId == null ? '确认记录回收' : '确认记录当前批次回收',
        icon: Icons.receipt_long_outlined,
        iconColor: AppTheme.accentGold,
        summary:
            '${position.stockName} ${position.stockCode}\n卖出 ${Formatters.quantity(actionQuantity)}${position.quantityUnit} · 价格 ¥${Formatters.price(plan.upperPrice)}',
        metrics: [
          _ConfirmMetric(
              '预计回收现金', Formatters.money(actionQuantity * plan.upperPrice)),
          _ConfirmMetric('执行后保留',
              '${Formatters.quantity(remainingAfterAction)}${position.quantityUnit}'),
          _ConfirmMetric(widget.targetBatchId == null ? '影响批次' : '入账批次',
              widget.targetBatchId == null ? '${actions.length} 批' : '当前播种记录'),
        ],
        warning: actions.length > 1 ? '本次数量会自动分摊到多个仍有剩余数量的批次。' : null,
      ),
    );
    if (confirmed != true || !mounted) return;

    final notifier = ref.read(holdingPositionsProvider.notifier);
    final sellDate = DateTime.now();
    for (final action in actions) {
      await notifier.recordSell(
        action.batch.id!,
        plan.upperPrice,
        action.quantity,
        sellDate: sellDate,
      );
    }
    if (!mounted) return;
    _showSnack('回收已入账，零成本进度已更新');
    AppNavigation.goHomeTab(context, HomeTab.holding);
  }

  List<_SellAction> _buildSellActions(
      HoldingPosition position, double targetQty) {
    final targetBatchId = widget.targetBatchId;
    if (targetBatchId != null) {
      for (final batch in position.batches) {
        if (batch.id != targetBatchId) continue;
        if (batch.remainingQuantity <= 0) return [];
        return [
          _SellAction(batch, math.min(targetQty, batch.remainingQuantity)),
        ];
      }
      return [];
    }

    var remaining = math.min(targetQty, position.totalRemaining);
    final batches = [...position.batches]..sort((a, b) {
        final aPlan = a.hasPlanSnapshot ? 0 : 1;
        final bPlan = b.hasPlanSnapshot ? 0 : 1;
        if (aPlan != bPlan) return aPlan.compareTo(bPlan);
        return a.buyDate.compareTo(b.buyDate);
      });

    final actions = <_SellAction>[];
    for (final batch in batches) {
      if (remaining <= 0) break;
      if (batch.id == null || batch.remainingQuantity <= 0) continue;
      final qty = math.min(remaining, batch.remainingQuantity);
      if (qty <= 0) continue;
      actions.add(_SellAction(batch, qty));
      remaining -= qty;
    }
    return actions;
  }

  Future<void> _recordIrrigationPlan(_HarvestPlan plan) async {
    final ctx = widget.stockContext;
    if (ctx?.code == null ||
        ctx?.name == null ||
        plan.suggestedBuyQty <= 0 ||
        plan.lowerPrice <= 0) {
      _showSnack('没有可入账的低吸方案');
      return;
    }
    final assetType = ctx!.assetType ?? _assetType;
    final market = ctx.market ?? 'SH';
    final code = ctx.code!;
    final name = ctx.name!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ExecutionConfirmDialog(
        title: '确认记录低吸',
        icon: Icons.grass_outlined,
        iconColor: AppTheme.primaryGreen,
        summary:
            '$name $code\n买入 ${Formatters.quantity(plan.suggestedBuyQty)}$_unit · 价格 ¥${Formatters.price(plan.lowerPrice)}',
        metrics: [
          _ConfirmMetric('预计占用现金', Formatters.money(plan.suggestedBuyCash)),
          _ConfirmMetric('记录类型', '新增播种批次'),
          _ConfirmMetric('记录时间', Formatters.dateTimeFull(DateTime.now())),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final batch = HoldingBatch(
      assetType: assetType,
      market: market,
      stockCode: code,
      stockName: name,
      buyPrice: plan.lowerPrice,
      quantity: plan.suggestedBuyQty,
      buyDate: DateTime.now(),
      note: '来自收割计算：灌溉低吸',
    );
    await ref.read(holdingPositionsProvider.notifier).addBatch(batch);
    if (!mounted) return;
    _showSnack('低吸已作为新播种批次入账');
    AppNavigation.goHomeTab(context, HomeTab.holding);
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _currentPriceController.dispose();
    _remainingCostController.dispose();
    _quantityController.dispose();
    _gridStepController.dispose();
    _atrController.dispose();
    _atrMultipleController.dispose();
    _recentHighController.dispose();
    super.dispose();
  }

  _HarvestPlan get _plan {
    final price = math.max(0.0, _currentPrice);
    final quantity = math.max(0.0, _quantity);
    final remainingCost = math.max(0.0, _remainingCost);

    final double lower;
    final double upper;
    if (_mode == 'grid') {
      lower = price * (1 - _gridStep);
      upper = price * (1 + _gridStep);
    } else if (_mode == 'chandelier') {
      // 吊灯移动止盈：止盈线 = 近期高点 − ATR × 倍数；跌破即收割
      final high = _recentHigh > 0 ? _recentHigh : price;
      final stopLine = math.max(0.0, high - _atr * _atrMultiple);
      lower = stopLine;
      upper = high; // 高点作为回收计价参考（利润奔跑上限）
    } else {
      // ATR 通道
      lower = math.max(0.0, price - _atr * _atrMultiple);
      upper = price + _atr * _atrMultiple;
    }

    final zeroCostSellQty = upper > 0
        ? _roundSellQuantity(math.min(quantity, remainingCost / upper))
        : 0.0;
    final freeQuantity = math.max(0.0, quantity - zeroCostSellQty);
    final recoveredAtUpper = zeroCostSellQty * upper;
    final gapAfterSell = math.max(0.0, remainingCost - recoveredAtUpper);

    final suggestedBuyCash = remainingCost > 0 ? remainingCost * 0.12 : 0.0;
    final suggestedBuyQty =
        lower > 0 ? _roundBuyQuantity(suggestedBuyCash / lower) : 0.0;

    return _HarvestPlan(
      lowerPrice: lower,
      upperPrice: upper,
      zeroCostSellQty: zeroCostSellQty,
      freeQuantity: freeQuantity,
      recoveredAtUpper: recoveredAtUpper,
      gapAfterSell: gapAfterSell,
      suggestedBuyQty: suggestedBuyQty,
      suggestedBuyCash: suggestedBuyQty * lower,
    );
  }

  double _roundSellQuantity(double qty) {
    if (_isFund) return (qty * 10000).ceil() / 10000;
    return (qty / 100).ceil() * 100;
  }

  double _roundBuyQuantity(double qty) {
    if (_isFund) return (qty * 10000).floor() / 10000;
    return (qty / 100).floor() * 100;
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;

    return Scaffold(
      appBar: AppBar(
        title: const Text('收割计算'),
        actions: const [HomeTabMenuButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          if (widget.stockContext?.name != null)
            _ContextBanner(ctx: widget.stockContext!)
          else
            const _IntroCard(),
          const SizedBox(height: 16),
          _ConfigCard(
            assetType: _assetType,
            mode: _mode,
            currentPriceController: _currentPriceController,
            remainingCostController: _remainingCostController,
            quantityController: _quantityController,
            gridStepController: _gridStepController,
            atrController: _atrController,
            atrMultipleController: _atrMultipleController,
            recentHighController: _recentHighController,
            atrAutoLoading: _atrAutoLoading,
            atrAutoLoaded: _atrAutoLoaded,
            highAutoLoading: _highAutoLoading,
            highAutoLoaded: _highAutoLoaded,
            hasStockContext: widget.stockContext?.code != null,
            onAssetTypeChanged: (value) => setState(() => _assetType = value),
            onModeChanged: (value) {
              setState(() => _mode = value);
              if (value == 'atr' || value == 'chandelier') _autoLoadAtr();
              if (value == 'chandelier') _autoLoadRecentHigh();
            },
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          _RangeCard(plan: plan, mode: _mode),
          const SizedBox(height: 12),
          _ZeroCostActionCard(
            plan: plan,
            unit: _unit,
            stockName: widget.stockContext?.name,
            canRecord: widget.stockContext?.code != null,
            onRecord: () => _recordHarvestPlan(plan),
          ),
          const SizedBox(height: 12),
          _IrrigationCard(
            plan: plan,
            unit: _unit,
            canRecord: widget.stockContext?.code != null,
            onRecord: () => _recordIrrigationPlan(plan),
          ),
          const SizedBox(height: 12),
          const _DisciplineCard(),
        ],
      ),
    );
  }
}

class _ContextBanner extends StatelessWidget {
  final StockContext ctx;
  const _ContextBanner({required this.ctx});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen.withValues(alpha: 0.14),
            AppTheme.accent.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_graph, color: AppTheme.primaryGreen, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ctx.name ?? '',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (ctx.code != null)
                  Text(
                    '${ctx.assetType == 'fund' ? '基金' : '股票'} · ${ctx.code}  已从持仓自动填充',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen.withValues(alpha: 0.14),
            AppTheme.accent.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '量化收割机',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '用网格、ATR通道或吊灯移动止盈计算纪律价位，只输出策略建议提示。',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final String assetType;
  final String mode;
  final TextEditingController currentPriceController;
  final TextEditingController remainingCostController;
  final TextEditingController quantityController;
  final TextEditingController gridStepController;
  final TextEditingController atrController;
  final TextEditingController atrMultipleController;
  final TextEditingController recentHighController;
  final bool atrAutoLoading;
  final bool atrAutoLoaded;
  final bool highAutoLoading;
  final bool highAutoLoaded;
  final bool hasStockContext;
  final ValueChanged<String> onAssetTypeChanged;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onChanged;

  const _ConfigCard({
    required this.assetType,
    required this.mode,
    required this.currentPriceController,
    required this.remainingCostController,
    required this.quantityController,
    required this.gridStepController,
    required this.atrController,
    required this.atrMultipleController,
    required this.recentHighController,
    required this.atrAutoLoading,
    required this.atrAutoLoaded,
    required this.highAutoLoading,
    required this.highAutoLoaded,
    required this.hasStockContext,
    required this.onAssetTypeChanged,
    required this.onModeChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isFund = assetType == 'fund';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '收割参数',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _SegmentedRow(
            leftLabel: '股票',
            rightLabel: '基金',
            selectedRight: isFund,
            onLeft: () => onAssetTypeChanged('stock'),
            onRight: () => onAssetTypeChanged('fund'),
          ),
          const SizedBox(height: 12),
          _ModeTriRow(
            mode: mode,
            onChanged: onModeChanged,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: isFund ? '当前净值' : '当前价',
                  suffix: '元',
                  controller: currentPriceController,
                  decimals: 4,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: '剩余本金缺口',
                  suffix: '元',
                  controller: remainingCostController,
                  decimals: 3,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: isFund ? '剩余份额' : '剩余股数',
                  suffix: isFund ? '份' : '股',
                  controller: quantityController,
                  decimals: isFund ? 4 : 0,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: mode == 'grid'
                    ? _NumberField(
                        label: '网格间距',
                        suffix: '%',
                        controller: gridStepController,
                        onChanged: onChanged,
                      )
                    : Stack(
                        children: [
                          _NumberField(
                            label: 'ATR',
                            suffix: '元',
                            controller: atrController,
                            decimals: 4,
                            onChanged: onChanged,
                          ),
                          if (atrAutoLoading)
                            const Positioned(
                              right: 0,
                              top: 20,
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ),
                          if (atrAutoLoaded && hasStockContext)
                            const Positioned(
                              right: 0,
                              top: 22,
                              child: Icon(
                                Icons.auto_awesome,
                                size: 13,
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          if (mode == 'atr') ...[
            const SizedBox(height: 12),
            _NumberField(
              label: 'ATR倍数',
              suffix: '倍',
              controller: atrMultipleController,
              onChanged: onChanged,
            ),
          ],
          if (mode == 'chandelier') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      _NumberField(
                        label: isFund ? '近22日最高净值' : '近22日最高价',
                        suffix: '元',
                        controller: recentHighController,
                        decimals: 4,
                        onChanged: onChanged,
                      ),
                      if (highAutoLoading)
                        const Positioned(
                          right: 0,
                          top: 20,
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      if (highAutoLoaded && hasStockContext)
                        const Positioned(
                          right: 0,
                          top: 22,
                          child: Icon(
                            Icons.auto_awesome,
                            size: 13,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: '吊灯倍数',
                    suffix: '倍',
                    controller: atrMultipleController,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.accentGold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '吊灯止盈线 = 近期高点 − ATR × 倍数。价格创新高则止盈线随之上移，跌破止盈线才触发收割，适合单边上涨行情。',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RangeCard extends StatelessWidget {
  final _HarvestPlan plan;
  final String mode;

  const _RangeCard({required this.plan, required this.mode});

  @override
  Widget build(BuildContext context) {
    final title = mode == 'grid'
        ? '网格区间'
        : mode == 'chandelier'
            ? '吊灯止盈区间'
            : 'ATR波动区间';
    final lowerLabel = mode == 'chandelier' ? '止盈触发线（跌破收割）' : '播种触发线';
    final upperLabel = mode == 'chandelier' ? '高点计价参考' : '回收触发线';
    return _InfoCard(
      title: title,
      children: [
        _MetricLine(
          label: lowerLabel,
          value: '¥${Formatters.price(plan.lowerPrice)}',
          color: AppTheme.primaryGreen,
        ),
        _MetricLine(
          label: upperLabel,
          value: '¥${Formatters.price(plan.upperPrice)}',
          color: AppTheme.accentGold,
        ),
      ],
    );
  }
}

class _ZeroCostActionCard extends StatelessWidget {
  final _HarvestPlan plan;
  final String unit;
  final String? stockName;
  final bool canRecord;
  final VoidCallback onRecord;

  const _ZeroCostActionCard({
    required this.plan,
    required this.unit,
    required this.canRecord,
    required this.onRecord,
    this.stockName,
  });

  @override
  Widget build(BuildContext context) {
    final canZero = plan.gapAfterSell <= 0 && plan.zeroCostSellQty > 0;
    final hasData = plan.zeroCostSellQty > 0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: canZero
              ? AppTheme.accentGold.withValues(alpha: 0.6)
              : AppTheme.borderColor,
          width: canZero ? 1.5 : 0.5,
        ),
        gradient: canZero
            ? LinearGradient(
                colors: [
                  AppTheme.accentGold.withValues(alpha: 0.12),
                  AppTheme.primaryGreen.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: canZero ? null : AppTheme.bgCard,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                canZero ? Icons.emoji_events : Icons.auto_graph_outlined,
                color: canZero ? AppTheme.accentGold : AppTheme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '零成本收割提示',
                style: TextStyle(
                  color: canZero ? AppTheme.accentGold : AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (canZero && hasData) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.accentGold.withValues(alpha: 0.4)),
              ),
              child: Text(
                '卖出 ${Formatters.quantity(plan.zeroCostSellQty)}$unit（触发价 ¥${Formatters.price(plan.upperPrice)}），'
                '即可让剩余 ${Formatters.quantity(plan.freeQuantity)}$unit${stockName != null ? ' 的 $stockName' : ''} 持仓成本降至 0 元！',
                style: const TextStyle(
                  color: AppTheme.accentGold,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _MetricLine(
            label: '触发后回收数量',
            value: hasData
                ? '${Formatters.quantity(plan.zeroCostSellQty)}$unit'
                : '—',
            color: AppTheme.accentGold,
          ),
          _MetricLine(
            label: '预计回收现金',
            value: hasData ? Formatters.money(plan.recoveredAtUpper) : '—',
            color: AppTheme.primaryGreen,
          ),
          _MetricLine(
            label: canZero ? '剩余零成本仓位' : '回收后仍差本金',
            value: canZero
                ? '${Formatters.quantity(plan.freeQuantity)}$unit'
                : Formatters.money(plan.gapAfterSell),
            color: canZero ? AppTheme.accentGold : AppTheme.riskRed,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: canRecord && hasData ? onRecord : null,
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('记录本次回收'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGold,
                foregroundColor: AppTheme.bgDark,
                disabledBackgroundColor: AppTheme.bgCardLight,
                disabledForegroundColor: AppTheme.textMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IrrigationCard extends StatelessWidget {
  final _HarvestPlan plan;
  final String unit;
  final bool canRecord;
  final VoidCallback onRecord;

  const _IrrigationCard({
    required this.plan,
    required this.unit,
    required this.canRecord,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = plan.suggestedBuyQty > 0;
    return _InfoCard(
      title: '灌溉低吸提示',
      children: [
        _MetricLine(
          label: '触发价',
          value: '¥${Formatters.price(plan.lowerPrice)}',
          color: AppTheme.primaryGreen,
        ),
        _MetricLine(
          label: '试探播种',
          value: '${Formatters.quantity(plan.suggestedBuyQty)}$unit',
          color: AppTheme.accent,
        ),
        _MetricLine(
          label: '预计占用现金',
          value: Formatters.money(plan.suggestedBuyCash),
          color: AppTheme.textPrimary,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: canRecord && hasData ? onRecord : null,
            icon: const Icon(Icons.grass_outlined, size: 18),
            label: const Text('记录本次低吸'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.bgCardLight,
              disabledForegroundColor: AppTheme.textMuted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DisciplineCard extends StatelessWidget {
  const _DisciplineCard();

  @override
  Widget build(BuildContext context) {
    const rules = [
      '只在计划价位触发后行动，盘中情绪不能改参数。',
      '收割优先回收本金，不把浮盈当作确定收益。',
      '低吸只用于原计划内标的，排雷失败的资产不允许灌溉。',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '执行纪律',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...rules.map((rule) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.rule_outlined,
                        color: AppTheme.accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricLine({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedRow extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool selectedRight;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _SegmentedRow({
    required this.leftLabel,
    required this.rightLabel,
    required this.selectedRight,
    required this.onLeft,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SegmentButton(
            label: leftLabel,
            selected: !selectedRight,
            onTap: onLeft,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SegmentButton(
            label: rightLabel,
            selected: selectedRight,
            onTap: onRight,
          ),
        ),
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.15)
              : AppTheme.bgCardLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.accent : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ModeTriRow extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _ModeTriRow({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('grid', '网格'),
      ('atr', 'ATR通道'),
      ('chandelier', '吊灯止盈'),
    ];
    return Row(
      children: List.generate(items.length, (i) {
        final key = items[i].$1;
        final label = items[i].$2;
        final selected = mode == key;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 8),
            child: _SegmentButton(
              label: label,
              selected: selected,
              onTap: () => onChanged(key),
            ),
          ),
        );
      }),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final int decimals;
  final VoidCallback onChanged;

  const _NumberField({
    required this.label,
    required this.suffix,
    required this.controller,
    this.decimals = 2,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = decimals == 0
        ? FilteringTextInputFormatter.digitsOnly
        : FilteringTextInputFormatter.allow(
            RegExp('^\\d+\\.?\\d{0,$decimals}'),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [formatter],
          onChanged: (_) => onChanged(),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            suffixText: suffix,
            suffixStyle: const TextStyle(color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }
}

class _ExecutionConfirmDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String summary;
  final List<_ConfirmMetric> metrics;
  final String? warning;

  const _ExecutionConfirmDialog({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.summary,
    required this.metrics,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgCardLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderColor, width: 0.5),
              ),
              child: Text(
                summary,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...metrics.map(
              (metric) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        metric.label,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      metric.value,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (warning != null) ...[
              const SizedBox(height: 4),
              Text(
                warning!,
                style: const TextStyle(
                  color: AppTheme.accentGold,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('确认入账'),
        ),
      ],
    );
  }
}

class _ConfirmMetric {
  final String label;
  final String value;

  const _ConfirmMetric(this.label, this.value);
}

class _SellAction {
  final HoldingBatch batch;
  final double quantity;

  const _SellAction(this.batch, this.quantity);
}

class _HarvestPlan {
  final double lowerPrice;
  final double upperPrice;
  final double zeroCostSellQty;
  final double freeQuantity;
  final double recoveredAtUpper;
  final double gapAfterSell;
  final double suggestedBuyQty;
  final double suggestedBuyCash;

  const _HarvestPlan({
    required this.lowerPrice,
    required this.upperPrice,
    required this.zeroCostSellQty,
    required this.freeQuantity,
    required this.recoveredAtUpper,
    required this.gapAfterSell,
    required this.suggestedBuyQty,
    required this.suggestedBuyCash,
  });
}
