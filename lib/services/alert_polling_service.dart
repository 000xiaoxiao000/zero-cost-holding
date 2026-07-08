import 'dart:async';
import 'dart:developer' as dev;

import '../models/watchlist.dart';
import '../services/notification_service.dart';
import '../services/stock_api_service.dart';

/// 盘中行情轮询服务 — 自动检测自选股触及目标价 / 警戒价并发送系统通知
///
/// 使用方式：
///   AlertPollingService().start(watchlistGetter: () => list);
///   AlertPollingService().stop();
///
/// 轮询间隔默认 3 分钟（行情本身有 15 分钟延迟，轮询过密无意义）。
/// 非交易时段（09:25–15:05 之外）自动跳过拉取，减少无效请求。
class AlertPollingService {
  static final AlertPollingService _instance =
      AlertPollingService._internal();
  factory AlertPollingService() => _instance;
  AlertPollingService._internal();

  static const _intervalMinutes = 3;

  Timer? _timer;
  List<Watchlist> Function()? _watchlistGetter;
  bool _running = false;

  void start({required List<Watchlist> Function() watchlistGetter}) {
    if (_running) return;
    _watchlistGetter = watchlistGetter;
    _running = true;
    // 立即执行一次，之后每隔 _intervalMinutes 分钟
    _poll();
    _timer = Timer.periodic(
      const Duration(minutes: _intervalMinutes),
      (_) => _poll(),
    );
    dev.log('AlertPollingService 已启动 (间隔 $_intervalMinutes 分钟)',
        name: 'AlertPollingService');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    dev.log('AlertPollingService 已停止', name: 'AlertPollingService');
  }

  bool get isRunning => _running;

  Future<void> _poll() async {
    if (!_isTradingHours()) {
      dev.log('非交易时段，跳过轮询', name: 'AlertPollingService');
      return;
    }

    final list = _watchlistGetter?.call() ?? [];
    final alertItems =
        list.where((w) => w.targetPrice != null || w.alertPrice != null);
    if (alertItems.isEmpty) return;

    dev.log('轮询 ${alertItems.length} 只自选股价格提醒', name: 'AlertPollingService');

    for (final item in alertItems) {
      try {
        final stock = await StockApiService()
            .fetchStockQuote(item.stockCode, item.market);
        if (stock == null || stock.price <= 0) continue;

        await NotificationService().checkAndNotify(
          code: item.stockCode,
          name: item.stockName,
          price: stock.price,
          targetPrice: item.targetPrice,
          alertPrice: item.alertPrice,
        );
      } catch (e) {
        dev.log('轮询行情失败 ${item.stockCode}: $e',
            name: 'AlertPollingService');
      }
    }
  }

  /// 是否在交易时段（09:25 ~ 15:05，含集合竞价，周一至周五）
  bool _isTradingHours() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final minutes = now.hour * 60 + now.minute;
    // 09:25 = 565, 15:05 = 905
    return minutes >= 565 && minutes <= 905;
  }
}
