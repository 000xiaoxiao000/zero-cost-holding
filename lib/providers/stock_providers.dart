import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/watchlist.dart';
import '../models/stock.dart';
import '../database/database_helper.dart';
import '../services/stock_api_service.dart';

// ── 自选股 Provider ────────────────────────────────────────────────────────────

class WatchlistNotifier extends StateNotifier<List<Watchlist>> {
  WatchlistNotifier() : super([]);

  final _db = DatabaseHelper();

  Future<void> load() async {
    final rows = await _db.getWatchlist();
    state = rows.map(Watchlist.fromMap).toList();
  }

  Future<void> add(Watchlist item) async {
    await _db.addToWatchlist(item.toMap());
    await load();
  }

  Future<void> remove(String code) async {
    await _db.removeFromWatchlist(code);
    state = state.where((w) => w.stockCode != code).toList();
  }

  Future<void> updateTargets(
      int id, double? targetPrice, double? alertPrice) async {
    await _db.updateWatchlistItem(
        id, {'target_price': targetPrice, 'alert_price': alertPrice});
    await load();
  }

  bool contains(String code) => state.any((w) => w.stockCode == code);
}

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, List<Watchlist>>(
        (ref) => WatchlistNotifier());

// ── 自选股行情 Provider ────────────────────────────────────────────────────────

final watchlistQuotesProvider =
    FutureProvider.autoDispose<Map<String, Stock>>((ref) async {
  final watchlist = ref.watch(watchlistProvider);
  if (watchlist.isEmpty) return {};
  return StockApiService().fetchBatchQuotes(watchlist);
});

// ── 市场指数 Provider ─────────────────────────────────────────────────────────

final marketIndicesProvider =
    FutureProvider.autoDispose<List<MarketIndex>>((ref) async {
  return StockApiService().fetchMarketIndices();
});

// ── 股票搜索 Provider ─────────────────────────────────────────────────────────

class StockSearchNotifier extends StateNotifier<List<Stock>> {
  StockSearchNotifier() : super([]);

  bool isLoading = false;

  Future<void> search(String keyword) async {
    if (keyword.trim().isEmpty) {
      state = [];
      return;
    }
    isLoading = true;
    final results = await StockApiService().searchByName(keyword);
    isLoading = false;
    state = results;
  }

  void clear() => state = [];
}

final stockSearchProvider =
    StateNotifierProvider<StockSearchNotifier, List<Stock>>(
        (ref) => StockSearchNotifier());

// ── 单只股票行情 Provider ──────────────────────────────────────────────────────

final stockQuoteProvider =
    FutureProvider.autoDispose.family<Stock?, (String, String)>((ref, args) {
  return StockApiService().fetchStockQuote(args.$1, args.$2);
});

// ── K线数据 Provider ──────────────────────────────────────────────────────────

final klineProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String, String)>((ref, args) {
  return StockApiService().fetchKlineDaily(args.$1, args.$2);
});

// ── 北向资金 Provider ─────────────────────────────────────────────────────────

final northboundProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return StockApiService().fetchNorthboundFlow();
});
