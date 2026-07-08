import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../providers/stock_providers.dart';
import '../models/watchlist.dart';
import '../models/stock.dart';

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
          padding: const EdgeInsets.all(16),
          children: [
            quoteAsync.when(
              data: (stock) => stock != null
                  ? _QuoteCard(stock: stock)
                  : const _DataError(msg: '行情数据获取失败'),
              loading: () => const _SkeletonBox(height: 130),
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
              loading: () => const _SkeletonBox(height: 160),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 60),
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

  @override
  Widget build(BuildContext context) {
    final bool valuationOk = stock.pe > 0 && stock.pe < 25;
    final bool priceDropped = stock.changePercent < -1.5;
    final bool hasVolume = stock.volume > 0;
    final score =
        (valuationOk ? 1 : 0) + (priceDropped ? 1 : 0) + (hasVolume ? 1 : 0);
    final scoreColor = score >= 2 ? AppTheme.accentGold : AppTheme.textMuted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: score >= 2
                ? AppTheme.accentGold.withValues(alpha: 0.4)
                : AppTheme.borderColor,
            width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.eco, color: AppTheme.accentGold, size: 16),
            const SizedBox(width: 8),
            const Text('建仓信号分析',
                style: TextStyle(
                    color: AppTheme.accentGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('$score/3 信号',
                  style: TextStyle(
                      color: scoreColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 14),
          _SignalRow(
              label: 'PE估值合理(<25)',
              met: valuationOk,
              detail: stock.pe > 0
                  ? 'PE=${stock.pe.toStringAsFixed(1)}'
                  : 'PE数据暂无'),
          const SizedBox(height: 8),
          _SignalRow(
              label: '今日出现回调(>1.5%)',
              met: priceDropped,
              detail: Formatters.percent(stock.changePercent)),
          const SizedBox(height: 8),
          _SignalRow(
              label: '有成交量支撑',
              met: hasVolume,
              detail: Formatters.largeNumber(stock.volume)),
          if (score >= 2) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: AppTheme.accentGold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('条件较好，可考虑小批量建仓，控制仓位在总资金5%以内',
                  style: TextStyle(
                      color: AppTheme.accentGold, fontSize: 12, height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  final String label;
  final bool met;
  final String detail;
  const _SignalRow(
      {required this.label, required this.met, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(met ? Icons.check_circle : Icons.radio_button_unchecked,
          color: met ? AppTheme.primaryGreen : AppTheme.textMuted, size: 16),
      const SizedBox(width: 8),
      Expanded(
          child: Text(label,
              style: TextStyle(
                  color: met ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontSize: 13))),
      Text(detail,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
    ]);
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
