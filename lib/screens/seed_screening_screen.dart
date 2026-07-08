import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stock.dart';
import '../services/stock_api_service.dart';
import '../theme/app_theme.dart';

class SeedScreeningScreen extends StatefulWidget {
  const SeedScreeningScreen({super.key});

  @override
  State<SeedScreeningScreen> createState() => _SeedScreeningScreenState();
}

class _SeedScreeningScreenState extends State<SeedScreeningScreen> {
  final _codeController = TextEditingController(text: '600519');
  final _nameController = TextEditingController(text: '观察标的');
  final _pePercentileController = TextEditingController(text: '35');
  final _pbPercentileController = TextEditingController(text: '40');
  final _pledgeRatioController = TextEditingController(text: '10');
  final _debtRatioController = TextEditingController(text: '45');
  final _goodwillRatioController = TextEditingController(text: '5');
  final _cashflowMarginController = TextEditingController(text: '8');
  final _dividendYieldController = TextEditingController(text: '3');
  final _dividendYearsController = TextEditingController(text: '5');
  final _currentPriceController = TextEditingController(text: '10.00');
  final _buyTriggerController = TextEditingController(text: '9.20');
  final _harvestTriggerController = TextEditingController(text: '11.50');

  bool _isSt = false;
  bool _delistRisk = false;
  bool _violationGuarantee = false;
  bool _financialFraudRisk = false;
  bool _isAutoLoading = false;
  String _market = 'SH';
  String _industryCycle = 'neutral';
  String _dividendStability = 'stable';
  String _autoStatus = '输入 A 股代码后可自动拉取行情、估值、K线趋势、质押、财务和分红数据。';

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _pePercentileController.dispose();
    _pbPercentileController.dispose();
    _pledgeRatioController.dispose();
    _debtRatioController.dispose();
    _goodwillRatioController.dispose();
    _cashflowMarginController.dispose();
    _dividendYieldController.dispose();
    _dividendYearsController.dispose();
    _currentPriceController.dispose();
    _buyTriggerController.dispose();
    _harvestTriggerController.dispose();
    super.dispose();
  }

  Future<void> _autoScreen() async {
    String input = _codeController.text.trim();
    if (input.isEmpty) {
      setState(() => _autoStatus = '请先输入股票代码或名称。');
      return;
    }

    setState(() {
      _isAutoLoading = true;
      _autoStatus = '正在拉取东方财富公开行情、K线、财务、质押和分红数据...';
    });

    try {
      final service = StockApiService();

      // 若输入非纯数字，先通过名称搜索解析出代码和市场
      if (!RegExp(r'^\d+$').hasMatch(input)) {
        setState(() => _autoStatus = '正在搜索「$input」...');
        final results = await service.searchByName(input);
        if (!mounted) return;
        if (results.isEmpty) {
          setState(() {
            _isAutoLoading = false;
            _autoStatus = '未找到「$input」对应的股票，请确认名称或改用代码。';
          });
          return;
        }
        final matched = results.first;
        input = matched.code;
        setState(() {
          _codeController.text = matched.code;
          _nameController.text = matched.name;
          _market = matched.market;
          _autoStatus = '已匹配到「${matched.name}」(${matched.code})，正在拉取数据...';
        });
      }

      final code = input;
      final stock = await service.fetchStockQuote(code, _market);
      final klines = await service.fetchKlineDaily(code, _market, limit: 120);
      final riskData = await service.fetchAutoRiskData(code, _market);

      if (!mounted) return;
      if (stock == null) {
        setState(() {
          _isAutoLoading = false;
          _autoStatus = '未拉取到数据，请检查代码和市场。';
        });
        return;
      }

      final trend = _detectTrend(klines);
      final price = stock.price > 0 ? stock.price : _currentPrice;
      setState(() {
        _nameController.text = stock.name.isEmpty ? code : stock.name;
        _currentPriceController.text =
            price > 0 ? price.toStringAsFixed(2) : _currentPriceController.text;
        _pePercentileController.text =
            _estimatePePercentile(stock.pe).toStringAsFixed(0);
        _pbPercentileController.text =
            _estimatePbPercentile(stock.pb).toStringAsFixed(0);
        _buyTriggerController.text = price > 0
            ? (price * 0.92).toStringAsFixed(2)
            : _buyTriggerController.text;
        _harvestTriggerController.text = price > 0
            ? (price * 1.15).toStringAsFixed(2)
            : _harvestTriggerController.text;
        _isSt = stock.name.toUpperCase().contains('ST');
        _delistRisk = stock.name.contains('退');
        if (riskData.pledgeRatio != null) {
          _pledgeRatioController.text =
              riskData.pledgeRatio!.toStringAsFixed(2);
        }
        if (riskData.debtRatio != null) {
          _debtRatioController.text = riskData.debtRatio!.toStringAsFixed(2);
        }
        if (riskData.goodwillRatio != null) {
          _goodwillRatioController.text =
              riskData.goodwillRatio!.toStringAsFixed(2);
        }
        if (riskData.cashflowMargin != null) {
          _cashflowMarginController.text =
              riskData.cashflowMargin!.toStringAsFixed(2);
        }
        if (riskData.dividendYield != null) {
          _dividendYieldController.text =
              riskData.dividendYield!.toStringAsFixed(2);
        }
        if (riskData.dividendYears != null) {
          _dividendYearsController.text = riskData.dividendYears!.toString();
        }
        if (riskData.dividendStability != null) {
          _dividendStability = riskData.dividendStability!;
        }
        _industryCycle = trend;
        _isAutoLoading = false;
        final deep = riskData.sourceNotes.isEmpty
            ? '深度财务/质押/分红数据未取到，相关项仍需人工核验。'
            : riskData.sourceNotes.join('，');
        _autoStatus = '已自动填充：名称、现价、PE/PB估值分位、ST状态、趋势和触发价。$deep';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAutoLoading = false;
        _autoStatus = '自动拉取失败，请稍后重试或手工录入。';
      });
    }
  }

  int _estimatePePercentile(double pe) {
    if (pe <= 0) return 50;
    if (pe <= 10) return 15;
    if (pe <= 15) return 25;
    if (pe <= 25) return 45;
    if (pe <= 40) return 70;
    return 90;
  }

  int _estimatePbPercentile(double pb) {
    if (pb <= 0) return 50;
    if (pb <= 1) return 20;
    if (pb <= 1.8) return 35;
    if (pb <= 3) return 55;
    if (pb <= 5) return 75;
    return 90;
  }

  String _detectTrend(List<Map<String, dynamic>> klines) {
    if (klines.length < 60) return 'neutral';
    final recent = ((klines.last['close'] ?? 0.0) as num).toDouble();
    final mid =
        ((klines[klines.length - 30]['close'] ?? 0.0) as num).toDouble();
    final far =
        ((klines[klines.length - 60]['close'] ?? 0.0) as num).toDouble();
    if (recent <= 0 || mid <= 0 || far <= 0) return 'neutral';
    final change30 = (recent - mid) / mid;
    final change60 = (recent - far) / far;
    if (change30 > 0.08 && change60 > 0.12) return 'up';
    if (change30 < -0.08 && change60 < -0.12) return 'down';
    return 'neutral';
  }

  double get _pePercentile =>
      double.tryParse(_pePercentileController.text) ?? 0;
  double get _pbPercentile =>
      double.tryParse(_pbPercentileController.text) ?? 0;
  double get _pledgeRatio => double.tryParse(_pledgeRatioController.text) ?? 0;
  double get _debtRatio => double.tryParse(_debtRatioController.text) ?? 0;
  double get _goodwillRatio =>
      double.tryParse(_goodwillRatioController.text) ?? 0;
  double get _cashflowMargin =>
      double.tryParse(_cashflowMarginController.text) ?? 0;
  double get _dividendYield =>
      double.tryParse(_dividendYieldController.text) ?? 0;
  int get _dividendYears => int.tryParse(_dividendYearsController.text) ?? 0;
  double get _currentPrice =>
      double.tryParse(_currentPriceController.text) ?? 0;
  double get _buyTrigger => double.tryParse(_buyTriggerController.text) ?? 0;
  double get _harvestTrigger =>
      double.tryParse(_harvestTriggerController.text) ?? 0;

  _ScreeningResult get _result {
    final hardBlocks = <String>[];
    final warnings = <String>[];
    final strengths = <String>[];
    var score = 100;

    if (_isSt) hardBlocks.add('ST/*ST 标的禁止播种');
    if (_delistRisk) hardBlocks.add('存在退市风险，禁止播种');
    if (_violationGuarantee) hardBlocks.add('存在违规担保风险，禁止播种');
    if (_financialFraudRisk) hardBlocks.add('存在财务造假风险，禁止播种');
    if (_cashflowMargin < 0) hardBlocks.add('经营现金流为负，禁止播种');
    if (_pledgeRatio >= 50) hardBlocks.add('质押率超过 50%，禁止播种');

    if (_pledgeRatio >= 30) {
      score -= 18;
      warnings.add('质押率偏高，需降低仓位上限');
    }
    if (_debtRatio >= 70) {
      score -= 18;
      warnings.add('资产负债率偏高');
    } else if (_debtRatio <= 45) {
      score += 5;
      strengths.add('负债率相对可控');
    }
    if (_goodwillRatio >= 30) {
      score -= 15;
      warnings.add('商誉占比偏高，需防减值风险');
    }
    if (_cashflowMargin < 5) {
      score -= 15;
      warnings.add('经营现金流质量偏弱');
    } else {
      score += 8;
      strengths.add('现金流质量较好');
    }

    if (_pePercentile <= 30) {
      score += 10;
      strengths.add('PE 百分位处于低位区');
    } else if (_pePercentile >= 80) {
      score -= 20;
      warnings.add('PE 百分位过高，播种性价比下降');
    }
    if (_pbPercentile <= 30) {
      score += 8;
      strengths.add('PB 百分位处于低位区');
    } else if (_pbPercentile >= 80) {
      score -= 15;
      warnings.add('PB 百分位过高');
    }

    if (_dividendYield >= 3 && _dividendYears >= 5) {
      score += 15;
      strengths.add('股息率和分红连续性较好');
    } else if (_dividendYield < 1 || _dividendYears == 0) {
      score -= 12;
      warnings.add('分红灌溉能力不足');
    }

    if (_dividendStability == 'unstable') {
      score -= 12;
      warnings.add('分红不稳定');
    } else if (_dividendStability == 'stable') {
      score += 8;
      strengths.add('分红稳定性较高');
    }

    if (_industryCycle == 'up') {
      score += 8;
      strengths.add('行业周期向上');
    } else if (_industryCycle == 'down') {
      score -= 12;
      warnings.add('行业周期向下');
    }

    score = score.clamp(0, 100);

    final priceAlerts = <String>[];
    if (_currentPrice > 0 && _buyTrigger > 0 && _currentPrice <= _buyTrigger) {
      priceAlerts.add('播种提醒：当前价已触及或低于播种触发线');
    }
    if (_currentPrice > 0 &&
        _harvestTrigger > 0 &&
        _currentPrice >= _harvestTrigger) {
      priceAlerts.add('收割提醒：当前价已触及或高于回收触发线');
    }
    if (priceAlerts.isEmpty) {
      priceAlerts.add('未触发价格提醒，继续观察计划价位');
    }

    if (hardBlocks.isNotEmpty) {
      return _ScreeningResult(
        score: 0,
        level: '禁止播种',
        color: AppTheme.riskRed,
        hardBlocks: hardBlocks,
        warnings: warnings,
        strengths: strengths,
        priceAlerts: priceAlerts,
      );
    }

    if (score >= 85) {
      return _ScreeningResult(
        score: score,
        level: '适合播种',
        color: AppTheme.primaryGreen,
        hardBlocks: hardBlocks,
        warnings: warnings,
        strengths: strengths,
        priceAlerts: priceAlerts,
      );
    }
    if (score >= 70) {
      return _ScreeningResult(
        score: score,
        level: '可小额播种',
        color: AppTheme.accentGold,
        hardBlocks: hardBlocks,
        warnings: warnings,
        strengths: strengths,
        priceAlerts: priceAlerts,
      );
    }
    if (score >= 50) {
      return _ScreeningResult(
        score: score,
        level: '谨慎观察',
        color: AppTheme.accent,
        hardBlocks: hardBlocks,
        warnings: warnings,
        strengths: strengths,
        priceAlerts: priceAlerts,
      );
    }
    return _ScreeningResult(
      score: score,
      level: '暂不播种',
      color: AppTheme.riskRed,
      hardBlocks: hardBlocks,
      warnings: warnings,
      strengths: strengths,
      priceAlerts: priceAlerts,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('排雷')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          _AutoScreenCard(
            codeController: _codeController,
            nameController: _nameController,
            market: _market,
            isLoading: _isAutoLoading,
            status: _autoStatus,
            onChanged: () => setState(() {}),
            onMarketChanged: (market) => setState(() => _market = market),
            onFetch: _autoScreen,
          ),
          const SizedBox(height: 16),
          _ResultCard(result: result, name: _nameController.text),
          const SizedBox(height: 16),
          _BasicInfoCard(
            pePercentileController: _pePercentileController,
            pbPercentileController: _pbPercentileController,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          _HardFilterCard(
            isSt: _isSt,
            delistRisk: _delistRisk,
            violationGuarantee: _violationGuarantee,
            financialFraudRisk: _financialFraudRisk,
            onStChanged: (v) => setState(() => _isSt = v),
            onDelistChanged: (v) => setState(() => _delistRisk = v),
            onGuaranteeChanged: (v) => setState(() => _violationGuarantee = v),
            onFraudChanged: (v) => setState(() => _financialFraudRisk = v),
          ),
          const SizedBox(height: 12),
          _FinancialQualityCard(
            pledgeRatioController: _pledgeRatioController,
            debtRatioController: _debtRatioController,
            goodwillRatioController: _goodwillRatioController,
            cashflowMarginController: _cashflowMarginController,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          _DividendCard(
            dividendYieldController: _dividendYieldController,
            dividendYearsController: _dividendYearsController,
            stability: _dividendStability,
            onStabilityChanged: (v) => setState(() => _dividendStability = v),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          _CycleCard(
            cycle: _industryCycle,
            onChanged: (v) => setState(() => _industryCycle = v),
          ),
          const SizedBox(height: 12),
          _AlertCard(
            currentPriceController: _currentPriceController,
            buyTriggerController: _buyTriggerController,
            harvestTriggerController: _harvestTriggerController,
            alerts: result.priceAlerts,
            onChanged: () => setState(() {}),
          ),
        ],
      ),
    );
  }
}

class _AutoScreenCard extends StatefulWidget {
  final TextEditingController codeController;
  final TextEditingController nameController;
  final String market;
  final bool isLoading;
  final String status;
  final VoidCallback onChanged;
  final ValueChanged<String> onMarketChanged;
  final VoidCallback onFetch;

  const _AutoScreenCard({
    required this.codeController,
    required this.nameController,
    required this.market,
    required this.isLoading,
    required this.status,
    required this.onChanged,
    required this.onMarketChanged,
    required this.onFetch,
  });

  @override
  State<_AutoScreenCard> createState() => _AutoScreenCardState();
}

class _AutoScreenCardState extends State<_AutoScreenCard> {
  List<Stock> _suggestions = [];
  bool _searching = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  bool get _isCodeInput =>
      RegExp(r'^\d+$').hasMatch(widget.codeController.text.trim());

  Future<void> _onCodeChanged(String value) async {
    widget.onChanged();
    _removeOverlay();
    final trimmed = value.trim();
    if (trimmed.isEmpty || _isCodeInput) {
      setState(() => _suggestions = []);
      return;
    }
    if (trimmed.length < 1) return;

    setState(() => _searching = true);
    final results = await StockApiService().searchByName(trimmed);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _searching = false;
    });
    if (results.isNotEmpty) _showOverlay();
  }

  void _selectSuggestion(Stock stock) {
    widget.codeController.text = stock.code;
    widget.nameController.text = stock.name;
    widget.onMarketChanged(stock.market);
    widget.onChanged();
    setState(() => _suggestions = []);
    _removeOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        width: _getFieldWidth(),
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 52),
          child: _SuggestionDropdown(
            suggestions: _suggestions,
            onSelect: _selectSuggestion,
            onDismiss: _removeOverlay,
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  double _getFieldWidth() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return 200;
    // approximate: half width minus padding and gap
    return (box.size.width - 32 - 12) / 2;
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '自动排雷数据源',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _TextFieldLine(
            label: '标的名称',
            controller: widget.nameController,
            hint: '例：润和软件 / 沪深300ETF',
            onChanged: widget.onChanged,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '股票代码 / 名称',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    CompositedTransformTarget(
                      link: _layerLink,
                      child: TextField(
                        controller: widget.codeController,
                        keyboardType: TextInputType.text,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: '代码或名称',
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5),
                                  ),
                                )
                              : null,
                        ),
                        onChanged: _onCodeChanged,
                        onTap: () {
                          if (_suggestions.isNotEmpty) _showOverlay();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '市场',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ThreeChoice(
                      labels: const ['沪市', '深市'],
                      values: const ['SH', 'SZ'],
                      selected: widget.market,
                      onChanged: widget.onMarketChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: widget.isLoading ? null : widget.onFetch,
              icon: widget.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_outlined, size: 18),
              label: Text(widget.isLoading ? '自动排雷中' : '自动拉取并排雷'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.status,
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

class _SuggestionDropdown extends StatelessWidget {
  final List<Stock> suggestions;
  final ValueChanged<Stock> onSelect;
  final VoidCallback onDismiss;

  const _SuggestionDropdown({
    required this.suggestions,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: AppTheme.borderColor,
          ),
          itemBuilder: (ctx, i) {
            final s = suggestions[i];
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelect(s),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.code,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        s.market,
                        style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final _ScreeningResult result;
  final String name;

  const _ResultCard({required this.result, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            result.color.withValues(alpha: 0.18),
            AppTheme.bgCard,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: result.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.trim().isEmpty ? '观察标的' : name.trim(),
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  result.level,
                  style: TextStyle(
                    color: result.color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${result.score}分',
                style: TextStyle(
                  color: result.color,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MessageList(
            title: '硬性过滤',
            items: result.hardBlocks.isEmpty ? ['未触发硬性排除项'] : result.hardBlocks,
            color: result.hardBlocks.isEmpty
                ? AppTheme.primaryGreen
                : AppTheme.riskRed,
          ),
          const SizedBox(height: 8),
          _MessageList(
            title: '优势',
            items: result.strengths.isEmpty ? ['暂无明显加分项'] : result.strengths,
            color: AppTheme.primaryGreen,
          ),
          const SizedBox(height: 8),
          _MessageList(
            title: '风险',
            items: result.warnings.isEmpty ? ['暂无明显扣分项'] : result.warnings,
            color: AppTheme.accentGold,
          ),
        ],
      ),
    );
  }
}

class _BasicInfoCard extends StatelessWidget {
  final TextEditingController pePercentileController;
  final TextEditingController pbPercentileController;
  final VoidCallback onChanged;

  const _BasicInfoCard({
    required this.pePercentileController,
    required this.pbPercentileController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: '估值百分位',
      children: [
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: 'PE百分位',
                suffix: '%',
                controller: pePercentileController,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                label: 'PB百分位',
                suffix: '%',
                controller: pbPercentileController,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HardFilterCard extends StatelessWidget {
  final bool isSt;
  final bool delistRisk;
  final bool violationGuarantee;
  final bool financialFraudRisk;
  final ValueChanged<bool> onStChanged;
  final ValueChanged<bool> onDelistChanged;
  final ValueChanged<bool> onGuaranteeChanged;
  final ValueChanged<bool> onFraudChanged;

  const _HardFilterCard({
    required this.isSt,
    required this.delistRisk,
    required this.violationGuarantee,
    required this.financialFraudRisk,
    required this.onStChanged,
    required this.onDelistChanged,
    required this.onGuaranteeChanged,
    required this.onFraudChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: '硬性过滤',
      children: [
        _SwitchLine(label: 'ST / *ST', value: isSt, onChanged: onStChanged),
        _SwitchLine(
            label: '退市风险', value: delistRisk, onChanged: onDelistChanged),
        _SwitchLine(
            label: '违规担保',
            value: violationGuarantee,
            onChanged: onGuaranteeChanged),
        _SwitchLine(
            label: '财务造假风险',
            value: financialFraudRisk,
            onChanged: onFraudChanged),
      ],
    );
  }
}

class _FinancialQualityCard extends StatelessWidget {
  final TextEditingController pledgeRatioController;
  final TextEditingController debtRatioController;
  final TextEditingController goodwillRatioController;
  final TextEditingController cashflowMarginController;
  final VoidCallback onChanged;

  const _FinancialQualityCard({
    required this.pledgeRatioController,
    required this.debtRatioController,
    required this.goodwillRatioController,
    required this.cashflowMarginController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: '财务质量',
      children: [
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: '质押率',
                suffix: '%',
                controller: pledgeRatioController,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                label: '负债率',
                suffix: '%',
                controller: debtRatioController,
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
                label: '商誉占比',
                suffix: '%',
                controller: goodwillRatioController,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                label: '现金流利润比',
                suffix: '%',
                controller: cashflowMarginController,
                allowNegative: true,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DividendCard extends StatelessWidget {
  final TextEditingController dividendYieldController;
  final TextEditingController dividendYearsController;
  final String stability;
  final ValueChanged<String> onStabilityChanged;
  final VoidCallback onChanged;

  const _DividendCard({
    required this.dividendYieldController,
    required this.dividendYearsController,
    required this.stability,
    required this.onStabilityChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: '分红灌溉',
      children: [
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: '股息率',
                suffix: '%',
                controller: dividendYieldController,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                label: '连续分红',
                suffix: '年',
                controller: dividendYearsController,
                decimals: 0,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ThreeChoice(
          labels: const ['稳定', '一般', '不稳'],
          values: const ['stable', 'normal', 'unstable'],
          selected: stability,
          onChanged: onStabilityChanged,
        ),
      ],
    );
  }
}

class _CycleCard extends StatelessWidget {
  final String cycle;
  final ValueChanged<String> onChanged;

  const _CycleCard({required this.cycle, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: '行业周期',
      children: [
        _ThreeChoice(
          labels: const ['向上', '中性', '向下'],
          values: const ['up', 'neutral', 'down'],
          selected: cycle,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final TextEditingController currentPriceController;
  final TextEditingController buyTriggerController;
  final TextEditingController harvestTriggerController;
  final List<String> alerts;
  final VoidCallback onChanged;

  const _AlertCard({
    required this.currentPriceController,
    required this.buyTriggerController,
    required this.harvestTriggerController,
    required this.alerts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: '本地触发提醒',
      children: [
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: '当前价',
                suffix: '元',
                controller: currentPriceController,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                label: '播种线',
                suffix: '元',
                controller: buyTriggerController,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _NumberField(
          label: '收割线',
          suffix: '元',
          controller: harvestTriggerController,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        _MessageList(title: '触发状态', items: alerts, color: AppTheme.accent),
      ],
    );
  }
}

class _InputCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InputCard({required this.title, required this.children});

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
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _TextFieldLine extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final VoidCallback onChanged;

  const _TextFieldLine({
    required this.label,
    required this.controller,
    this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final int decimals;
  final bool allowNegative;
  final VoidCallback onChanged;

  const _NumberField({
    required this.label,
    required this.suffix,
    required this.controller,
    this.decimals = 2,
    this.allowNegative = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pattern = allowNegative
        ? RegExp('^-?\\d*\\.?\\d{0,$decimals}')
        : RegExp('^\\d*\\.?\\d{0,$decimals}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            decimals == 0
                ? FilteringTextInputFormatter.allow(
                    allowNegative ? RegExp(r'^-?\d*') : RegExp(r'^\d*'),
                  )
                : FilteringTextInputFormatter.allow(pattern),
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

class _SwitchLine extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchLine({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppTheme.riskRed,
      title: Text(
        label,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _ThreeChoice extends StatelessWidget {
  final List<String> labels;
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;

  const _ThreeChoice({
    required this.labels,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (index) {
        final isSelected = values[index] == selected;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8),
            child: GestureDetector(
              onTap: () => onChanged(values[index]),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: 0.15)
                      : AppTheme.bgCardLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppTheme.accent : AppTheme.borderColor,
                  ),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color:
                        isSelected ? AppTheme.accent : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _MessageList extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color color;

  const _MessageList({
    required this.title,
    required this.items,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.circle, color: color, size: 6),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScreeningResult {
  final int score;
  final String level;
  final Color color;
  final List<String> hardBlocks;
  final List<String> warnings;
  final List<String> strengths;
  final List<String> priceAlerts;

  const _ScreeningResult({
    required this.score,
    required this.level,
    required this.color,
    required this.hardBlocks,
    required this.warnings,
    required this.strengths,
    required this.priceAlerts,
  });
}
