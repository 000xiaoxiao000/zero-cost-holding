import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/stock_providers.dart';
import '../models/stock.dart';
import '../models/watchlist.dart';
import 'stock_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(stockSearchProvider);
    final watchlist = ref.watch(watchlistProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: (v) => ref.read(stockSearchProvider.notifier).search(v),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: '搜索股票名称或代码',
            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 15),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            fillColor: Colors.transparent,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear,
                        color: AppTheme.textMuted, size: 18),
                    onPressed: () {
                      _controller.clear();
                      ref.read(stockSearchProvider.notifier).clear();
                    },
                  )
                : null,
          ),
        ),
      ),
      body: results.isEmpty
          ? const _SearchHint()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final stock = results[i];
                final inWatchlist =
                    watchlist.any((w) => w.stockCode == stock.code);
                return _SearchResultTile(
                  stock: stock,
                  isInWatchlist: inWatchlist,
                  onAdd: inWatchlist
                      ? null
                      : () async {
                          await ref.read(watchlistProvider.notifier).add(
                                Watchlist(
                                  stockCode: stock.code,
                                  stockName: stock.name,
                                  market: stock.market,
                                ),
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已添加 ${stock.name}'),
                                backgroundColor: AppTheme.bgCard,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StockDetailScreen(
                        code: stock.code,
                        name: stock.name,
                        market: stock.market,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Stock stock;
  final bool isInWatchlist;
  final VoidCallback? onAdd;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.stock,
    required this.isInWatchlist,
    required this.onAdd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.bgCardLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            stock.code.length >= 2 ? stock.code.substring(0, 2) : stock.code,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      title: Text(stock.name,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500)),
      subtitle: Row(
        children: [
          _MarketBadge(market: stock.market),
          const SizedBox(width: 6),
          Text(stock.code,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
      trailing: isInWatchlist
          ? const Icon(Icons.check_circle,
              color: AppTheme.primaryGreen, size: 22)
          : IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  color: AppTheme.accent, size: 22),
              onPressed: onAdd,
            ),
    );
  }
}

class _MarketBadge extends StatelessWidget {
  final String market;
  const _MarketBadge({required this.market});

  @override
  Widget build(BuildContext context) {
    final Color color = market == 'SH'
        ? AppTheme.accentGold
        : market == 'BJ'
            ? AppTheme.accent
            : AppTheme.primaryGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        market,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.search, color: AppTheme.textMuted, size: 48),
          SizedBox(height: 12),
          Text('输入股票名称或代码搜索',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          SizedBox(height: 6),
          Text('例如：贵州茅台 / 600519',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
