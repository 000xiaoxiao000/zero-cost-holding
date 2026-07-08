import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class HarvestCalculatorScreen extends StatefulWidget {
  const HarvestCalculatorScreen({super.key});

  @override
  State<HarvestCalculatorScreen> createState() =>
      _HarvestCalculatorScreenState();
}

class _HarvestCalculatorScreenState extends State<HarvestCalculatorScreen> {
  final _currentPriceController = TextEditingController(text: '10.00');
  final _remainingCostController = TextEditingController(text: '20000');
  final _quantityController = TextEditingController(text: '3000');
  final _gridStepController = TextEditingController(text: '8');
  final _atrController = TextEditingController(text: '0.45');
  final _atrMultipleController = TextEditingController(text: '2');

  String _assetType = 'stock';
  String _mode = 'grid';

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

  String get _unit => _isFund ? '份' : '股';

  @override
  void dispose() {
    _currentPriceController.dispose();
    _remainingCostController.dispose();
    _quantityController.dispose();
    _gridStepController.dispose();
    _atrController.dispose();
    _atrMultipleController.dispose();
    super.dispose();
  }

  _HarvestPlan get _plan {
    final price = math.max(0.0, _currentPrice);
    final quantity = math.max(0.0, _quantity);
    final remainingCost = math.max(0.0, _remainingCost);

    final lower = _mode == 'grid'
        ? price * (1 - _gridStep)
        : math.max(0.0, price - _atr * _atrMultiple);
    final upper =
        _mode == 'grid' ? price * (1 + _gridStep) : price + _atr * _atrMultiple;

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
      appBar: AppBar(title: const Text('收割计算')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
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
            onAssetTypeChanged: (value) => setState(() => _assetType = value),
            onModeChanged: (value) => setState(() => _mode = value),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          _RangeCard(plan: plan, mode: _mode),
          const SizedBox(height: 12),
          _ZeroCostActionCard(plan: plan, unit: _unit),
          const SizedBox(height: 12),
          _IrrigationCard(plan: plan, unit: _unit),
          const SizedBox(height: 12),
          const _DisciplineCard(),
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
            '用网格或ATR计算纪律价位，只输出策略建议提示，不连接券商、不触达执行。',
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
          _SegmentedRow(
            leftLabel: '网格',
            rightLabel: 'ATR',
            selectedRight: mode == 'atr',
            onLeft: () => onModeChanged('grid'),
            onRight: () => onModeChanged('atr'),
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
                    : _NumberField(
                        label: 'ATR',
                        suffix: '元',
                        controller: atrController,
                        decimals: 4,
                        onChanged: onChanged,
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
    return _InfoCard(
      title: mode == 'grid' ? '网格区间' : 'ATR波动区间',
      children: [
        _MetricLine(
          label: '播种触发线',
          value: '¥${Formatters.price(plan.lowerPrice)}',
          color: AppTheme.primaryGreen,
        ),
        _MetricLine(
          label: '回收触发线',
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

  const _ZeroCostActionCard({required this.plan, required this.unit});

  @override
  Widget build(BuildContext context) {
    final canZero = plan.gapAfterSell <= 0 && plan.zeroCostSellQty > 0;
    return _InfoCard(
      title: '零成本收割提示',
      children: [
        _MetricLine(
          label: '触发后回收数量',
          value: '${Formatters.quantity(plan.zeroCostSellQty)}$unit',
          color: AppTheme.accentGold,
        ),
        _MetricLine(
          label: '预计回收现金',
          value: Formatters.largeNumber(plan.recoveredAtUpper),
          color: AppTheme.primaryGreen,
        ),
        _MetricLine(
          label: canZero ? '剩余零成本仓位' : '仍差本金',
          value: canZero
              ? '${Formatters.quantity(plan.freeQuantity)}$unit'
              : Formatters.largeNumber(plan.gapAfterSell),
          color: canZero ? AppTheme.accentGold : AppTheme.riskRed,
        ),
      ],
    );
  }
}

class _IrrigationCard extends StatelessWidget {
  final _HarvestPlan plan;
  final String unit;

  const _IrrigationCard({required this.plan, required this.unit});

  @override
  Widget build(BuildContext context) {
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
          value: Formatters.largeNumber(plan.suggestedBuyCash),
          color: AppTheme.textPrimary,
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
