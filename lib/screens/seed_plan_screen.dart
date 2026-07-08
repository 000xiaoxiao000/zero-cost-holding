import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class SeedPlanScreen extends StatefulWidget {
  const SeedPlanScreen({super.key});

  @override
  State<SeedPlanScreen> createState() => _SeedPlanScreenState();
}

class _SeedPlanScreenState extends State<SeedPlanScreen> {
  final _capitalController = TextEditingController(text: '100000');
  final _startPriceController = TextEditingController(text: '10.00');
  final _seedCountController = TextEditingController(text: '5');
  final _dropStepController = TextEditingController(text: '8');
  final _reboundController = TextEditingController(text: '30');
  final _commissionController = TextEditingController(text: '5');
  String _assetType = 'stock';

  bool get _isFund => _assetType == 'fund';

  @override
  void dispose() {
    _capitalController.dispose();
    _startPriceController.dispose();
    _seedCountController.dispose();
    _dropStepController.dispose();
    _reboundController.dispose();
    _commissionController.dispose();
    super.dispose();
  }

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

  List<_SeedSlice> get _plan {
    if (_capital <= 0 || _startPrice <= 0 || _seedCount <= 0) return [];
    final trancheCapital = _capital / _seedCount;
    return List.generate(_seedCount, (i) {
      final buyPrice = _startPrice * math.pow(1 - _dropStep, i);
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

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final totalCost = plan.fold(0.0, (sum, s) => sum + s.cost);
    final totalQuantity = plan.fold(0.0, (sum, s) => sum + s.quantity);
    final freeQuantity = plan.fold(0.0, (sum, s) => sum + s.freeQuantity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('播种计划'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          _PrincipleBand(
            title: '本金先活下来，利润用时间发芽',
            subtitle: '先拆仓播种，价格或净值越低越有计划；触发回收条件后记录部分现金回笼，保留剩余资产作为零成本种子。',
          ),
          const SizedBox(height: 16),
          _PlannerForm(
            capitalController: _capitalController,
            startPriceController: _startPriceController,
            seedCountController: _seedCountController,
            dropStepController: _dropStepController,
            reboundController: _reboundController,
            commissionController: _commissionController,
            assetType: _assetType,
            onAssetTypeChanged: (type) => setState(() => _assetType = type),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          _PlanSummary(
            totalCost: totalCost,
            totalQuantity: totalQuantity,
            freeQuantity: freeQuantity,
            idleCash: math.max(0.0, _capital - totalCost),
            unit: _isFund ? '份' : '股',
          ),
          const SizedBox(height: 16),
          _SectionTitle(
            title: '分批播种表',
            subtitle: '按输入参数自动推演，不连接券商账户',
          ),
          const SizedBox(height: 10),
          if (plan.isEmpty)
            const _EmptyState()
          else
            ...plan.map((slice) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SeedSliceCard(
                    slice: slice,
                    unit: _isFund ? '份' : '股',
                  ),
                )),
          const SizedBox(height: 12),
          const _RiskRules(),
        ],
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
  final ValueChanged<String> onAssetTypeChanged;
  final VoidCallback onChanged;

  const _PlannerForm({
    required this.capitalController,
    required this.startPriceController,
    required this.seedCountController,
    required this.dropStepController,
    required this.reboundController,
    required this.commissionController,
    required this.assetType,
    required this.onAssetTypeChanged,
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
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
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

  const _SeedSliceCard({
    required this.slice,
    required this.unit,
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
