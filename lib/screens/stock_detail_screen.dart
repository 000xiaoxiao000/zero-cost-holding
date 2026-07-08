import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../providers/stock_providers.dart';
import '../models/watchlist.dart';
import '../models/stock.dart';
import '../models/stock_context.dart';
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
                    label: '成交额', value: Formatters.largeNumber(stock.turnover))),
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
  bool get _capOk =>
      stock.marketCap > 2e9 && stock.marketCap < 2e11;

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
            label: 'PB估值${stock.pb > 0 && stock.pb < 1 ? "破净" : stock.pb > 0 && stock.pb < 2 ? "合理(<2)" : stock.pb > 0 ? "偏高(≥2)" : "暂无"}',
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
                style: TextStyle(
                    color: recColor, fontSize: 12, height: 1.5)),
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
                    builder: (_) => HarvestCalculatorScreen(
                        stockContext: _buildContext()),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            '排雷通过后制定播种计划，持仓回本后用收割计算确认零成本仓位',
            style: TextStyle(
                color: AppTheme.textMuted, fontSize: 11, height: 1.4),
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
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 10),
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
