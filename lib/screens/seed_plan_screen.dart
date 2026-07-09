import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stock_context.dart';
import '../screens/add_holding_batch_screen.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

// ── 仓位权重模式 ────────────────────────────────────────────────────────────────

enum WeightMode {
  pyramid,   // 正金字塔：越跌越重（后批权重递增）
  equal,     // 等额：每批相同资金
  inverted,  // 倒金字塔：越跌越轻（后批权重递减）
}

extension WeightModeLabel on WeightMode {
  String get label {
    switch (this) {
      case WeightMode.pyramid:  return '正金字塔';
      case WeightMode.equal:    return '等额';
      case WeightMode.inverted: return '倒金字塔';
    }
  }
  String get hint {
    switch (this) {
      case WeightMode.pyramid:  return '越跌仓位越重';
      case WeightMode.equal:    return '每批资金相等';
      case WeightMode.inverted: return '越跌仓位越轻';
    }
  }
}

// ── 定投周期 ────────────────────────────────────────────────────────────────────

enum DcaPeriod { weekly, biweekly, monthly }

extension DcaPeriodLabel on DcaPeriod {
  String get label {
    switch (this) {
      case DcaPeriod.weekly:    return '每周';
      case DcaPeriod.biweekly: return '每两周';
      case DcaPeriod.monthly:  return '每月';
    }
  }
  int get days {
    switch (this) {
      case DcaPeriod.weekly:    return 7;
      case DcaPeriod.biweekly: return 14;
      case DcaPeriod.monthly:  return 30;
    }
  }
}

// ── SeedPlanScreen ──────────────────────────────────────────────────────────────

class SeedPlanScreen extends StatefulWidget {
  final StockContext? stockContext;

  const SeedPlanScreen({super.key, this.stockContext});

  @override
  State<SeedPlanScreen> createState() => _SeedPlanScreenState();
}

class _SeedPlanScreenState extends State<SeedPlanScreen>
    with SingleTickerProviderStateMixin {
  // ── Tab controller（播种计划 / 定投模式）
  late final TabController _tabController;

  // ── 播种计划参数
  late final TextEditingController _capitalController;
  late final TextEditingController _startPriceController;
  late final TextEditingController _seedCountController;
  late final TextEditingController _dropStepController;
  final _reboundController = TextEditingController(text: '30');
  final _commissionController = TextEditingController(text: '5');
  late String _assetType;
  late WeightMode _weightMode;

  // ── 定投模式参数
  final _dcaAmountController = TextEditingController(text: '3000');
  final _dcaSessionsController = TextEditingController(text: '12');
  final _dcaPriceLimitController = TextEditingController(text: '');
  final _dcaReboundController = TextEditingController(text: '20');
  DcaPeriod _dcaPeriod = DcaPeriod.monthly;
  bool _dcaUsePriceLimit = false;

  bool get _isFund => _assetType == 'fund';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final ctx = widget.stockContext;
    _assetType = ctx?.assetType ?? 'stock';
    _capitalController = TextEditingController(text: '100000');
    final startPrice = ctx?.currentPrice ?? ctx?.avgCostPrice;
    _startPriceController = TextEditingController(
      text: startPrice != null ? startPrice.toStringAsFixed(3) : '10.000',
    );
    if (startPrice != null) {
      _dcaPriceLimitController.text = startPrice.toStringAsFixed(3);
    }
    // 排雷页策略顾问推荐参数，缺失时回落到经验默认值
    _seedCountController = TextEditingController(
      text: (ctx?.recommendSeedCount ?? 5).toString(),
    );
    _dropStepController = TextEditingController(
      text: (ctx?.recommendDropStep ?? 8).toString(),
    );
    _weightMode = _weightModeFromKey(ctx?.weightModeKey);
  }

  WeightMode _weightModeFromKey(String? key) {
    switch (key) {
      case 'pyramid':  return WeightMode.pyramid;
      case 'inverted': return WeightMode.inverted;
      case 'equal':    return WeightMode.equal;
      default:         return WeightMode.equal;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _capitalController.dispose();
    _startPriceController.dispose();
    _seedCountController.dispose();
    _dropStepController.dispose();
    _reboundController.dispose();
    _commissionController.dispose();
    _dcaAmountController.dispose();
    _dcaSessionsController.dispose();
    _dcaPriceLimitController.dispose();
    _dcaReboundController.dispose();
    super.dispose();
  }

  // ── 播种计划 getters

  double get _capital => double.tryParse(_capitalController.text) ?? 0;
  double get _startPrice => double.tryParse(_startPriceController.text) ?? 0;
  int get _seedCount {
    final value = int.tryParse(_seedCountController.text) ?? 0;
    return value.clamp(1, 12).toInt();
  }
  double get _dropStep {
    final value = (double.tryParse(_dropStepController.text) ?? 0) / 100;
    return value.clamp(0.0, 0.95).toDouble();
  }
  double get _rebound {
    final value = (double.tryParse(_reboundController.text) ?? 0) / 100;
    return math.max(0.0, value);
  }
  double get _commission => double.tryParse(_commissionController.text) ?? 0;

  /// 正金字塔权重：第 i 批（0-indexed）权重 = i+1；归一化后返回每批资金
  List<double> _trancheCapitals() {
    final n = _seedCount;
    if (n <= 0) return [];
    switch (_weightMode) {
      case WeightMode.equal:
        return List.filled(n, _capital / n);
      case WeightMode.pyramid:
        // 权重递增：1, 2, 3, ..., n
        final total = n * (n + 1) / 2;
        return List.generate(n, (i) => _capital * (i + 1) / total);
      case WeightMode.inverted:
        // 权重递减：n, n-1, ..., 1
        final total = n * (n + 1) / 2;
        return List.generate(n, (i) => _capital * (n - i) / total);
    }
  }

  List<_SeedSlice> get _plan {
    if (_capital <= 0 || _startPrice <= 0 || _seedCount <= 0) return [];
    final capitals = _trancheCapitals();
    return List.generate(_seedCount, (i) {
      final buyPrice = _startPrice * math.pow(1 - _dropStep, i);
      final trancheCapital = capitals[i];
      final quantity = _isFund
          ? ((trancheCapital - _commission) / buyPrice * 10000).floor() / 10000
          : (((trancheCapital - _commission) / buyPrice / 100).floor() * 100)
              .toDouble();
      final cost = quantity * buyPrice + _commission;
      final targetPrice = buyPrice * (1 + _rebound);
      final recoverQuantity = targetPrice > 0
          ? math.min(
              quantity,
              _isFund
                  ? ((cost / targetPrice) * 10000).ceil() / 10000
                  : (cost / targetPrice).ceilToDouble(),
            )
          : 0.0;
      return _SeedSlice(
        index: i + 1,
        buyPrice: buyPrice.toDouble(),
        quantity: quantity,
        cost: cost,
        targetPrice: targetPrice,
        recoverQuantity: recoverQuantity,
        freeQuantity: math.max(0.0, quantity - recoverQuantity),
      );
    }).where((s) => s.quantity > 0).toList();
  }

  // ── 定投计划 getters

  double get _dcaAmount => double.tryParse(_dcaAmountController.text) ?? 0;
  int get _dcaSessions {
    final v = int.tryParse(_dcaSessionsController.text) ?? 0;
    return v.clamp(1, 60).toInt();
  }
  double? get _dcaPriceLimit =>
      _dcaUsePriceLimit ? double.tryParse(_dcaPriceLimitController.text) : null;
  double get _dcaRebound {
    final v = (double.tryParse(_dcaReboundController.text) ?? 0) / 100;
    return math.max(0.0, v);
  }

  List<_DcaSlice> get _dcaPlan {
    if (_dcaAmount <= 0 || _dcaSessions <= 0) return [];
    final now = DateTime.now();
    return List.generate(_dcaSessions, (i) {
      final date = now.add(Duration(days: _dcaPeriod.days * i));
      return _DcaSlice(
        index: i + 1,
        date: date,
        amount: _dcaAmount,
        priceLimit: _dcaPriceLimit,
        reboundTarget: _dcaRebound,
        period: _dcaPeriod,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.stockContext;
    return Scaffold(
      appBar: AppBar(
        title: Text(ctx?.name != null ? '播种计划 · ${ctx!.name}' : '播种计划'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.accent,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(icon: Icon(Icons.grass_outlined, size: 16), text: '分批播种'),
            Tab(icon: Icon(Icons.calendar_today_outlined, size: 16), text: '定投模式'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SeedPlanTab(
            ctx: ctx,
            isFund: _isFund,
            plan: _plan,
            capital: _capital,
            capitalController: _capitalController,
            startPriceController: _startPriceController,
            seedCountController: _seedCountController,
            dropStepController: _dropStepController,
            reboundController: _reboundController,
            commissionController: _commissionController,
            assetType: _assetType,
            weightMode: _weightMode,
            onAssetTypeChanged: (t) => setState(() => _assetType = t),
            onWeightModeChanged: (m) => setState(() => _weightMode = m),
            onChanged: () => setState(() {}),
          ),
          _DcaPlanTab(
            ctx: ctx,
            isFund: _isFund,
            plan: _dcaPlan,
            amountController: _dcaAmountController,
            sessionsController: _dcaSessionsController,
            priceLimitController: _dcaPriceLimitController,
            reboundController: _dcaReboundController,
            period: _dcaPeriod,
            usePriceLimit: _dcaUsePriceLimit,
            assetType: _assetType,
            onPeriodChanged: (p) => setState(() => _dcaPeriod = p),
            onUsePriceLimitChanged: (v) => setState(() => _dcaUsePriceLimit = v),
            onChanged: () => setState(() {}),
          ),
        ],
      ),
    );
  }
}

// ── 分批播种 Tab ────────────────────────────────────────────────────────────────

class _SeedPlanTab extends StatelessWidget {
  final StockContext? ctx;
  final bool isFund;
  final List<_SeedSlice> plan;
  final double capital;
  final TextEditingController capitalController;
  final TextEditingController startPriceController;
  final TextEditingController seedCountController;
  final TextEditingController dropStepController;
  final TextEditingController reboundController;
  final TextEditingController commissionController;
  final String assetType;
  final WeightMode weightMode;
  final ValueChanged<String> onAssetTypeChanged;
  final ValueChanged<WeightMode> onWeightModeChanged;
  final VoidCallback onChanged;

  const _SeedPlanTab({
    required this.ctx,
    required this.isFund,
    required this.plan,
    required this.capital,
    required this.capitalController,
    required this.startPriceController,
    required this.seedCountController,
    required this.dropStepController,
    required this.reboundController,
    required this.commissionController,
    required this.assetType,
    required this.weightMode,
    required this.onAssetTypeChanged,
    required this.onWeightModeChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final totalCost = plan.fold(0.0, (sum, s) => sum + s.cost);
    final totalQuantity = plan.fold(0.0, (sum, s) => sum + s.quantity);
    final freeQuantity = plan.fold(0.0, (sum, s) => sum + s.freeQuantity);
    final unit = isFund ? '份' : '股';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        if (ctx?.name != null)
          _StockContextBanner(ctx: ctx!)
        else
          _PrincipleBand(
            title: '本金先活下来，利润用时间发芽',
            subtitle: '先拆仓播种，价格或净值越低越有计划；触发回收条件后记录部分现金回笼，保留剩余资产作为零成本种子。',
          ),
        const SizedBox(height: 16),
        if (ctx != null && (ctx!.pePercentile != null || ctx!.industryCycle != null))
          _ValuationHintCard(ctx: ctx!),
        if (ctx != null && (ctx!.pePercentile != null || ctx!.industryCycle != null))
          const SizedBox(height: 16),
        _PlannerForm(
          capitalController: capitalController,
          startPriceController: startPriceController,
          seedCountController: seedCountController,
          dropStepController: dropStepController,
          reboundController: reboundController,
          commissionController: commissionController,
          assetType: assetType,
          weightMode: weightMode,
          onAssetTypeChanged: onAssetTypeChanged,
          onWeightModeChanged: onWeightModeChanged,
          onChanged: onChanged,
        ),
        const SizedBox(height: 16),
        _PlanSummary(
          totalCost: totalCost,
          totalQuantity: totalQuantity,
          freeQuantity: freeQuantity,
          idleCash: math.max(0.0, capital - totalCost),
          unit: unit,
        ),
        const SizedBox(height: 16),
        _SectionTitle(
          title: '分批播种表',
          subtitle: '${weightMode.label} · 按输入参数自动推演',
        ),
        const SizedBox(height: 10),
        if (plan.isEmpty)
          const _EmptyState()
        else
          ...plan.map((slice) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SeedSliceCard(
                  slice: slice,
                  unit: unit,
                  onRecord: ctx == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddHoldingBatchScreen(
                                stockContext: ctx!.copyWith(
                                  planBuyPrice: slice.buyPrice,
                                  planQuantity: slice.quantity,
                                ),
                              ),
                            ),
                          ),
                ),
              )),
        const SizedBox(height: 12),
        if (plan.isNotEmpty && ctx != null)
          _QuickRecordBar(ctx: ctx!, firstSlice: plan.first, isFund: isFund),
        if (plan.isNotEmpty && ctx != null) const SizedBox(height: 12),
        const _RiskRules(),
      ],
    );
  }
}

// ── 定投模式 Tab ────────────────────────────────────────────────────────────────

class _DcaPlanTab extends StatelessWidget {
  final StockContext? ctx;
  final bool isFund;
  final List<_DcaSlice> plan;
  final TextEditingController amountController;
  final TextEditingController sessionsController;
  final TextEditingController priceLimitController;
  final TextEditingController reboundController;
  final DcaPeriod period;
  final bool usePriceLimit;
  final String assetType;
  final ValueChanged<DcaPeriod> onPeriodChanged;
  final ValueChanged<bool> onUsePriceLimitChanged;
  final VoidCallback onChanged;

  const _DcaPlanTab({
    required this.ctx,
    required this.isFund,
    required this.plan,
    required this.amountController,
    required this.sessionsController,
    required this.priceLimitController,
    required this.reboundController,
    required this.period,
    required this.usePriceLimit,
    required this.assetType,
    required this.onPeriodChanged,
    required this.onUsePriceLimitChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final unit = isFund ? '份' : '股';
    final totalAmount = plan.fold(0.0, (s, e) => s + e.amount);
    final dcaRebound = plan.isNotEmpty ? plan.first.reboundTarget : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        _DcaIntroBand(ctx: ctx),
        const SizedBox(height: 16),
        _DcaForm(
          amountController: amountController,
          sessionsController: sessionsController,
          priceLimitController: priceLimitController,
          reboundController: reboundController,
          period: period,
          usePriceLimit: usePriceLimit,
          onPeriodChanged: onPeriodChanged,
          onUsePriceLimitChanged: onUsePriceLimitChanged,
          onChanged: onChanged,
        ),
        const SizedBox(height: 16),
        _DcaSummaryCard(
          sessions: plan.length,
          totalAmount: totalAmount,
          period: period,
          priceLimit: usePriceLimit ? double.tryParse(priceLimitController.text) : null,
          reboundPct: dcaRebound,
        ),
        const SizedBox(height: 16),
        _SectionTitle(
          title: '定投计划表',
          subtitle: '${period.label} · 时间+价格双维度触发',
        ),
        const SizedBox(height: 10),
        if (plan.isEmpty)
          const _EmptyState()
        else
          ...plan.map((slice) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DcaSliceCard(slice: slice, unit: unit),
              )),
        const SizedBox(height: 12),
        const _DcaRules(),
      ],
    );
  }
}

class _StockContextBanner extends StatelessWidget {
  final StockContext ctx;
  const _StockContextBanner({required this.ctx});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.16),
            AppTheme.accentGold.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grass, color: AppTheme.accentGold, size: 18),
              const SizedBox(width: 8),
              Text(
                ctx.name ?? '',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              if (ctx.code != null)
                Text(
                  ctx.code!,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ctx.avgCostPrice != null && ctx.avgCostPrice! > 0
                ? '当前成本价 ¥${Formatters.price(ctx.avgCostPrice!)}，已从持仓/排雷自动填入首批价格'
                : '已从排雷自动填入首批价格，请确认参数后生成计划',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ValuationHintCard extends StatelessWidget {
  final StockContext ctx;
  const _ValuationHintCard({required this.ctx});

  @override
  Widget build(BuildContext context) {
    final pe = ctx.pePercentile;
    final cycle = ctx.industryCycle;

    String positionHint;
    Color hintColor;
    if (pe != null && pe <= 30) {
      positionHint = 'PE百分位 ${pe.toInt()}%，处于历史低位，可考虑较重仓位';
      hintColor = AppTheme.primaryGreen;
    } else if (pe != null && pe >= 70) {
      positionHint = 'PE百分位 ${pe.toInt()}%，估值偏高，建议轻仓首批观察';
      hintColor = AppTheme.riskRed;
    } else {
      positionHint = pe != null
          ? 'PE百分位 ${pe.toInt()}%，估值中性，按计划正常播种'
          : '未获取到估值百分位';
      hintColor = AppTheme.accentGold;
    }

    String cycleHint = '';
    if (cycle == 'up') cycleHint = ' · 行业趋势向上';
    if (cycle == 'down') cycleHint = ' · 行业趋势向下，可缩减批次';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hintColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hintColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.insights, color: hintColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$positionHint$cycleHint',
              style: TextStyle(
                  color: hintColor, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickRecordBar extends StatelessWidget {
  final StockContext ctx;
  final _SeedSlice firstSlice;
  final bool isFund;

  const _QuickRecordBar({
    required this.ctx,
    required this.firstSlice,
    required this.isFund,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddHoldingBatchScreen(
              stockContext: ctx.copyWith(
                planBuyPrice: firstSlice.buyPrice,
                planQuantity: firstSlice.quantity,
              ),
            ),
          ),
        ),
        icon: const Icon(Icons.add_circle_outline, size: 18),
        label: Text(
          '记录第一批入账  ¥${Formatters.price(firstSlice.buyPrice)} · ${Formatters.quantity(firstSlice.quantity)}${isFund ? '份' : '股'}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _PlannerForm extends StatelessWidget {
  final TextEditingController capitalController;
  final TextEditingController startPriceController;
  final TextEditingController seedCountController;
  final TextEditingController dropStepController;
  final TextEditingController reboundController;
  final TextEditingController commissionController;
  final String assetType;
  final WeightMode weightMode;
  final ValueChanged<String> onAssetTypeChanged;
  final ValueChanged<WeightMode> onWeightModeChanged;
  final VoidCallback onChanged;

  const _PlannerForm({
    required this.capitalController,
    required this.startPriceController,
    required this.seedCountController,
    required this.dropStepController,
    required this.reboundController,
    required this.commissionController,
    required this.assetType,
    required this.weightMode,
    required this.onAssetTypeChanged,
    required this.onWeightModeChanged,
    required this.onChanged,
  });

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
          const Text(
            '计划参数',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _PlanAssetTypeSelector(
            assetType: assetType,
            onChanged: onAssetTypeChanged,
          ),
          const SizedBox(height: 12),
          _WeightModeSelector(
            weightMode: weightMode,
            onChanged: onWeightModeChanged,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: '可用本金',
                  suffix: '元',
                  controller: capitalController,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: '首批价格/净值',
                  suffix: '元',
                  controller: startPriceController,
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
                  label: '播种批数',
                  suffix: '批',
                  controller: seedCountController,
                  digitsOnly: true,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: '下跌间距',
                  suffix: '%',
                  controller: dropStepController,
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
                  label: '回收涨幅',
                  suffix: '%',
                  controller: reboundController,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: '单笔费用',
                  suffix: '元',
                  controller: commissionController,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeightModeSelector extends StatelessWidget {
  final WeightMode weightMode;
  final ValueChanged<WeightMode> onChanged;

  const _WeightModeSelector({
    required this.weightMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '仓位权重',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          children: WeightMode.values.map((m) {
            final selected = m == weightMode;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: m != WeightMode.inverted ? 8 : 0,
                ),
                child: GestureDetector(
                  onTap: () => onChanged(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.accent.withValues(alpha: 0.15)
                          : AppTheme.bgCardLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? AppTheme.accent : AppTheme.borderColor,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          m.label,
                          style: TextStyle(
                            color: selected ? AppTheme.accent : AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                        Text(
                          m.hint,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PlanAssetTypeSelector extends StatelessWidget {
  final String assetType;
  final ValueChanged<String> onChanged;

  const _PlanAssetTypeSelector({
    required this.assetType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PlanAssetChip(
          label: '股票',
          selected: assetType == 'stock',
          onTap: () => onChanged('stock'),
        ),
        const SizedBox(width: 10),
        _PlanAssetChip(
          label: '基金',
          selected: assetType == 'fund',
          onTap: () => onChanged('fund'),
        ),
      ],
    );
  }
}

class _PlanAssetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PlanAssetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
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
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final bool digitsOnly;
  final VoidCallback onChanged;

  const _NumberField({
    required this.label,
    required this.suffix,
    required this.controller,
    this.digitsOnly = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            if (digitsOnly)
              FilteringTextInputFormatter.digitsOnly
            else
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
          ],
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

class _PlanSummary extends StatelessWidget {
  final double totalCost;
  final double totalQuantity;
  final double freeQuantity;
  final double idleCash;
  final String unit;

  const _PlanSummary({
    required this.totalCost,
    required this.totalQuantity,
    required this.freeQuantity,
    required this.idleCash,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: '预计投入',
              value: Formatters.largeNumber(totalCost),
            ),
          ),
          Expanded(
            child: _Metric(
              label: '播种数量',
              value: '${Formatters.quantity(totalQuantity)}$unit',
            ),
          ),
          Expanded(
            child: _Metric(
              label: '零成本种子',
              value: '${Formatters.quantity(freeQuantity)}$unit',
            ),
          ),
          Expanded(
            child: _Metric(
              label: '余留现金',
              value: Formatters.largeNumber(idleCash),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeedSliceCard extends StatelessWidget {
  final _SeedSlice slice;
  final String unit;
  final VoidCallback? onRecord;

  const _SeedSliceCard({
    required this.slice,
    required this.unit,
    this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${slice.index}',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '播种 ${Formatters.quantity(slice.quantity)}$unit @ ¥${Formatters.price(slice.buyPrice)}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                Formatters.largeNumber(slice.cost),
                style: const TextStyle(
                  color: AppTheme.accentGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniLine(
                  label: '回收触发价',
                  value: '¥${Formatters.price(slice.targetPrice)}',
                  color: AppTheme.accentGold,
                ),
              ),
              Expanded(
                child: _MiniLine(
                  label: '策略建议提示',
                  value: '${Formatters.quantity(slice.recoverQuantity)}$unit',
                  color: AppTheme.primaryGreen,
                ),
              ),
              Expanded(
                child: _MiniLine(
                  label: '保留种子',
                  value: '${Formatters.quantity(slice.freeQuantity)}$unit',
                  color: AppTheme.accentGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '触发后记录回收 ${Formatters.quantity(slice.recoverQuantity)}$unit，可让剩余 ${Formatters.quantity(slice.freeQuantity)}$unit 进入零成本持有。',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (onRecord != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRecord,
                icon: const Icon(Icons.add_circle_outline, size: 15),
                label: const Text('记录此批入账'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: BorderSide(
                      color: AppTheme.accent.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(fontSize: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RiskRules extends StatelessWidget {
  const _RiskRules();

  @override
  Widget build(BuildContext context) {
    const rules = [
      '单一股票或基金最多使用组合资金的 10%-20%，避免一颗种子拖垮整片田。',
      '只在提前写好的价位追加播种，临盘情绪不改计划。',
      '触发条件后先回收本金，回收后剩余仓位只记录，不再把浮盈当本金加码。',
      '股票基本面恶化、基金策略漂移或流动性风险出现时，零成本思维失效，先处理风险。',
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
            '风控纪律',
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
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppTheme.accent,
                      size: 16,
                    ),
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

class _PrincipleBand extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PrincipleBand({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.16),
            AppTheme.accentGold.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MiniLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniLine({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: const Text(
        '输入有效本金、价格和批数后生成播种计划。',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _SeedSlice {
  final int index;
  final double buyPrice;
  final double quantity;
  final double cost;
  final double targetPrice;
  final double recoverQuantity;
  final double freeQuantity;

  const _SeedSlice({
    required this.index,
    required this.buyPrice,
    required this.quantity,
    required this.cost,
    required this.targetPrice,
    required this.recoverQuantity,
    required this.freeQuantity,
  });
}

// ── 定投介绍横幅 ──────────────────────────────────────────────────────────────────

class _DcaIntroBand extends StatelessWidget {
  final StockContext? ctx;
  const _DcaIntroBand({required this.ctx});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.14),
            AppTheme.primaryGreen.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, color: AppTheme.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                ctx?.name != null ? '定投计划 · ${ctx!.name}' : '时间 + 价格双维度定投',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '时间维度：按设定周期触发买入；价格维度：开启后仅当价格低于上限时才执行，高于上限时跳过等下期。两维度结合，实现纪律性低价建仓。',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }
}

// ── 定投数据模型 ────────────────────────────────────────────────────────────────

class _DcaSlice {
  final int index;
  final DateTime date;
  final double amount;
  final double? priceLimit;
  final double reboundTarget;
  final DcaPeriod period;

  const _DcaSlice({
    required this.index,
    required this.date,
    required this.amount,
    required this.priceLimit,
    required this.reboundTarget,
    required this.period,
  });
}

// ── 定投参数表单 ──────────────────────────────────────────────────────────────────

class _DcaForm extends StatelessWidget {
  final TextEditingController amountController;
  final TextEditingController sessionsController;
  final TextEditingController priceLimitController;
  final TextEditingController reboundController;
  final DcaPeriod period;
  final bool usePriceLimit;
  final ValueChanged<DcaPeriod> onPeriodChanged;
  final ValueChanged<bool> onUsePriceLimitChanged;
  final VoidCallback onChanged;

  const _DcaForm({
    required this.amountController,
    required this.sessionsController,
    required this.priceLimitController,
    required this.reboundController,
    required this.period,
    required this.usePriceLimit,
    required this.onPeriodChanged,
    required this.onUsePriceLimitChanged,
    required this.onChanged,
  });

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
          const Text(
            '定投参数',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            children: DcaPeriod.values.map((p) {
              final selected = p == period;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: p != DcaPeriod.monthly ? 8 : 0),
                  child: GestureDetector(
                    onTap: () => onPeriodChanged(p),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primaryGreen.withValues(alpha: 0.15)
                            : AppTheme.bgCardLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primaryGreen
                              : AppTheme.borderColor,
                        ),
                      ),
                      child: Text(
                        p.label,
                        style: TextStyle(
                          color: selected
                              ? AppTheme.primaryGreen
                              : AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: '每期金额',
                  suffix: '元',
                  controller: amountController,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: '定投期数',
                  suffix: '期',
                  controller: sessionsController,
                  digitsOnly: true,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Switch(
                value: usePriceLimit,
                onChanged: onUsePriceLimitChanged,
                activeColor: AppTheme.primaryGreen,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '启用价格上限（仅当价格低于设定值时执行）',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          if (usePriceLimit) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: '价格上限',
                    suffix: '元',
                    controller: priceLimitController,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: '回弹提醒涨幅',
                    suffix: '%',
                    controller: reboundController,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── 定投汇总卡 ────────────────────────────────────────────────────────────────────

class _DcaSummaryCard extends StatelessWidget {
  final int sessions;
  final double totalAmount;
  final DcaPeriod period;
  final double? priceLimit;
  final double reboundPct;

  const _DcaSummaryCard({
    required this.sessions,
    required this.totalAmount,
    required this.period,
    required this.priceLimit,
    required this.reboundPct,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.primaryGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(child: _Metric(label: '总期数', value: '$sessions 期')),
          Expanded(
              child: _Metric(
                  label: '合计金额',
                  value: Formatters.largeNumber(totalAmount))),
          Expanded(
            child: _Metric(
              label: '价格条件',
              value: priceLimit != null
                  ? '≤¥${Formatters.price(priceLimit!)}'
                  : '无限制',
            ),
          ),
          Expanded(
            child: _Metric(
              label: '回弹提醒',
              value: reboundPct > 0
                  ? '+${(reboundPct * 100).toStringAsFixed(0)}%'
                  : '—',
            ),
          ),
        ],
      ),
    );
  }
}

// ── 定投单期卡片 ──────────────────────────────────────────────────────────────────

class _DcaSliceCard extends StatelessWidget {
  final _DcaSlice slice;
  final String unit;

  const _DcaSliceCard({required this.slice, required this.unit});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${slice.date.year}-${slice.date.month.toString().padLeft(2, '0')}-${slice.date.day.toString().padLeft(2, '0')}';
    final hasLimit = slice.priceLimit != null && slice.priceLimit! > 0;
    final reboundPrice = hasLimit && slice.reboundTarget > 0
        ? slice.priceLimit! * (1 + slice.reboundTarget)
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${slice.index}',
                  style: const TextStyle(
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '第 ${slice.index} 期 · $dateStr',
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      hasLimit
                          ? '条件：价格 ≤ ¥${Formatters.price(slice.priceLimit!)} 时执行'
                          : '无价格限制，到期自动执行',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                Formatters.largeNumber(slice.amount),
                style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (reboundPrice != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.trending_up,
                    size: 13, color: AppTheme.accentGold),
                const SizedBox(width: 5),
                Text(
                  '涨至 ¥${Formatters.price(reboundPrice)} (+${(slice.reboundTarget * 100).toStringAsFixed(0)}%) 时触发回收提醒',
                  style: const TextStyle(
                      color: AppTheme.accentGold, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── 定投纪律卡 ────────────────────────────────────────────────────────────────────

class _DcaRules extends StatelessWidget {
  const _DcaRules();

  @override
  Widget build(BuildContext context) {
    const rules = [
      '到期后先检查价格条件，满足才执行，不因行情高涨强行加仓。',
      '定投是手段，不是目标；基本面恶化时暂停定投，先做排雷。',
      '触发回弹提醒后按计划回收部分仓位，保持零成本思维。',
      '不要在已定投的标的之外叠加临时情绪买入，计划与冲动分开。',
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
            '定投纪律',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...rules.map((rule) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppTheme.primaryGreen, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            height: 1.35),
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
