import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stock.dart';
import '../models/stock_context.dart';
import '../services/stock_api_service.dart';
import '../services/strategy_advisor_service.dart';
import '../theme/app_theme.dart';
import 'seed_plan_screen.dart';

// 【用户手动录入】标的名称、代码、市场、硬性一票否决开关、播种触发价、最高加仓价、目标收割价
// 【自动拉取只读】当前价、PE/PB百分位、质押率、负债率、商誉占比、现金流利润比、股息率、分红年数、分红稳定性、K线趋势
class SeedScreeningScreen extends StatefulWidget {
  final StockContext? stockContext;

  const SeedScreeningScreen({super.key, this.stockContext});

  @override
  State<SeedScreeningScreen> createState() => _SeedScreeningScreenState();
}

class _SeedScreeningScreenState extends State<SeedScreeningScreen> {
  final _codeController         = TextEditingController();
  final _nameController         = TextEditingController();
  final _seedPriceController    = TextEditingController();
  final _maxAddPriceController  = TextEditingController();
  final _harvestPriceController = TextEditingController();
  String _market = 'SH';
  bool _isSt = false, _delistRisk = false, _violationGuarantee = false, _financialFraudRisk = false;

  double? _autoPrice;
  DateTime? _autoDataTime;
  int?    _autoPePct, _autoPbPct;
  bool    _autoPeEst = false, _autoPbEst = false;
  double? _autoPledge, _autoDebt, _autoGoodwill, _autoCashflow;
  double? _autoDivYield;
  int?    _autoDivYears;
  String? _autoDivStability, _autoTrend, _autoTrendTip;
  bool    _isFund = false;

  StrategyAdvice? _advice;

  bool   _loading = false;
  String _status  = '输入A股代码/基金代码或名称后，点击「自动拉取并排雷」，系统将自动填充行情、估值、财务、分红数据。';

  @override
  void initState() {
    super.initState();
    final ctx = widget.stockContext;
    if (ctx != null) {
      if (ctx.code != null) _codeController.text = ctx.code!;
      if (ctx.name != null) _nameController.text = ctx.name!;
      if (ctx.market != null) _market = ctx.market!;
      if (ctx.currentPrice != null && ctx.currentPrice! > 0) {
        final p = ctx.currentPrice!;
        _seedPriceController.text = (p * 0.92).toStringAsFixed(3);
        _harvestPriceController.text = (p * 1.15).toStringAsFixed(3);
        _maxAddPriceController.text = (p * 0.70).toStringAsFixed(3);
        _autoPrice = p;
      }
      _status = '已从持仓载入「${ctx.name ?? ctx.code ?? ''}」，可直接点击「自动拉取并排雷」更新数据。';
    }
  }

  @override
  void dispose() {
    _codeController.dispose(); _nameController.dispose();
    _seedPriceController.dispose(); _maxAddPriceController.dispose();
    _harvestPriceController.dispose();
    super.dispose();
  }

  Future<void> _autoFetch() async {
    String input = _codeController.text.trim();
    if (input.isEmpty) { setState(() => _status = '请先输入股票代码或名称。'); return; }
    setState(() { _loading = true; _status = '正在解析标的...'; });
    try {
      final svc = StockApiService();
      if (!RegExp(r'^\d+$').hasMatch(input)) {
        setState(() => _status = '正在搜索「$input」...');
        final hits = await svc.searchByName(input);
        if (!mounted) return;
        if (hits.isEmpty) {
          setState(() { _loading = false; _status = '未找到「$input」，请确认名称或改用六位代码。'; });
          return;
        }
        final m = hits.first;
        input = m.code;
        _codeController.text = m.code; _nameController.text = m.name; _market = m.market;
        _isFund = m.isFund;
        setState(() => _status = '已匹配「${m.name}」(${m.code})，正在拉取数据...');
      } else {
        // 直接输入代码时，根据代码前缀判断是否为基金，并推断市场
        _isFund = StockApiService().isFundCode(input);
        if (!_isFund) {
          _market = StockApiService().inferMarket(input);
        }
      }
      final code = input;
      setState(() => _status = '正在拉取行情、K线、${_isFund ? "分红收益" : "财务、分红"}数据...');
      final fetched = await Future.wait([
        svc.fetchStockQuote(code, _market),
        svc.fetchKlineDaily(code, _market, limit: 120),
        svc.fetchAutoRiskData(code, _market),
      ]);
      if (!mounted) return;
      final stock  = fetched[0] as Stock?;
      final klines = fetched[1] as List<Map<String, dynamic>>;
      final risk   = fetched[2] as AutoRiskData;
      if (stock == null) {
        setState(() { _loading = false; _status = '行情未取到，请检查代码和市场是否正确。'; });
        return;
      }
      final isFundDetected = risk.isFund || stock.isFund;
      // 基金不拉 PE/PB 百分位，直接跳过该步骤节省时间
      final pct = isFundDetected
          ? (pePercentile: null as int?, pbPercentile: null as int?)
          : await svc.fetchValuationPercentile(code, _market);
      if (!mounted) return;
      final trend = _detectTrend(klines);
      final price = stock.price > 0 ? stock.price : 0.0;
      final nameU = stock.name.toUpperCase();
      final autoSt = nameU.contains('ST');
      final autoDel = stock.name.contains('退') || nameU.contains('*ST') || nameU.startsWith('PT');
      // 基金无 PE/PB，不做估算回退
      final pe = isFundDetected ? null : (pct.pePercentile ?? _fbPe(stock.pe));
      final pb = isFundDetected ? null : (pct.pbPercentile ?? _fbPb(stock.pb));
      final notes = <String>[];
      if (!isFundDetected) {
        notes.add(pct.pePercentile == null ? 'PE百分位为估算值' : 'PE百分位取自历史数据');
        notes.add(pct.pbPercentile == null ? 'PB百分位为估算值' : 'PB百分位取自历史数据');
      } else {
        notes.add('基金无PE/PB历史百分位，估值模块已隐藏');
      }
      if (risk.sourceNotes.isNotEmpty) notes.addAll(risk.sourceNotes);
      else notes.add('${isFundDetected ? "基金分红" : "财务/质押/分红"}数据未取到，相关项仍需人工核验');
      if (autoSt)  notes.add('检测到ST状态，已自动标记');
      if (autoDel) notes.add('检测到退市风险，已自动标记');
      final advice = StrategyAdvisorService.advise(
        klines: klines,
        pePercentile: pe?.toDouble(),
        pbPercentile: pb?.toDouble(),
        isFund: isFundDetected,
      );
      setState(() {
        // 名称优先用行情接口返回值，但若为空（如新浪备用接口不返回名称），
        // 保留搜索结果或用户已填写的名称，避免覆盖为空
        if (stock.name.isNotEmpty) _nameController.text = stock.name;
        _isFund = isFundDetected;
        _autoPrice = price > 0 ? price : null;
        // 优先用数据源自带的行情时间；缺失时用本地拉取时间兜底
        _autoDataTime = stock.dataTime ?? DateTime.now();
        _autoPePct = pe; _autoPbPct = pb;
        _autoPeEst = !isFundDetected && pct.pePercentile == null;
        _autoPbEst = !isFundDetected && pct.pbPercentile == null;
        _autoPledge = risk.pledgeRatio; _autoDebt = risk.debtRatio;
        _autoGoodwill = risk.goodwillRatio; _autoCashflow = risk.cashflowMargin;
        _autoDivYield = risk.dividendYield; _autoDivYears = risk.dividendYears;
        _autoDivStability = risk.dividendStability;
        _autoTrend = trend; _autoTrendTip = _trendTip(trend, klines);
        _advice = advice;
        if (autoSt)  _isSt       = true;
        if (autoDel) _delistRisk = true;
        if (_seedPriceController.text.isEmpty && price > 0)
          _seedPriceController.text = (price * 0.92).toStringAsFixed(3);
        if (_harvestPriceController.text.isEmpty && price > 0)
          _harvestPriceController.text = (price * 1.20).toStringAsFixed(3);
        _loading = false;
        _status = '自动填充完成。${notes.join('；')}。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _status = '拉取失败：$e'; });
    }
  }

  int _fbPe(double v) { if (v<=0) return 50; if (v<=10) return 15; if (v<=15) return 25; if (v<=25) return 45; if (v<=40) return 70; return 90; }
  int _fbPb(double v) { if (v<=0) return 50; if (v<=1) return 20; if (v<=1.8) return 35; if (v<=3) return 55; if (v<=5) return 75; return 90; }

  /// 格式化行情数据时间：完整显示 年-月-日 时:分。
  String _fmtDataTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  String _detectTrend(List<Map<String, dynamic>> k) {
    if (k.length < 60) return 'neutral';
    final r = ((k.last['close'] ?? 0.0) as num).toDouble();
    final m = ((k[k.length-30]['close'] ?? 0.0) as num).toDouble();
    final f = ((k[k.length-60]['close'] ?? 0.0) as num).toDouble();
    if (r<=0||m<=0||f<=0) return 'neutral';
    if ((r-m)/m>0.08&&(r-f)/f>0.12) return 'up';
    if ((r-m)/m<-0.08&&(r-f)/f<-0.12) return 'down';
    return 'neutral';
  }

  String _trendTip(String t, List<Map<String, dynamic>> k) {
    if (k.length < 60) return '历史K线不足，无法判断趋势';
    if (t=='up')   return '近60日价格持续上行，注意估值是否偏贵，控制仓位';
    if (t=='down') return '近60日价格持续下行，判断是否进入播种区间';
    return '近60日价格震荡，趋势中性，关注估值百分位';
  }

  _ScreeningResult get _result {
    final hard=<String>[], warn=<String>[], str=<String>[];
    var s = 100;
    if (_isSt)               hard.add('ST/*ST 标的，禁止播种');
    if (_delistRisk)         hard.add('存在退市风险，禁止播种');
    if (_violationGuarantee) hard.add('存在违规担保风险，禁止播种');
    if (_financialFraudRisk) hard.add('存在财务造假风险，禁止播种');

    // 股票特有指标，基金跳过
    if (!_isFund) {
      if (_autoCashflow!=null&&_autoCashflow!<0) hard.add('经营现金流为负，禁止播种');
      if (_autoPledge!=null&&_autoPledge!>=50)   hard.add('大股东质押率≥50%，禁止播种');
      if (_autoPledge!=null) {
        if (_autoPledge!>=30) { s-=18; warn.add('大股东质押率偏高（${_autoPledge!.toStringAsFixed(1)}%），需降低仓位上限'); }
        else if (_autoPledge!<10) { s+=5; str.add('大股东质押率极低（${_autoPledge!.toStringAsFixed(1)}%）'); }
      }
      if (_autoDebt!=null) {
        if (_autoDebt!>=70) { s-=18; warn.add('资产负债率偏高（${_autoDebt!.toStringAsFixed(1)}%）'); }
        else if (_autoDebt!<=45) { s+=5; str.add('资产负债率健康（${_autoDebt!.toStringAsFixed(1)}%）'); }
      }
      if (_autoGoodwill!=null) {
        if (_autoGoodwill!>=30) { s-=15; warn.add('商誉/净资产偏高（${_autoGoodwill!.toStringAsFixed(1)}%），防减值风险'); }
        else if (_autoGoodwill!<5) { s+=3; str.add('商誉占比极低（${_autoGoodwill!.toStringAsFixed(1)}%）'); }
      }
      if (_autoCashflow!=null) {
        if (_autoCashflow!<5) { s-=15; warn.add('经营现金流/净利润偏低（${_autoCashflow!.toStringAsFixed(1)}%），盈利质量存疑'); }
        else { s+=8; str.add('经营现金流质量良好（${_autoCashflow!.toStringAsFixed(1)}%）'); }
      }
      if (_autoPePct!=null) {
        if (_autoPePct!<=30) { s+=10; str.add('PE处于历史低位（${_autoPePct}分位${_autoPeEst?"，估算":""}）'); }
        else if (_autoPePct!>=80) { s-=20; warn.add('PE处于历史高位（${_autoPePct}分位${_autoPeEst?"，估算":""}），播种性价比下降'); }
      }
      if (_autoPbPct!=null) {
        if (_autoPbPct!<=30) { s+=8; str.add('PB处于历史低位（${_autoPbPct}分位${_autoPbEst?"，估算":""}）'); }
        else if (_autoPbPct!>=80) { s-=15; warn.add('PB处于历史高位（${_autoPbPct}分位${_autoPbEst?"，估算":""}）'); }
      }
    } else {
      // 基金专项：用 K 线趋势替代估值加分/扣分主要来源
      str.add('基金（ETF/LOF）无质押/负债/商誉风险，财务安全项不适用');
    }

    if (_autoDivYield!=null&&_autoDivYield!>=3&&(_autoDivYears??0)>=5) {
      s+=15; str.add('${_isFund?"基金收益率":"股息率"}高（${_autoDivYield!.toStringAsFixed(2)}%）且连续分红${_autoDivYears}${_isFund?"次":"年"}，灌溉能力强');
    } else if (_autoDivYield==null||_autoDivYield!<1) {
      s-=10; warn.add('无分红或${_isFund?"收益率":"股息率"}极低，灌溉能力不足');
    }
    if (_autoDivStability=='unstable') { s-=12; warn.add('历史分红不稳定'); }
    else if (_autoDivStability=='stable') { s+=8; str.add('历史分红稳定'); }
    if (_autoTrend=='up')   { s+=5;  str.add('近期K线趋势向上'); }
    if (_autoTrend=='down') { s-=10; warn.add('近期K线趋势向下，注意是否进入播种区间'); }
    s = s.clamp(0, 100);

    final alerts=<String>[];
    final cur=_autoPrice??0.0;
    final seed=double.tryParse(_seedPriceController.text)??0.0;
    final maxA=double.tryParse(_maxAddPriceController.text)??0.0;
    final harv=double.tryParse(_harvestPriceController.text)??0.0;
    if (cur>0&&seed>0&&cur<=seed) alerts.add('当前价（${cur.toStringAsFixed(3)}）≤ 播种触发线（${seed.toStringAsFixed(3)}），可按计划播种');
    if (cur>0&&maxA>0&&cur>=maxA) alerts.add('当前价（${cur.toStringAsFixed(3)}）≥ 最高加仓线（${maxA.toStringAsFixed(3)}），禁止继续加仓');
    if (cur>0&&harv>0&&cur>=harv) alerts.add('当前价（${cur.toStringAsFixed(3)}）≥ 目标收割价（${harv.toStringAsFixed(3)}），可考虑分批收割');
    if (alerts.isEmpty) alerts.add('暂未触发价格提醒，继续观察计划价位');

    if (hard.isNotEmpty) return _ScreeningResult(score:0,level:'禁止播种',color:AppTheme.riskRed,hardBlocks:hard,warnings:warn,strengths:str,priceAlerts:alerts);
    if (s>=85) return _ScreeningResult(score:s,level:'适合播种',  color:AppTheme.primaryGreen,hardBlocks:hard,warnings:warn,strengths:str,priceAlerts:alerts);
    if (s>=70) return _ScreeningResult(score:s,level:'可小额播种',color:AppTheme.accentGold,  hardBlocks:hard,warnings:warn,strengths:str,priceAlerts:alerts);
    if (s>=50) return _ScreeningResult(score:s,level:'谨慎观察',  color:AppTheme.accent,      hardBlocks:hard,warnings:warn,strengths:str,priceAlerts:alerts);
    return _ScreeningResult(score:s,level:'暂不播种',color:AppTheme.riskRed,hardBlocks:hard,warnings:warn,strengths:str,priceAlerts:alerts);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('排雷')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          // ① 标的输入 + 自动拉取
          _AutoFetchCard(
            codeController: _codeController,
            nameController: _nameController,
            market: _market,
            isLoading: _loading,
            isFund: _isFund,
            status: _status,
            onChanged: () => setState(() {}),
            onMarketChanged: (v) => setState(() => _market = v),
            onFetch: _autoFetch,
          ),
          const SizedBox(height: 16),
          // ② 综合评分结果
          _ResultCard(result: result, name: _nameController.text),
          const SizedBox(height: 16),
          // ②.5 策略算法推荐（离线特征识别）
          if (_advice != null) ...[
            _StrategyAdviceCard(advice: _advice!, isFund: _isFund),
            const SizedBox(height: 16),
          ],
          // ③ 自动拉取区块标题
          Row(children: [
            _SectionLabel(label: '自动拉取数据', icon: Icons.cloud_done_outlined, color: AppTheme.accent),
            const Spacer(),
            if (_autoDataTime != null)
              Text('行情时间 ${_fmtDataTime(_autoDataTime!)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          // 基金显示行情+K线趋势，隐藏 PE/PB 百分位（基金无此指标）
          if (_isFund)
            _FundDataCard(price: _autoPrice, trend: _autoTrend, trendTip: _autoTrendTip)
          else
            _AutoDataCard(
              price: _autoPrice,
              pePct: _autoPePct, pbPct: _autoPbPct,
              peEst: _autoPeEst, pbEst: _autoPbEst,
              trend: _autoTrend, trendTip: _autoTrendTip,
            ),
          const SizedBox(height: 8),
          // 财务安全：仅股票显示，基金跳过
          if (!_isFund) ...[
            _FinancialAutoCard(
              pledge: _autoPledge, debt: _autoDebt,
              goodwill: _autoGoodwill, cashflow: _autoCashflow,
            ),
            const SizedBox(height: 8),
          ],
          // ⑤ 自动拉取：分红灌溉（基金显示收益率，标签文案有区别）
          _DividendAutoCard(
            yield_: _autoDivYield,
            years: _autoDivYears,
            stability: _autoDivStability,
            isFund: _isFund,
          ),
          const SizedBox(height: 16),
          // ⑥ 用户录入：硬性一票否决
          _SectionLabel(label: '用户录入字段', icon: Icons.edit_outlined, color: AppTheme.accentGold),
          const SizedBox(height: 8),
          _HardFilterCard(
            isSt: _isSt, delistRisk: _delistRisk,
            violationGuarantee: _violationGuarantee, financialFraudRisk: _financialFraudRisk,
            onStChanged: (v) => setState(() => _isSt = v),
            onDelistChanged: (v) => setState(() => _delistRisk = v),
            onGuaranteeChanged: (v) => setState(() => _violationGuarantee = v),
            onFraudChanged: (v) => setState(() => _financialFraudRisk = v),
          ),
          const SizedBox(height: 8),
          // ⑦ 用户录入：播种计划价
          _SeedPlanCard(
            seedPriceController: _seedPriceController,
            maxAddPriceController: _maxAddPriceController,
            harvestPriceController: _harvestPriceController,
            alerts: result.priceAlerts,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          // ⑧ 流程跳转：制定播种计划
          if (result.level != '禁止播种')
            _ProceedToSeedButton(
              result: result,
              onTap: () {
                final price = double.tryParse(_seedPriceController.text);
                final adv = _advice;
                final ctx = StockContext(
                  code: _codeController.text.trim().isEmpty
                      ? null
                      : _codeController.text.trim(),
                  name: _nameController.text.trim().isEmpty
                      ? null
                      : _nameController.text.trim(),
                  assetType: _isFund ? 'fund' : 'stock',
                  market: _market,
                  pePercentile: _autoPePct?.toDouble(),
                  pbPercentile: _autoPbPct?.toDouble(),
                  industryCycle: _autoTrend,
                  currentPrice: price ?? _autoPrice,
                  seedAlgo: adv?.seedAlgo.name,
                  weightModeKey: adv?.seedAlgo.weightModeKey,
                  harvestAlgo: adv?.harvestAlgo.name,
                  harvestModeKey: adv?.harvestAlgo.modeKey,
                  recommendSeedCount: adv?.seedCount,
                  recommendDropStep: adv?.dropStepPct,
                  recommendGridStep: adv?.gridStepPct,
                  recommendAtrMultiple: adv?.atrMultiple,
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SeedPlanScreen(stockContext: ctx),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── 排雷完成后跳转播种计划 ────────────────────────────────────────────────────
class _ProceedToSeedButton extends StatelessWidget {
  final _ScreeningResult result;
  final VoidCallback onTap;
  const _ProceedToSeedButton({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isGood = result.level == '适合播种';
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.grass_outlined, size: 18),
        label: Text(
          isGood ? '排雷通过 · 制定播种计划' : '查看播种计划（谨慎）',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isGood ? AppTheme.primaryGreen : AppTheme.accentGold,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ── 策略算法推荐卡 ────────────────────────────────────────────────────────────
class _StrategyAdviceCard extends StatelessWidget {
  final StrategyAdvice advice;
  final bool isFund;
  const _StrategyAdviceCard({required this.advice, required this.isFund});

  @override
  Widget build(BuildContext context) {
    final f = advice.features;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.16),
            AppTheme.primaryGreen.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 16, color: AppTheme.accent),
          const SizedBox(width: 6),
          const Text('智能策略推荐',
              style: TextStyle(color: AppTheme.accent, fontSize: 15, fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('离线特征识别',
                style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Text(advice.summary,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _FeatChip(
            label: '波动率 ATR%',
            value: f.atrPct != null ? '${(f.atrPct! * 100).toStringAsFixed(1)}%' : '—',
          )),
          Expanded(child: _FeatChip(
            label: '趋势强度 R²',
            value: f.hasEnoughData ? f.trendStrength.toStringAsFixed(2) : '—',
          )),
          Expanded(child: _FeatChip(
            label: isFund ? '价格分位' : '综合分位',
            value: f.hasEnoughData ? '${(f.pricePercentile * 100).round()}%' : '—',
          )),
          Expanded(child: _FeatChip(
            label: '距高点回撤',
            value: f.hasEnoughData ? '${(f.drawdown * 100).round()}%' : '—',
          )),
        ]),
        const SizedBox(height: 14),
        _AlgoRow(
          icon: Icons.grass_outlined,
          tag: '播种',
          algo: advice.seedAlgo.label,
          reason: advice.seedReason,
          color: AppTheme.primaryGreen,
        ),
        const SizedBox(height: 8),
        _AlgoRow(
          icon: Icons.content_cut,
          tag: '收割',
          algo: advice.harvestAlgo.label,
          reason: advice.harvestReason,
          color: AppTheme.accentGold,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.bgCardLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.tune, size: 13, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text(
              '推荐参数：批数 ${advice.seedCount} · 下跌间距 ${advice.dropStepPct}% · '
              '网格 ${advice.gridStepPct}% · ATR/吊灯 ${advice.atrMultiple}倍',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.35),
            )),
          ]),
        ),
        const SizedBox(height: 8),
        const Text('跳转「制定播种计划」后将自动带入以上推荐参数，可随时手动调整。',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.35)),
      ]),
    );
  }
}

class _FeatChip extends StatelessWidget {
  final String label;
  final String value;
  const _FeatChip({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _AlgoRow extends StatelessWidget {
  final IconData icon;
  final String tag;
  final String algo;
  final String reason;
  final Color color;
  const _AlgoRow({required this.icon, required this.tag, required this.algo, required this.reason, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5)),
        child: Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(tag, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(algo, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(reason, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.35)),
      ])),
    ]);
  }
}

// ── 区块标题 ──────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _SectionLabel({required this.label, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }
}

// ── 通用卡片容器 ──────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? borderColor;
  const _Card({required this.title, required this.children, this.borderColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? AppTheme.borderColor, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }
}

// ── ① 自动拉取卡 ──────────────────────────────────────────────────────────────
class _AutoFetchCard extends StatefulWidget {
  final TextEditingController codeController;
  final TextEditingController nameController;
  final String market;
  final bool isLoading;
  final bool isFund;
  final String status;
  final VoidCallback onChanged;
  final ValueChanged<String> onMarketChanged;
  final VoidCallback onFetch;
  const _AutoFetchCard({
    required this.codeController, required this.nameController,
    required this.market, required this.isLoading, required this.status,
    required this.onChanged, required this.onMarketChanged, required this.onFetch,
    this.isFund = false,
  });
  @override
  State<_AutoFetchCard> createState() => _AutoFetchCardState();
}

class _AutoFetchCardState extends State<_AutoFetchCard> {
  List<Stock> _sugg = [];
  bool _searching = false;
  OverlayEntry? _ov;
  final _link = LayerLink();
  int _searchSeq = 0;

  Future<void> _onCode(String v) async {
    widget.onChanged();
    _ov?.remove(); _ov = null;
    final t = v.trim();
    // 代码或名称都触发下拉搜索：东方财富 suggest 接口对两者均支持。
    if (t.isEmpty) { setState(() { _sugg = []; _searching = false; }); return; }
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    final r = await StockApiService().searchByName(t);
    if (!mounted || seq != _searchSeq) return;
    setState(() { _sugg = r; _searching = false; });
    if (r.isNotEmpty) _showOv();
  }

  void _select(Stock s) {
    widget.codeController.text = s.code;
    widget.nameController.text = s.name;
    widget.onMarketChanged(s.market);
    widget.onChanged();
    setState(() => _sugg = []);
    _ov?.remove(); _ov = null;
  }

  void _showOv() {
    _ov?.remove();
    final box = context.findRenderObject() as RenderBox?;
    // 输入框现为整行宽度（卡片内边距 16*2 = 32）
    final w = box != null ? (box.size.width - 32) : 320.0;
    _ov = OverlayEntry(builder: (_) => Positioned(
      width: w,
      child: CompositedTransformFollower(
        link: _link, showWhenUnlinked: false, offset: const Offset(0, 52),
        child: _SuggDrop(suggestions: _sugg, onSelect: _select, onDismiss: () { _ov?.remove(); _ov = null; }),
      ),
    ));
    Overlay.of(context).insert(_ov!);
  }

  @override
  void dispose() { _ov?.remove(); super.dispose(); }

  void _clearCode() {
    widget.codeController.clear();
    widget.onChanged();
    _ov?.remove(); _ov = null;
    setState(() => _sugg = []);
  }

  Widget? _buildCodeSuffix() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
      );
    }
    if (widget.codeController.text.isNotEmpty) {
      return IconButton(
        icon: const Icon(Icons.cancel, size: 18, color: AppTheme.textSecondary),
        splashRadius: 18,
        tooltip: '清除',
        onPressed: _clearCode,
      );
    }
    return null;
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('自动排雷数据源', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _FieldLabel('标的名称'),
        const SizedBox(height: 6),
        TextField(
          controller: widget.nameController,
          onChanged: (_) => widget.onChanged(),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(hintText: '例：贵州茅台'),
        ),
        const SizedBox(height: 12),
        _FieldLabel('股票代码 / 名称'),
        const SizedBox(height: 6),
        CompositedTransformTarget(
          link: _link,
          child: TextField(
            controller: widget.codeController,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '输入代码或名称，如 600519 / 贵州茅台',
              suffixIcon: _buildCodeSuffix(),
            ),
            onChanged: _onCode,
            onTap: () { if (_sugg.isNotEmpty) _showOv(); },
          ),
        ),
        const SizedBox(height: 12),
        _FieldLabel('市场'),
        const SizedBox(height: 6),
        widget.isFund
            ? Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.5)),
                ),
                child: Text('基金', style: TextStyle(
                  color: AppTheme.primaryGreen, fontSize: 13, fontWeight: FontWeight.w700,
                )),
              )
            : _TogglePair(
                labels: const ['沪市', '深市', '京市'],
                values: const ['SH', 'SZ', 'BJ'],
                selected: widget.market, onChanged: widget.onMarketChanged,
              ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity, height: 46,
          child: ElevatedButton.icon(
            onPressed: widget.isLoading ? null : widget.onFetch,
            icon: widget.isLoading
                ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2))
                : const Icon(Icons.cloud_sync_outlined, size: 18),
            label: Text(widget.isLoading ? '自动排雷中...' : '自动拉取并排雷'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(widget.status, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.35)),
      ]),
    );
  }
}

// ── 搜索下拉 ──────────────────────────────────────────────────────────────────
class _SuggDrop extends StatelessWidget {
  final List<Stock> suggestions;
  final ValueChanged<Stock> onSelect;
  final VoidCallback onDismiss;
  const _SuggDrop({required this.suggestions, required this.onSelect, required this.onDismiss});
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: ListView.separated(
          padding: EdgeInsets.zero, shrinkWrap: true,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.borderColor),
          itemBuilder: (_, i) {
            final s = suggestions[i];
            return InkWell(
              borderRadius: BorderRadius.circular(10), onTap: () => onSelect(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(child: Text(s.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Text(s.code, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(s.market, style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                  if (s.isFund) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.primaryGreen.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('基金', style: TextStyle(color: AppTheme.primaryGreen, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── 综合结果卡 ────────────────────────────────────────────────────────────────
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
          colors: [result.color.withValues(alpha: 0.18), AppTheme.bgCard],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: result.color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          name.trim().isEmpty ? '观察标的' : name.trim(),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(result.level,
              style: TextStyle(color: result.color, fontSize: 24, fontWeight: FontWeight.w900))),
          Text('${result.score}分',
              style: TextStyle(color: result.color, fontSize: 24, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 12),
        _MsgList(
          title: '硬性过滤',
          items: result.hardBlocks.isEmpty ? ['未触发硬性排除项'] : result.hardBlocks,
          color: result.hardBlocks.isEmpty ? AppTheme.primaryGreen : AppTheme.riskRed,
        ),
        const SizedBox(height: 8),
        _MsgList(
          title: '优势',
          items: result.strengths.isEmpty ? ['暂无明显加分项'] : result.strengths,
          color: AppTheme.primaryGreen,
        ),
        const SizedBox(height: 8),
        _MsgList(
          title: '风险',
          items: result.warnings.isEmpty ? ['暂无明显扣分项'] : result.warnings,
          color: AppTheme.accentGold,
        ),
      ]),
    );
  }
}

// ── 自动数据展示：行情 + 估值 ─────────────────────────────────────────────────
class _AutoDataCard extends StatelessWidget {
  final double? price;
  final int? pePct, pbPct;
  final bool peEst, pbEst;
  final String? trend, trendTip;
  const _AutoDataCard({
    this.price, this.pePct, this.pbPct,
    this.peEst = false, this.pbEst = false,
    this.trend, this.trendTip,
  });
  @override
  Widget build(BuildContext context) {
    return _Card(title: '估值百分位 & K线趋势', children: [
      Row(children: [
        Expanded(child: _ReadItem(
          label: '当前价',
          value: price != null ? '${price!.toStringAsFixed(3)} 元' : '—',
          badge: null,
        )),
        Expanded(child: _ReadItem(
          label: 'PE历史百分位',
          value: pePct != null ? '$pePct%' : '—',
          badge: peEst ? '估算' : null,
          warn: pePct != null && pePct! >= 80,
          good: pePct != null && pePct! <= 30,
        )),
        Expanded(child: _ReadItem(
          label: 'PB历史百分位',
          value: pbPct != null ? '$pbPct%' : '—',
          badge: pbEst ? '估算' : null,
          warn: pbPct != null && pbPct! >= 80,
          good: pbPct != null && pbPct! <= 30,
        )),
      ]),
      if (trendTip != null) ...[
        const SizedBox(height: 10),
        _TrendRow(trend: trend ?? 'neutral', tip: trendTip!),
      ],
    ]);
  }
}

// ── 自动数据展示：财务安全 ────────────────────────────────────────────────────
class _FinancialAutoCard extends StatelessWidget {
  final double? pledge, debt, goodwill, cashflow;
  const _FinancialAutoCard({this.pledge, this.debt, this.goodwill, this.cashflow});
  @override
  Widget build(BuildContext context) {
    return _Card(title: '财务安全（自动拉取）', children: [
      Row(children: [
        Expanded(child: _ReadItem(
          label: '大股东质押率',
          value: pledge != null ? '${pledge!.toStringAsFixed(1)}%' : '—',
          warn: pledge != null && pledge! >= 30,
          good: pledge != null && pledge! < 10,
          hardWarn: pledge != null && pledge! >= 50,
        )),
        Expanded(child: _ReadItem(
          label: '资产负债率',
          value: debt != null ? '${debt!.toStringAsFixed(1)}%' : '—',
          warn: debt != null && debt! >= 70,
          good: debt != null && debt! <= 45,
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _ReadItem(
          label: '商誉/净资产',
          value: goodwill != null ? '${goodwill!.toStringAsFixed(1)}%' : '—',
          warn: goodwill != null && goodwill! >= 30,
          good: goodwill != null && goodwill! < 5,
        )),
        Expanded(child: _ReadItem(
          label: '经营现金流/净利润',
          value: cashflow != null ? '${cashflow!.toStringAsFixed(1)}%' : '—',
          warn: cashflow != null && cashflow! < 5,
          good: cashflow != null && cashflow! >= 50,
          hardWarn: cashflow != null && cashflow! < 0,
        )),
      ]),
      const SizedBox(height: 10),
      const _AutoNote(text: '以上数据由东方财富数据中心自动拉取，仅供参考，建议结合年报核实。'),
    ]);
  }
}

// ── 自动数据展示：分红灌溉 ────────────────────────────────────────────────────
class _DividendAutoCard extends StatelessWidget {
  final double? yield_;
  final int? years;
  final String? stability;
  final bool isFund;
  const _DividendAutoCard({this.yield_, this.years, this.stability, this.isFund = false});
  String get _stabilityLabel {
    if (stability == 'stable')   return '稳定';
    if (stability == 'unstable') return '不稳定';
    if (stability == 'normal')   return '一般';
    return '—';
  }
  Color _stabilityColor(BuildContext ctx) {
    if (stability == 'stable')   return AppTheme.primaryGreen;
    if (stability == 'unstable') return AppTheme.riskRed;
    return AppTheme.textSecondary;
  }
  @override
  Widget build(BuildContext context) {
    final yieldLabel = isFund ? '近12月收益率' : '股息率';
    final yearsLabel = isFund ? '历史分红次数' : '连续分红年数';
    final yearsUnit  = isFund ? '次' : '年';
    final noteText   = isFund
        ? '收益率 ≥3% 且有稳定分红记录为播种参考标准，ETF/LOF 分红为灌溉核心来源。'
        : '股息率 ≥3% 且连续分红 ≥5年为播种标准，分红是零成本策略的核心灌溉来源。';
    return _Card(title: '分红灌溉（自动拉取）', children: [
      Row(children: [
        Expanded(child: _ReadItem(
          label: yieldLabel,
          value: yield_ != null ? '${yield_!.toStringAsFixed(2)}%' : '—',
          good: yield_ != null && yield_! >= 3,
          warn: yield_ != null && yield_! < 1 && yield_! > 0,
        )),
        Expanded(child: _ReadItem(
          label: yearsLabel,
          value: years != null ? '$years $yearsUnit' : '—',
          good: years != null && years! >= 5,
          warn: years != null && years! < 2,
        )),
        Expanded(child: _ReadItem(
          label: '分红稳定性',
          value: _stabilityLabel,
          valueColor: stability != null ? _stabilityColor(context) : null,
        )),
      ]),
      const SizedBox(height: 10),
      _AutoNote(text: noteText),
    ]);
  }
}

// ── 基金专用数据展示：行情 + K线趋势（无PE/PB） ───────────────────────────────
class _FundDataCard extends StatelessWidget {
  final double? price;
  final String? trend, trendTip;
  const _FundDataCard({this.price, this.trend, this.trendTip});
  @override
  Widget build(BuildContext context) {
    return _Card(title: '行情 & K线趋势（基金）', children: [
      Row(children: [
        Expanded(child: _ReadItem(
          label: '当前价',
          value: price != null ? '${price!.toStringAsFixed(3)} 元' : '—',
        )),
        Expanded(child: _ReadItem(
          label: 'PE/PB百分位',
          value: 'N/A',
          badge: '基金不适用',
        )),
      ]),
      if (trendTip != null) ...[
        const SizedBox(height: 10),
        _TrendRow(trend: trend ?? 'neutral', tip: trendTip!),
      ],
      const SizedBox(height: 10),
      const _AutoNote(text: 'ETF/LOF 无 PE/PB 历史估值，可参考折溢价率和跟踪误差评估买入时机。'),
    ]);
  }
}

// ── 用户录入：硬性一票否决 ────────────────────────────────────────────────────
class _HardFilterCard extends StatelessWidget {
  final bool isSt, delistRisk, violationGuarantee, financialFraudRisk;
  final ValueChanged<bool> onStChanged, onDelistChanged, onGuaranteeChanged, onFraudChanged;
  const _HardFilterCard({
    required this.isSt, required this.delistRisk,
    required this.violationGuarantee, required this.financialFraudRisk,
    required this.onStChanged, required this.onDelistChanged,
    required this.onGuaranteeChanged, required this.onFraudChanged,
  });
  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '硬性一票否决（人工判断）',
      borderColor: AppTheme.accentGold.withValues(alpha: 0.4),
      children: [
        const _AutoNote(text: '以下任意一项触发，立即停止播种。ST状态和退市风险可由系统辅助识别，违规担保和财务造假需人工核查。'),
        const SizedBox(height: 10),
        _SwitchRow(label: 'ST / *ST 标的', value: isSt, onChanged: onStChanged,
            desc: '被特别处理，流动性和基本面均有风险'),
        _SwitchRow(label: '退市风险', value: delistRisk, onChanged: onDelistChanged,
            desc: '名称含"退"或处于退市整理期'),
        _SwitchRow(label: '违规担保', value: violationGuarantee, onChanged: onGuaranteeChanged,
            desc: '存在违规对外担保，资产可能被冻结'),
        _SwitchRow(label: '财务造假风险', value: financialFraudRisk, onChanged: onFraudChanged,
            desc: '审计意见非标、核心数据异常'),
      ],
    );
  }
}

// ── 用户录入：播种计划价 ──────────────────────────────────────────────────────
class _SeedPlanCard extends StatelessWidget {
  final TextEditingController seedPriceController;
  final TextEditingController maxAddPriceController;
  final TextEditingController harvestPriceController;
  final List<String> alerts;
  final VoidCallback onChanged;
  const _SeedPlanCard({
    required this.seedPriceController, required this.maxAddPriceController,
    required this.harvestPriceController, required this.alerts, required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '播种计划价（人工录入）',
      borderColor: AppTheme.accentGold.withValues(alpha: 0.4),
      children: [
        const _AutoNote(text: '以下价格由用户根据个人判断设定，自动拉取仅提供参考初始值（当前价 ×0.92 / ×1.20）。'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _NumField(
            label: '播种触发价',
            hint: '首批买入触发线',
            suffix: '元',
            controller: seedPriceController,
            onChanged: onChanged,
          )),
          const SizedBox(width: 12),
          Expanded(child: _NumField(
            label: '最高加仓价',
            hint: '仓位封顶线',
            suffix: '元',
            controller: maxAddPriceController,
            onChanged: onChanged,
          )),
        ]),
        const SizedBox(height: 12),
        _NumField(
          label: '目标收割价',
          hint: '回本/收割触发线',
          suffix: '元',
          controller: harvestPriceController,
          onChanged: onChanged,
        ),
        const SizedBox(height: 14),
        _MsgList(title: '触发状态', items: alerts, color: AppTheme.accent),
      ],
    );
  }
}

// ── 只读数值展示项 ────────────────────────────────────────────────────────────
class _ReadItem extends StatelessWidget {
  final String label;
  final String value;
  final String? badge;
  final Color? valueColor;
  final bool warn;
  final bool good;
  final bool hardWarn;

  const _ReadItem({
    required this.label,
    required this.value,
    this.badge,
    this.valueColor,
    this.warn = false,
    this.good = false,
    this.hardWarn = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color vColor = hardWarn
        ? AppTheme.riskRed
        : warn
            ? AppTheme.accentGold
            : good
                ? AppTheme.primaryGreen
                : valueColor ?? AppTheme.textPrimary;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      const SizedBox(height: 4),
      Row(children: [
        Text(value, style: TextStyle(color: vColor, fontSize: 15, fontWeight: FontWeight.w700)),
        if (badge != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(badge!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
          ),
        ],
      ]),
    ]);
  }
}

// ── K线趋势行 ─────────────────────────────────────────────────────────────────
class _TrendRow extends StatelessWidget {
  final String trend;
  final String tip;
  const _TrendRow({required this.trend, required this.tip});

  @override
  Widget build(BuildContext context) {
    final Color c = trend == 'up'
        ? AppTheme.accentGold
        : trend == 'down'
            ? AppTheme.riskRed
            : AppTheme.textSecondary;
    final String label = trend == 'up' ? '上行' : trend == 'down' ? '下行' : '震荡';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('K线 $label', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(tip, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.3))),
      ]),
    );
  }
}

// ── 自动备注 ──────────────────────────────────────────────────────────────────
class _AutoNote extends StatelessWidget {
  final String text;
  const _AutoNote({required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, size: 12, color: AppTheme.textMuted),
      const SizedBox(width: 5),
      Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4))),
    ]);
  }
}

// ── Switch 行 ─────────────────────────────────────────────────────────────────
class _SwitchRow extends StatelessWidget {
  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, required this.desc, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(
            color: value ? AppTheme.riskRed : AppTheme.textSecondary,
            fontSize: 13, fontWeight: value ? FontWeight.w700 : FontWeight.normal,
          )),
          Text(desc, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.3)),
        ])),
        Switch(value: value, onChanged: onChanged, activeColor: AppTheme.riskRed),
      ]),
    );
  }
}

// ── 数字输入框 ────────────────────────────────────────────────────────────────
class _NumField extends StatelessWidget {
  final String label;
  final String hint;
  final String suffix;
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _NumField({
    required this.label, required this.hint, required this.suffix,
    required this.controller, required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
        onChanged: (_) => onChanged(),
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          suffixText: suffix,
          suffixStyle: const TextStyle(color: AppTheme.textMuted),
        ),
      ),
    ]);
  }
}

// ── 字段标签 ──────────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12));
}

// ── 双选切换 ──────────────────────────────────────────────────────────────────
class _TogglePair extends StatelessWidget {
  final List<String> labels;
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;
  const _TogglePair({required this.labels, required this.values, required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final sel = values[i] == selected;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
          child: GestureDetector(
            onTap: () => onChanged(values[i]),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? AppTheme.accent.withValues(alpha: 0.15) : AppTheme.bgCardLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sel ? AppTheme.accent : AppTheme.borderColor),
              ),
              child: Text(labels[i], style: TextStyle(
                color: sel ? AppTheme.accent : AppTheme.textSecondary,
                fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
              )),
            ),
          ),
        ));
      }),
    );
  }
}

// ── 消息列表 ──────────────────────────────────────────────────────────────────
class _MsgList extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color color;
  const _MsgList({required this.title, required this.items, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      ...items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.circle, color: color, size: 6),
          const SizedBox(width: 8),
          Expanded(child: Text(item, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.35))),
        ]),
      )),
    ]);
  }
}

// ── 数据模型 ──────────────────────────────────────────────────────────────────
class _ScreeningResult {
  final int score;
  final String level;
  final Color color;
  final List<String> hardBlocks;
  final List<String> warnings;
  final List<String> strengths;
  final List<String> priceAlerts;

  const _ScreeningResult({
    required this.score, required this.level, required this.color,
    required this.hardBlocks, required this.warnings,
    required this.strengths, required this.priceAlerts,
  });
}

