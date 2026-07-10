import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../providers/stock_providers.dart';
import '../models/watchlist.dart';
import '../models/stock.dart';
import 'stock_detail_screen.dart';

Future<void> _showAlertEditor(
  BuildContext context,
  WidgetRef ref,
  Watchlist item,
) async {
  if (item.id == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('自选股数据未完成保存，请稍后再试')),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (_) => _AlertEditorDialog(item: item),
  );
}

class _AlertEditorDialog extends ConsumerStatefulWidget {
  final Watchlist item;

  const _AlertEditorDialog({required this.item});

  @override
  ConsumerState<_AlertEditorDialog> createState() => _AlertEditorDialogState();
}

class _AlertEditorDialogState extends ConsumerState<_AlertEditorDialog> {
  late final TextEditingController _targetController;
  late final TextEditingController _alertController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _targetController = TextEditingController(
      text: widget.item.targetPrice != null
          ? widget.item.targetPrice!.toStringAsFixed(3)
          : '',
    );
    _alertController = TextEditingController(
      text: widget.item.alertPrice != null
          ? widget.item.alertPrice!.toStringAsFixed(3)
          : '',
    );
  }

  @override
  void dispose() {
    _targetController.dispose();
    _alertController.dispose();
    super.dispose();
  }

  double? _parsePrice(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value.replaceAll(',', ''));
  }

  Future<void> _save() async {
    final target = _parsePrice(_targetController.text);
    final alert = _parsePrice(_alertController.text);
    final targetInvalid =
        _targetController.text.trim().isNotEmpty && target == null;
    final alertInvalid =
        _alertController.text.trim().isNotEmpty && alert == null;
    if (targetInvalid || alertInvalid) {
      setState(() => _errorText = '请输入有效价格，或留空关闭对应提醒');
      return;
    }
    if ((target != null && target <= 0) || (alert != null && alert <= 0)) {
      setState(() => _errorText = '提醒价格必须大于 0');
      return;
    }

    await ref
        .read(watchlistProvider.notifier)
        .updateTargets(widget.item.id!, target, alert);
    ref.invalidate(watchlistQuotesProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: Text('${widget.item.stockName} 提醒价'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _targetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '目标价',
              hintText: '涨到此价格提醒收割',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _alertController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '警戒价',
              hintText: '跌到此价格提醒关注',
              prefixIcon: Icon(Icons.warning_amber_outlined),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _errorText!,
                style: const TextStyle(
                  color: AppTheme.riskRed,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _targetController.clear();
            _alertController.clear();
            setState(() => _errorText = null);
          },
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  @override
  Widget build(BuildContext context) {
    final watchlist = ref.watch(watchlistProvider);
    final quotesAsync = ref.watch(watchlistQuotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('自选股'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.pushNamed(context, '/search'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: watchlist.isEmpty
          ? const _EmptyWatchlist()
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(watchlistQuotesProvider),
              color: AppTheme.accent,
              backgroundColor: AppTheme.bgCard,
              child: quotesAsync.when(
                data: (quotes) => _WatchlistList(
                  watchlist: watchlist,
                  quotes: quotes,
                ),
                loading: () => _WatchlistList(
                  watchlist: watchlist,
                  quotes: {},
                  isLoading: true,
                ),
                error: (_, __) => _WatchlistList(
                  watchlist: watchlist,
                  quotes: {},
                ),
              ),
            ),
    );
  }
}

class _WatchlistList extends ConsumerWidget {
  final List<Watchlist> watchlist;
  final Map<String, Stock> quotes;
  final bool isLoading;

  const _WatchlistList({
    required this.watchlist,
    required this.quotes,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: watchlist.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final item = watchlist[i];
        final stock = quotes[item.stockCode];
        return _WatchlistTile(
          item: item,
          stock: stock,
          isLoading: isLoading,
          onRemove: () =>
              ref.read(watchlistProvider.notifier).remove(item.stockCode),
          onEditAlerts: () => _showAlertEditor(context, ref, item),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StockDetailScreen(
                code: item.stockCode,
                name: item.stockName,
                market: item.market,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WatchlistTile extends StatelessWidget {
  final Watchlist item;
  final Stock? stock;
  final bool isLoading;
  final VoidCallback onRemove;
  final VoidCallback onEditAlerts;
  final VoidCallback onTap;

  const _WatchlistTile({
    required this.item,
    required this.stock,
    required this.isLoading,
    required this.onRemove,
    required this.onEditAlerts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = stock?.price ?? 0.0;
    final pct = stock?.changePercent ?? 0.0;
    final priceColor = pct >= 0 ? AppTheme.accentGold : AppTheme.primaryGreen;
    final hasAlerts = item.targetPrice != null || item.alertPrice != null;

    return Dismissible(
      key: Key(item.stockCode),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.riskRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            const Icon(Icons.delete_outline, color: AppTheme.riskRed, size: 22),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor, width: 0.5),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _StockAvatar(code: item.stockCode),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.stockName,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            _MarketTag(market: item.market),
                            const SizedBox(width: 6),
                            Text(item.stockCode,
                                style: const TextStyle(
                                    color: AppTheme.textMuted, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '设置提醒',
                    icon: Icon(
                      hasAlerts
                          ? Icons.notifications_active
                          : Icons.notifications_none_outlined,
                      color:
                          hasAlerts ? AppTheme.accentGold : AppTheme.textMuted,
                      size: 21,
                    ),
                    onPressed: onEditAlerts,
                  ),
                  if (isLoading)
                    Container(
                      width: 70,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.bgCardLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          price > 0 ? Formatters.price(price) : '--',
                          style: TextStyle(
                            color: priceColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: priceColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            price > 0 ? Formatters.percent(pct) : '--',
                            style: TextStyle(
                                color: priceColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (hasAlerts) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (item.targetPrice != null)
                      _AlertChip(
                        icon: Icons.flag_outlined,
                        label: '目标 ¥${Formatters.price(item.targetPrice!)}',
                        color: AppTheme.accentGold,
                      ),
                    if (item.targetPrice != null && item.alertPrice != null)
                      const SizedBox(width: 8),
                    if (item.alertPrice != null)
                      _AlertChip(
                        icon: Icons.warning_amber_outlined,
                        label: '警戒 ¥${Formatters.price(item.alertPrice!)}',
                        color: AppTheme.riskRed,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _AlertChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.28), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockAvatar extends StatelessWidget {
  final String code;
  const _StockAvatar({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.bgCardLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Center(
        child: Text(
          code.length >= 2 ? code.substring(0, 2) : code,
          style: const TextStyle(
            color: AppTheme.accent,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MarketTag extends StatelessWidget {
  final String market;
  const _MarketTag({required this.market});

  @override
  Widget build(BuildContext context) {
    final isSH = market == 'SH';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: (isSH ? AppTheme.accentGold : AppTheme.primaryGreen)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        market,
        style: TextStyle(
          color: isSH ? AppTheme.accentGold : AppTheme.primaryGreen,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyWatchlist extends StatelessWidget {
  const _EmptyWatchlist();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmark_add_outlined,
              color: AppTheme.textMuted, size: 56),
          const SizedBox(height: 16),
          const Text('还没有自选股',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text('点击右上角 + 搜索添加',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/search'),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('搜索股票'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              side: const BorderSide(color: AppTheme.accent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
