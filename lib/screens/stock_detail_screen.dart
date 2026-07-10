import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../navigation/app_navigation.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../providers/stock_providers.dart';
import '../models/watchlist.dart';
import '../models/stock.dart';
import '../models/stock_context.dart';
import '../models/dividend_financing.dart';
import 'seed_screening_screen.dart';
import 'seed_plan_screen.dart';
import 'harvest_calculator_screen.dart';

class StockDetailScreen extends ConsumerWidget {
  final String code;
  final String name;
  final String market;

  const StockDetailScreen({
    super.key,
    required this.code,
    required this.name,
    required this.market,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quoteAsync = ref.watch(stockQuoteProvider((code, market)));
    final klineAsync = ref.watch(klineProvider((code, market)));
    final watchlist = ref.watch(watchlistProvider);
    final inWatchlist = watchlist.any((w) => w.stockCode == code);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text('$market · $code',
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              inWatchlist ? Icons.bookmark : Icons.bookmark_outline,
              color: inWatchlist ? AppTheme.accentGold : AppTheme.textSecondary,
            ),
            onPressed: () async {
              if (inWatchlist) {
                await ref.read(watchlistProvider.notifier).remove(code);
              } else {
                await ref.read(watchlistProvider.notifier).add(
                      Watchlist(
                          stockCode: code, stockName: name, market: market),
                    );
              }
            },
          ),
          const HomeTabMenuButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(stockQuoteProvider((code, market)));
          ref.invalidate(klineProvider((code, market)));
        },
        color: AppTheme.accent,
        backgroundColor: AppTheme.bgCard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            quoteAsync.when(
              data: (stock) => stock != null
                  ? _QuoteCard(stock: stock)
                  : const _DataError(msg: '行情数据获取失败'),
              loading: () => const _SkeletonBox(height: 150),
              error: (_, __) => const _DataError(msg: '行情数据获取失败'),
            ),
            const SizedBox(height: 16),
            const _SectionHeader(title: 'K线走势'),
            const SizedBox(height: 10),
            klineAsync.when(
              data: (klines) => klines.isNotEmpty
                  ? _SimpleKlineChart(klines: klines)
                  : const _DataError(msg: 'K线数据暂无'),
              loading: () => const _SkeletonBox(height: 160),
              error: (_, __) => const _DataError(msg: 'K线数据获取失败'),
            ),
            const SizedBox(height: 16),
            quoteAsync.when(
              data: (stock) => stock != null
                  ? _ValuationCard(stock: stock)
                  : const SizedBox.shrink(),
              loading: () => const _SkeletonBox(height: 120),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            quoteAsync.when(
              data: (stock) => _DividendFinancingSection(
                  code: code, market: market, stock: stock),
              loading: () => _DividendFinancingSection(
                  code: code, market: market, stock: null),
              error: (_, __) => _DividendFinancingSection(
                  code: code, market: market, stock: null),
            ),
            const SizedBox(height: 16),
            quoteAsync.when(
              data: (stock) => stock != null
                  ? _EntryAnalysisCard(stock: stock)
                  : const SizedBox.shrink(),
              loading: () => const _SkeletonBox(height: 200),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            quoteAsync.when(
              data: (stock) => stock != null
                  ? _FlowActionBar(
                      code: code,
                      name: name,
                      market: market,
                      stock: stock,
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final Stock stock;
  const _QuoteCard({required this.stock});

  @override
  Widget build(BuildContext context) {
    final color =
        stock.changePercent >= 0 ? AppTheme.accentGold : AppTheme.primaryGreen;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Formatters.price(stock.price),
                  style: TextStyle(
                      color: color, fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Formatters.change(stock.change),
                      style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(Formatters.percent(stock.changePercent),
                        style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const Spacer(),
              if (stock.dataTime != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('行情时间',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(_fmtQuoteTime(stock.dataTime!),
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _QuoteItem(
                    label: '今开', value: Formatters.price(stock.open))),
            Expanded(
                child: _QuoteItem(
                    label: '最高',
                    value: Formatters.price(stock.high),
                    color: AppTheme.accentGold)),
            Expanded(
                child: _QuoteItem(
                    label: '最低',
                    value: Formatters.price(stock.low),
                    color: AppTheme.primaryGreen)),
            Expanded(
                child: _QuoteItem(
                    label: '成交量', value: Formatters.largeNumber(stock.volume))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _QuoteItem(
                    label: '昨收', value: Formatters.price(stock.preClose))),
            Expanded(
                child: _QuoteItem(
                    label: '成交额',
                    value: Formatters.largeNumber(stock.turnover))),
            Expanded(
                child: _QuoteItem(
                    label: '换手率',
                    value: stock.turnoverRate > 0
                        ? '${stock.turnoverRate.toStringAsFixed(2)}%'
                        : '--')),
            const Expanded(child: SizedBox()),
          ]),
        ],
      ),
    );
  }

  /// 行情数据时间：当天显示时分，跨天补月日。
  String _fmtQuoteTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final hm = '${two(t.hour)}:${two(t.minute)}';
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? hm : '${two(t.month)}-${two(t.day)} $hm';
  }
}

class _QuoteItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _QuoteItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              color: color ?? AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500)),
    ]);
  }
}

class _ValuationCard extends StatelessWidget {
  final Stock stock;
  const _ValuationCard({required this.stock});

  String _peLabel(double pe) {
    if (pe <= 0) return '暂无';
    if (pe < 10) return '低估';
    if (pe < 20) return '合理';
    if (pe < 35) return '偏高';
    return '高估';
  }

  Color _peColor(double pe) {
    if (pe <= 0) return AppTheme.textMuted;
    if (pe < 10) return AppTheme.primaryGreen;
    if (pe < 20) return AppTheme.accentGold;
    if (pe < 35) return Colors.orange;
    return AppTheme.riskRed;
  }

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
          const _SectionHeader(title: '估值参考'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _ValCard(
                    label: '市盈率(PE)',
                    value: stock.pe > 0 ? stock.pe.toStringAsFixed(2) : '-',
                    tag: _peLabel(stock.pe),
                    tagColor: _peColor(stock.pe))),
            const SizedBox(width: 10),
            Expanded(
                child: _ValCard(
                    label: '市净率(PB)',
                    value: stock.pb > 0 ? stock.pb.toStringAsFixed(2) : '-',
                    tag: stock.pb > 0
                        ? (stock.pb < 1
                            ? '破净'
                            : stock.pb < 2
                                ? '合理'
                                : '偏高')
                        : '-',
                    tagColor: stock.pb > 0 && stock.pb < 1
                        ? AppTheme.primaryGreen
                        : AppTheme.accentGold)),
            const SizedBox(width: 10),
            Expanded(
                child: _ValCard(
                    label: '总市值',
                    value: Formatters.marketCap(stock.marketCap),
                    tag: stock.marketCap > 1e11
                        ? '大盘'
                        : stock.marketCap > 2e10
                            ? '中盘'
                            : '小盘',
                    tagColor: AppTheme.textSecondary)),
          ]),
        ],
      ),
    );
  }
}

class _ValCard extends StatelessWidget {
  final String label;
  final String value;
  final String tag;
  final Color tagColor;
  const _ValCard(
      {required this.label,
      required this.value,
      required this.tag,
      required this.tagColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppTheme.bgCardLight, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(tag,
              style: TextStyle(
                  color: tagColor, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── 分红 & 融资板块 ───────────────────────────────────────────────────────────

class _DividendFinancingSection extends ConsumerWidget {
  final String code;
  final String market;
  final Stock? stock;
  const _DividendFinancingSection(
      {required this.code, required this.market, this.stock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dividendFinancingProvider((code, market)));
    return async.when(
      loading: () => const _SkeletonBox(height: 180),
      // 拉取失败也展示空态卡片，避免只剩空白间距
      error: (_, __) => _DividendFinancingCard(
          data:
              const DividendFinancingData(sourceNotes: ['分红/融资数据拉取失败，请下拉刷新重试']),
          stock: stock),
      data: (data) => _DividendFinancingCard(data: data, stock: stock),
    );
  }
}

class _DividendFinancingCard extends StatefulWidget {
  final DividendFinancingData data;
  final Stock? stock;
  const _DividendFinancingCard({required this.data, this.stock});

  @override
  State<_DividendFinancingCard> createState() => _DividendFinancingCardState();
}

class _DividendFinancingCardState extends State<_DividendFinancingCard> {
  bool _showDividend = true;

  DividendFinancingData get d => widget.data;
  Stock? get s => widget.stock;

  bool get _isFund => d.isFund || (s?.isFund ?? false);

  /// 基金累计每份分红（元），来自各期 cashPer10/10 求和。
  String _fundCumPerShare() {
    double sum = 0;
    for (final r in d.records) {
      if (r.cashPer10 > 0) sum += r.cashPer10 / 10.0;
    }
    if (sum <= 0) return '--';
    return '${sum.toStringAsFixed(3)}元';
  }

  /// 综合分红画像 + 当前估值，给出「播种」与「收割」两条专业建议。
  /// 返回：分红定性文案、播种建议、收割建议、整体色调。
  ({String profile, String seed, String harvest, Color color, IconData icon})
      get _advice {
    final ratio = d.divFinRatio;
    final level = d.potentialLevel;
    final pe = s?.pe ?? 0;
    final pb = s?.pb ?? 0;
    final peHigh = pe > 35;
    final peLow = pe > 0 && pe < 15;
    final broken = pb > 0 && pb < 1; // 破净
    final yieldGood = (d.dividendYield ?? 0) >= 3;

    // 估值口径的播种/收割措辞，供各分支复用
    final seedByVal = peHigh
        ? '当前 PE ${pe > 0 ? pe.toStringAsFixed(0) : "--"} 偏高，暂不宜播种，'
            '等回调至合理估值或分红除权后的低点再分批建仓。'
        : (peLow || broken)
            ? '当前估值处于低位${broken ? "（PB<1 破净）" : ""}，是分批播种的较好窗口，'
                '可按计划金额定投式建仓，越跌越买摊低成本。'
            : '估值中性，建议小额试仓，价格回调时再加码，单批仓位≤总资金5%。';
    final harvestByVal = peHigh
        ? '若已有持仓且估值高企，可分批收割兑现浮盈，'
            '保留分红形成的零成本底仓长期收息。'
        : '持仓回本前不急于收割，让分红持续灌溉；'
            '待估值修复到高位或达目标价时再分批止盈。';

    // 无数据兜底
    if (!d.hasData) {
      return (
        profile: _isFund
            ? '基金（ETF/LOF）分红维度不适用，可参考跟踪指数股息与折溢价。'
            : '暂未取到分红/融资数据，请下拉刷新或结合公司公告核实。',
        seed: seedByVal,
        harvest: harvestByVal,
        color: AppTheme.textSecondary,
        icon: Icons.info_outline,
      );
    }

    if (d.dividendCount == 0 && d.financingCount > 0) {
      return (
        profile: '多次融资却从未派现，属「只抽血不灌溉」型，'
            '零成本策略无法依赖分红降本。',
        seed: '不建议将其作为收息底仓；如仅做波段，'
            '务必等深度回调且放量企稳再小仓位播种。',
        harvest: '反弹或达目标价即分批收割，不恋战，'
            '严格执行止盈止损，避免长期套牢。',
        color: AppTheme.riskRed,
        icon: Icons.warning_amber_rounded,
      );
    }
    if (ratio != null && ratio >= 100) {
      return (
        profile: '累计派现超过累计融资（派现融资比 ${ratio.toStringAsFixed(0)}%），'
            '持续回馈股东的优质现金牛。',
        seed: '适合作为零成本核心底仓。$seedByVal',
        harvest: '首选长期持有收息，$harvestByVal',
        color: AppTheme.primaryGreen,
        icon: Icons.verified_outlined,
      );
    }
    if (level == 'high') {
      return (
        profile: '分红频次高、连续性好，灌溉能力强'
            '${yieldGood ? "，股息率可观" : ""}。',
        seed: seedByVal,
        harvest: harvestByVal,
        color: AppTheme.primaryGreen,
        icon: Icons.eco_outlined,
      );
    }
    if (level == 'mid') {
      return (
        profile: '有一定分红记录但连续性或力度一般，'
            '需观察股利支付率与现金流能否支撑分红延续。',
        seed: '可小仓位参与，$seedByVal 避免在融资密集期追高。',
        harvest: '以波段收割为主，$harvestByVal',
        color: AppTheme.accentGold,
        icon: Icons.balance,
      );
    }
    return (
      profile: '分红偏弱或以送转为主，现金回馈有限，灌溉来源不足。',
      seed: '不宜重仓收息，$seedByVal 仓位从严控制。',
      harvest: '依赖波段收割而非长期收息，$harvestByVal',
      color: AppTheme.textSecondary,
      icon: Icons.info_outline,
    );
  }

  String _potentialLabel(String level) {
    switch (level) {
      case 'high':
        return '高';
      case 'mid':
        return '中';
      default:
        return '低';
    }
  }

  Color _potentialColor(String level) {
    switch (level) {
      case 'high':
        return AppTheme.primaryGreen;
      case 'mid':
        return AppTheme.accentGold;
      default:
        return AppTheme.textMuted;
    }
  }

  /// 「分红」页签：个股显示股息率/股利支付率/派现融资比；基金显示股息率/分红次数/累计每份分红。
  List<Widget> _buildDividendPanel() {
    return [
      Row(children: [
        Expanded(
            child: _MetricTile(
                label: _isFund ? '近12月分红率' : '股息率',
                value: d.dividendYield != null
                    ? '${d.dividendYield!.toStringAsFixed(2)}%'
                    : '--',
                color: d.dividendYield != null && d.dividendYield! >= 3
                    ? AppTheme.primaryGreen
                    : AppTheme.textPrimary)),
        if (_isFund) ...[
          Expanded(
              child: _MetricTile(label: '分红次数', value: '${d.dividendCount}')),
          Expanded(
              child: _MetricTile(
                  label: '累计每份',
                  value: _fundCumPerShare(),
                  color: AppTheme.accentGold)),
        ] else ...[
          Expanded(
              child: _MetricTile(
                  label: '股利支付率',
                  value: d.payoutRatio != null
                      ? '${d.payoutRatio!.toStringAsFixed(2)}%'
                      : '--')),
          Expanded(
              child: _MetricTile(
                  label: '派现融资比',
                  value: d.divFinRatio != null
                      ? '${d.divFinRatio!.toStringAsFixed(2)}%'
                      : '--',
                  color: d.divFinRatio != null && d.divFinRatio! >= 100
                      ? AppTheme.primaryGreen
                      : d.divFinRatio != null && d.divFinRatio! < 20
                          ? AppTheme.riskRed
                          : AppTheme.textPrimary)),
        ],
      ]),
      const SizedBox(height: 14),
      Row(children: [
        const Icon(Icons.notifications_active_outlined,
            size: 14, color: AppTheme.accentGold),
        const SizedBox(width: 6),
        const Text('潜在派现概率',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(width: 6),
        Text(_potentialLabel(d.potentialLevel),
            style: TextStyle(
                color: _potentialColor(d.potentialLevel),
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ]),
      if (d.records.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(_isFund ? '分红配送' : '分红送转',
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _DividendTable(records: d.records.take(6).toList(), isFund: _isFund),
      ] else ...[
        const SizedBox(height: 12),
        const _EmptyHint(text: '暂无分红送转记录'),
      ],
    ];
  }

  /// 「融资」页签：首发 / 再融资 / 派现融资比 + 融资明细
  List<Widget> _buildFinancingPanel() {
    return [
      Row(children: [
        Expanded(
            child: _MetricTile(
                label: '首发募资',
                value: d.ipoTotal != null
                    ? Formatters.largeNumber(d.ipoTotal!)
                    : '--',
                color: AppTheme.riskRed)),
        Expanded(
            child: _MetricTile(
                label: '再融资',
                value: d.refinanceTotal != null
                    ? Formatters.largeNumber(d.refinanceTotal!)
                    : '--',
                color: AppTheme.accentGold)),
        Expanded(
            child: _MetricTile(
                label: '派现融资比',
                value: d.divFinRatio != null
                    ? '${d.divFinRatio!.toStringAsFixed(2)}%'
                    : '--',
                color: d.divFinRatio != null && d.divFinRatio! >= 100
                    ? AppTheme.primaryGreen
                    : d.divFinRatio != null && d.divFinRatio! < 20
                        ? AppTheme.riskRed
                        : AppTheme.textPrimary)),
      ]),
      if (d.financingRecords.isNotEmpty) ...[
        const SizedBox(height: 14),
        const Text('融资明细',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _FinancingTable(records: d.financingRecords.take(6).toList()),
      ] else ...[
        const SizedBox(height: 12),
        _EmptyHint(
            text: _isFund
                ? '基金（ETF/LOF）无股权融资维度，分红来自跟踪指数成份股派息'
                : d.dividendCount > 0
                    ? '该标的上市后无再融资记录，仅靠自身经营即可持续派现，属优质标的'
                    : '暂无融资记录'),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final advice = _advice;
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
          const _SectionHeader(title: '分红 · 融资参考'),
          const SizedBox(height: 14),
          _DivFinToggle(
            showDividend: _isFund ? true : _showDividend,
            financingDisabled: _isFund,
            onChanged: (v) => setState(() => _showDividend = v),
          ),
          const SizedBox(height: 14),
          _DivFinSummaryBar(data: d),
          const SizedBox(height: 14),
          // 分红 / 融资 两个页签展示各自维度的指标与明细
          if (_isFund || _showDividend)
            ..._buildDividendPanel()
          else
            ..._buildFinancingPanel(),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: advice.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: advice.color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(advice.icon, size: 15, color: advice.color),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(advice.profile,
                          style: TextStyle(
                              color: advice.color,
                              fontSize: 12,
                              height: 1.5,
                              fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 10),
                _AdviceRow(
                    tag: '播种',
                    icon: Icons.grass_outlined,
                    tagColor: AppTheme.primaryGreen,
                    text: advice.seed),
                const SizedBox(height: 8),
                _AdviceRow(
                    tag: '收割',
                    icon: Icons.content_cut,
                    tagColor: AppTheme.accentGold,
                    text: advice.harvest),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 12, color: AppTheme.textMuted),
            SizedBox(width: 5),
            Expanded(
                child: Text('数据来自东方财富数据中心，仅供参考，请结合公司公告核实。',
                    style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 11, height: 1.4))),
          ]),
        ],
      ),
    );
  }
}

class _DivFinToggle extends StatelessWidget {
  final bool showDividend;
  final bool financingDisabled; // 基金无融资维度时置灰「融资」页签
  final ValueChanged<bool> onChanged;
  const _DivFinToggle({
    required this.showDividend,
    required this.onChanged,
    this.financingDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _tab('分红', showDividend, AppTheme.accentGold, () => onChanged(true),
          disabled: false),
      const SizedBox(width: 8),
      _tab('融资', !showDividend && !financingDisabled, AppTheme.riskRed,
          financingDisabled ? null : () => onChanged(false),
          disabled: financingDisabled),
    ]);
  }

  Widget _tab(String label, bool sel, Color color, VoidCallback? onTap,
      {required bool disabled}) {
    final content = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: disabled
            ? AppTheme.bgCardLight.withValues(alpha: 0.4)
            : sel
                ? color.withValues(alpha: 0.15)
                : AppTheme.bgCardLight,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: sel ? color : AppTheme.borderColor, width: 0.8),
      ),
      child: Text(disabled ? '$label（无）' : label,
          style: TextStyle(
              color: disabled
                  ? AppTheme.textMuted.withValues(alpha: 0.5)
                  : sel
                      ? color
                      : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
    );
    return Expanded(
      child: disabled
          ? Opacity(opacity: 0.6, child: content)
          : GestureDetector(onTap: onTap, child: content),
    );
  }
}

class _DivFinSummaryBar extends StatelessWidget {
  final DividendFinancingData data;
  const _DivFinSummaryBar({required this.data});

  @override
  Widget build(BuildContext context) {
    final divAmt = data.dividendTotal ?? 0;
    final finAmt = data.financingTotal ?? 0;
    final total = divAmt + finAmt;
    final divFlex =
        total > 0 ? (divAmt / total * 100).round().clamp(1, 99) : 50;
    final finFlex = 100 - divFlex;
    return Column(children: [
      Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('A股派现 ${data.dividendCount}次',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
                data.dividendTotal != null
                    ? Formatters.largeNumber(data.dividendTotal!)
                    : '--',
                style: const TextStyle(
                    color: AppTheme.accentGold,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('A股融资 ${data.financingCount}次',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
                data.financingTotal != null
                    ? Formatters.largeNumber(data.financingTotal!)
                    : '--',
                style: const TextStyle(
                    color: AppTheme.riskRed,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Row(children: [
          Expanded(
            flex: divFlex,
            child: Container(height: 6, color: AppTheme.accentGold),
          ),
          Expanded(
            flex: finFlex,
            child: Container(height: 6, color: AppTheme.riskRed),
          ),
        ]),
      ),
    ]);
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _MetricTile({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              color: color ?? AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
    ]);
  }
}

class _AdviceRow extends StatelessWidget {
  final String tag;
  final IconData icon;
  final Color tagColor;
  final String text;
  const _AdviceRow(
      {required this.tag,
      required this.icon,
      required this.tagColor,
      required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: tagColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(5)),
        child: Row(children: [
          Icon(icon, size: 12, color: tagColor),
          const SizedBox(width: 4),
          Text(tag,
              style: TextStyle(
                  color: tagColor, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, height: 1.45))),
    ]);
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
          color: AppTheme.bgCardLight, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        const Icon(Icons.inbox_outlined, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12, height: 1.4))),
      ]),
    );
  }
}

class _FinancingTable extends StatelessWidget {
  final List<FinancingRecord> records;
  const _FinancingTable({required this.records});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Row(children: [
        Expanded(flex: 4, child: _Th('日期')),
        Expanded(flex: 3, child: _Th('类型')),
        Expanded(
            flex: 3,
            child: Align(alignment: Alignment.centerRight, child: _Th('募资净额'))),
      ]),
      const SizedBox(height: 6),
      ...records.map((r) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(flex: 4, child: _Td(r.date)),
              Expanded(flex: 3, child: _Td(r.type)),
              Expanded(
                  flex: 3,
                  child: Text(Formatters.largeNumber(r.amount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: AppTheme.riskRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w600))),
            ]),
          )),
    ]);
  }
}

class _DividendTable extends StatelessWidget {
  final List<DividendRecord> records;
  final bool isFund;
  const _DividendTable({required this.records, this.isFund = false});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(flex: 3, child: _Th(isFund ? '权益登记日' : '报告期')),
        Expanded(flex: 4, child: _Th(isFund ? '除息日' : '分红方案')),
        Expanded(flex: 3, child: _Th(isFund ? '单位分红' : '股权登记日')),
      ]),
      const SizedBox(height: 6),
      ...records.map((r) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: isFund
                    ? [
                        Expanded(flex: 3, child: _Td(r.recordDate)),
                        Expanded(flex: 4, child: _Td(r.exDate)),
                        Expanded(
                            flex: 3,
                            child: _Td(
                                '${(r.cashPer10 / 10).toStringAsFixed(3)}元')),
                      ]
                    : [
                        Expanded(flex: 3, child: _Td(r.reportPeriod)),
                        Expanded(flex: 4, child: _Td(r.plan)),
                        Expanded(flex: 3, child: _Td(r.recordDate)),
                      ]),
          )),
    ]);
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11));
}

class _Td extends StatelessWidget {
  final String text;
  const _Td(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 12, height: 1.3));
}

class _EntryAnalysisCard extends StatelessWidget {
  final Stock stock;
  const _EntryAnalysisCard({required this.stock});

  // 根据书中"零成本播种术"：PE绝对值仅作参考，核心看市盈率档位
  // <10 极低估, 10-20 合理, 20-35 偏高, >35 高估；无数据时不计分
  int _peScore() {
    if (stock.pe <= 0) return 0;
    if (stock.pe < 10) return 3;
    if (stock.pe < 20) return 2;
    if (stock.pe < 35) return 1;
    return 0;
  }

  String _peSignalLabel() {
    if (stock.pe <= 0) return 'PE数据暂无';
    if (stock.pe < 10) return 'PE极低估 (<10)';
    if (stock.pe < 20) return 'PE合理 (10-20)';
    if (stock.pe < 35) return 'PE偏高 (20-35)';
    return 'PE高估 (>35)';
  }

  Color _peSignalColor() {
    if (stock.pe <= 0) return AppTheme.textMuted;
    if (stock.pe < 10) return AppTheme.primaryGreen;
    if (stock.pe < 20) return AppTheme.accentGold;
    if (stock.pe < 35) return Colors.orange;
    return AppTheme.riskRed;
  }

  // PB<2 合理，1以下破净加分；高于3扣分
  int _pbScore() {
    if (stock.pb <= 0) return 0;
    if (stock.pb < 1) return 2;
    if (stock.pb < 2) return 1;
    return 0;
  }

  // 今日回调超1.5%为播种时机信号（书中"价格回调时分批播种"）
  bool get _priceDropped => stock.changePercent < -1.5;

  // 有成交量支撑，避免无量阴跌
  bool get _hasVolume => stock.volume > 0;

  // 市值适中（20亿~2000亿为书中偏好范围）
  bool get _capOk => stock.marketCap > 2e9 && stock.marketCap < 2e11;

  @override
  Widget build(BuildContext context) {
    final peScore = _peScore();
    final pbScore = _pbScore();
    final dropScore = _priceDropped ? 1 : 0;
    final volScore = _hasVolume ? 1 : 0;
    final capScore = _capOk ? 1 : 0;

    // 满分8分，4分以上可考虑播种
    final totalScore = peScore + pbScore + dropScore + volScore + capScore;
    final maxScore = 8;

    final String recommendation;
    final Color recColor;
    if (peScore == 0 && stock.pe > 0) {
      recommendation = 'PE偏高，暂不适合播种';
      recColor = AppTheme.riskRed;
    } else if (totalScore >= 5) {
      recommendation = '信号较强，可按计划分批播种，单仓位≤总资金5%';
      recColor = AppTheme.primaryGreen;
    } else if (totalScore >= 3) {
      recommendation = '信号一般，可小额观察性播种首批';
      recColor = AppTheme.accentGold;
    } else {
      recommendation = '信号偏弱，继续观察，等待更好价位';
      recColor = AppTheme.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: totalScore >= 5
                ? AppTheme.accentGold.withValues(alpha: 0.45)
                : AppTheme.borderColor,
            width: totalScore >= 5 ? 1.0 : 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.eco, color: AppTheme.accentGold, size: 16),
            const SizedBox(width: 8),
            const Text('播种信号分析',
                style: TextStyle(
                    color: AppTheme.accentGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: recColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('$totalScore/$maxScore',
                  style: TextStyle(
                      color: recColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 14),
          _SignalRow(
            label: _peSignalLabel(),
            met: peScore >= 2,
            partial: peScore == 1,
            detail: stock.pe > 0 ? 'PE ${stock.pe.toStringAsFixed(1)}' : '--',
            detailColor: _peSignalColor(),
          ),
          const SizedBox(height: 8),
          _SignalRow(
            label:
                'PB估值${stock.pb > 0 && stock.pb < 1 ? "破净" : stock.pb > 0 && stock.pb < 2 ? "合理(<2)" : stock.pb > 0 ? "偏高(≥2)" : "暂无"}',
            met: pbScore >= 2,
            partial: pbScore == 1,
            detail: stock.pb > 0 ? 'PB ${stock.pb.toStringAsFixed(2)}' : '--',
          ),
          const SizedBox(height: 8),
          _SignalRow(
            label: '今日回调买点(>1.5%)',
            met: _priceDropped,
            detail: Formatters.percent(stock.changePercent),
          ),
          const SizedBox(height: 8),
          _SignalRow(
            label: '成交量支撑',
            met: _hasVolume,
            detail: Formatters.largeNumber(stock.volume),
          ),
          const SizedBox(height: 8),
          _SignalRow(
            label: '市值规模适中(20亿-2000亿)',
            met: _capOk,
            detail: stock.marketCap > 0
                ? Formatters.marketCap(stock.marketCap)
                : '--',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: recColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: recColor.withValues(alpha: 0.25))),
            child: Text(recommendation,
                style: TextStyle(color: recColor, fontSize: 12, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  final String label;
  final bool met;
  final bool partial;
  final String detail;
  final Color? detailColor;

  const _SignalRow({
    required this.label,
    required this.met,
    this.partial = false,
    required this.detail,
    this.detailColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final IconData iconData;
    if (met) {
      iconColor = AppTheme.primaryGreen;
      iconData = Icons.check_circle;
    } else if (partial) {
      iconColor = AppTheme.accentGold;
      iconData = Icons.check_circle_outline;
    } else {
      iconColor = AppTheme.textMuted;
      iconData = Icons.radio_button_unchecked;
    }

    return Row(children: [
      Icon(iconData, color: iconColor, size: 16),
      const SizedBox(width: 8),
      Expanded(
          child: Text(label,
              style: TextStyle(
                  color: (met || partial)
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                  fontSize: 13))),
      Text(detail,
          style: TextStyle(
              color: detailColor ?? AppTheme.textMuted, fontSize: 12)),
    ]);
  }
}

class _FlowActionBar extends StatelessWidget {
  final String code;
  final String name;
  final String market;
  final Stock stock;

  const _FlowActionBar({
    required this.code,
    required this.name,
    required this.market,
    required this.stock,
  });

  StockContext _buildContext() => StockContext(
        code: code,
        name: name,
        market: market,
        assetType: 'stock',
        currentPrice: stock.price > 0 ? stock.price : null,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.alt_route, color: AppTheme.accent, size: 15),
            SizedBox(width: 6),
            Text('零成本播种流程',
                style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _FlowButton(
                icon: Icons.health_and_safety_outlined,
                label: '排雷',
                subtitle: '基本面筛查',
                color: AppTheme.primaryGreen,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SeedScreeningScreen(stockContext: _buildContext()),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FlowButton(
                icon: Icons.grass_outlined,
                label: '播种',
                subtitle: '分批建仓计划',
                color: AppTheme.accentGold,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SeedPlanScreen(stockContext: _buildContext()),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FlowButton(
                icon: Icons.auto_graph,
                label: '收割',
                subtitle: '零成本计算',
                color: Colors.orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        HarvestCalculatorScreen(stockContext: _buildContext()),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            '排雷通过后制定播种计划，持仓回本后用收割计算确认零成本仓位',
            style:
                TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _FlowButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _FlowButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SimpleKlineChart extends StatelessWidget {
  final List<Map<String, dynamic>> klines;
  const _SimpleKlineChart({required this.klines});

  @override
  Widget build(BuildContext context) {
    final recent =
        klines.length > 60 ? klines.sublist(klines.length - 60) : klines;
    final closes = recent.map((k) => (k['close'] as num).toDouble()).toList();
    if (closes.isEmpty) return const SizedBox.shrink();
    final minC = closes.reduce((a, b) => a < b ? a : b);
    final maxC = closes.reduce((a, b) => a > b ? a : b);
    final isUp = closes.last >= closes.first;

    return Container(
      height: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor, width: 0.5)),
      child: Stack(children: [
        Positioned(
            top: 0,
            right: 0,
            child: Text('近${recent.length}日',
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 10))),
        CustomPaint(
          size: const Size(double.infinity, 136),
          painter: _LinePainter(
              closes: closes,
              minVal: minC,
              range: maxC - minC,
              color: isUp ? AppTheme.accentGold : AppTheme.primaryGreen),
        ),
      ]),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> closes;
  final double minVal;
  final double range;
  final Color color;
  const _LinePainter(
      {required this.closes,
      required this.minVal,
      required this.range,
      required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (closes.length < 2) return;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final n = closes.length;
    final stepX = size.width / (n - 1);
    final effectiveRange = range < 0.001 ? 1.0 : range;
    double y(double v) =>
        size.height * (1 - (v - minVal) / effectiveRange) * 0.9 +
        size.height * 0.05;

    final path = Path()..moveTo(0, y(closes[0]));
    final fill = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, y(closes[0]));
    for (int i = 1; i < n; i++) {
      path.lineTo(i * stepX, y(closes[i]));
      fill.lineTo(i * stepX, y(closes[i]));
    }
    fill
      ..lineTo((n - 1) * stepX, size.height)
      ..close();
    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.closes != closes || old.color != color;
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
              color: AppTheme.accent, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600)),
    ]);
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;
  const _SkeletonBox({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
        height: height,
        decoration: BoxDecoration(
            color: AppTheme.bgCardLight,
            borderRadius: BorderRadius.circular(12)));
  }
}

class _DataError extends StatelessWidget {
  final String msg;
  const _DataError({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor, width: 0.5)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppTheme.textMuted, size: 16),
        const SizedBox(width: 8),
        Text(msg,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ]),
    );
  }
}
