import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/watchlist.dart';
import '../models/stock.dart';
import '../models/dividend_financing.dart';
import '../database/database_helper.dart';
import '../services/stock_api_service.dart';
import '../services/alert_polling_service.dart';
import '../services/notification_service.dart';
import '../services/atr_service.dart';

// ── 自选股 Provider ────────────────────────────────────────────────────────────

class WatchlistNotifier extends StateNotifier<List<Watchlist>> {
  WatchlistNotifier() : super([]);

  final _db = DatabaseHelper();

  Future<void> load() async {
    final rows = await _db.getWatchlist();
    state = rows.map(Watchlist.fromMap).toList();
    _syncPolling();
  }

  Future<void> add(Watchlist item) async {
    await _db.addToWatchlist(item.toMap());
    await load();
  }

  Future<void> remove(String code) async {
    await _db.removeFromWatchlist(code);
    state = state.where((w) => w.stockCode != code).toList();
    _syncPolling();
  }

  Future<void> updateTargets(
      int id, double? targetPrice, double? alertPrice) async {
    await _db.updateWatchlistItem(
        id, {'target_price': targetPrice, 'alert_price': alertPrice});
    await load();
  }

  bool contains(String code) => state.any((w) => w.stockCode == code);

  /// 有任意一只股票设置了目标价或警戒价时启动后台轮询
  void _syncPolling() {
    final hasAlerts =
        state.any((w) => w.targetPrice != null || w.alertPrice != null);
    final polling = AlertPollingService();
    if (hasAlerts) {
      polling.updateWatchlist(watchlistGetter: () => state);
    } else {
      polling.updateWatchlist();
    }
  }
}

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, List<Watchlist>>(
        (ref) => WatchlistNotifier());

// ── 自选股行情 Provider（含通知检查）────────────────────────────────────────────

final watchlistQuotesProvider =
    FutureProvider.autoDispose<Map<String, Stock>>((ref) async {
  final watchlist = ref.watch(watchlistProvider);
  if (watchlist.isEmpty) return {};
  final quotes = await StockApiService().fetchBatchQuotes(watchlist);

  for (final item in watchlist) {
    final stock = quotes[item.stockCode];
    if (stock == null || stock.price <= 0) continue;
    await NotificationService().checkAndNotify(
      code: item.stockCode,
      name: item.stockName,
      price: stock.price,
      targetPrice: item.targetPrice,
      alertPrice: item.alertPrice,
    );
  }
  return quotes;
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
  Timer? _debounce;
  int _seq = 0;

  /// 防抖搜索：连续输入时仅在停顿 350ms 后发起一次网络请求，
  /// 并用序号丢弃过期响应，避免快慢请求乱序覆盖结果。
  void search(String keyword) {
    _debounce?.cancel();
    final kw = keyword.trim();
    if (kw.isEmpty) {
      isLoading = false;
      state = [];
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(kw));
  }

  Future<void> _run(String keyword) async {
    final seq = ++_seq;
    isLoading = true;
    final results = await StockApiService().searchByName(keyword);
    if (seq != _seq) return;
    isLoading = false;
    state = results;
  }

  void clear() {
    _debounce?.cancel();
    _seq++;
    state = [];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
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

// ── 分红 & 融资 Provider ──────────────────────────────────────────────────────

final dividendFinancingProvider = FutureProvider.autoDispose
    .family<DividendFinancingData, (String, String)>((ref, args) {
  return StockApiService().fetchDividendFinancing(args.$1, args.$2);
});

// ── 北向资金 Provider ─────────────────────────────────────────────────────────

final northboundProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return StockApiService().fetchNorthboundFlow();
});

// ── ATR Provider（14日 Wilder ATR，从 60 根日K自动计算）──────────────────────

final atrProvider = FutureProvider.autoDispose
    .family<double?, (String, String)>((ref, args) async {
  final klines =
      await StockApiService().fetchKlineDaily(args.$1, args.$2, limit: 60);
  return AtrService.calculate(klines);
});

// ── 吊灯止盈参考高点 Provider（近 22 日最高价，从日K计算）───────────────────────

final recentHighProvider = FutureProvider.autoDispose
    .family<double?, (String, String)>((ref, args) async {
  final klines =
      await StockApiService().fetchKlineDaily(args.$1, args.$2, limit: 60);
  if (klines.isEmpty) return null;
  final window =
      klines.length >= 22 ? klines.sublist(klines.length - 22) : klines;
  double? high;
  for (final k in window) {
    final h = k['high'];
    final v = h is num ? h.toDouble() : double.tryParse('${h ?? ''}');
    if (v != null && (high == null || v > high)) high = v;
  }
  return high;
});
