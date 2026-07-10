import 'dart:async';
import 'dart:developer' as dev;
import '../models/holding_batch.dart';
import '../models/watchlist.dart';
import '../services/alert_polling_config_service.dart';
import '../services/notification_service.dart';
import '../services/stock_api_service.dart';

/// 盘中行情轮询服务 — 自动检测自选股与播种账本触价提醒并发送系统通知
///
/// 使用方式：
///   AlertPollingService().updateWatchlist(watchlistGetter: () => list);
///   AlertPollingService().updateHoldings(holdingGetter: () => positions);
///
/// 轮询间隔默认 3 分钟（行情本身有 15 分钟延迟，轮询过密无意义）。
/// 非交易时段（09:25–15:05 之外）自动跳过拉取，减少无效请求。
class AlertPollingService {
  static final AlertPollingService _instance = AlertPollingService._internal();
  factory AlertPollingService() => _instance;
  AlertPollingService._internal();

  Timer? _timer;
  List<Watchlist> Function()? _watchlistGetter;
  List<HoldingPosition> Function()? _holdingGetter;
  bool _running = false;
  AlertPollingConfig? _activeConfig;

  void start({required List<Watchlist> Function() watchlistGetter}) {
    updateWatchlist(watchlistGetter: watchlistGetter);
  }

  void updateWatchlist({List<Watchlist> Function()? watchlistGetter}) {
    _watchlistGetter = watchlistGetter;
    _syncTimer();
  }

  void updateHoldings({List<HoldingPosition> Function()? holdingGetter}) {
    _holdingGetter = holdingGetter;
    _syncTimer();
  }

  Future<void> _syncTimer() async {
    final hasSources = _watchlistGetter != null || _holdingGetter != null;
    if (!hasSources) {
      stop();
      return;
    }

    final previousConfig = _activeConfig;
    final config = await AlertPollingConfigService().load();
    _activeConfig = config;
    if (!config.enabled) {
      _cancelTimer();
      dev.log('AlertPollingService 已暂停：全局轮询关闭', name: 'AlertPollingService');
      return;
    }

    if (_running) {
      final timerInterval = previousConfig?.intervalMinutes;
      if (timerInterval == config.intervalMinutes) return;
      _cancelTimer();
    }

    _running = true;
    // 立即执行一次，之后按配置间隔轮询。
    _poll();
    _timer = Timer.periodic(
      config.interval,
      (_) => _poll(),
    );
    dev.log('AlertPollingService 已启动 (间隔 ${config.intervalMinutes} 分钟)',
        name: 'AlertPollingService');
  }

  void stop() {
    _cancelTimer();
    _watchlistGetter = null;
    _holdingGetter = null;
    dev.log('AlertPollingService 已停止', name: 'AlertPollingService');
  }

  Future<void> refreshConfig() async {
    if (_watchlistGetter == null && _holdingGetter == null) {
      _activeConfig = await AlertPollingConfigService().load();
      return;
    }
    _cancelTimer();
    await _syncTimer();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  bool get isRunning => _running;

  Future<void> _poll() async {
    final config = _activeConfig ?? await AlertPollingConfigService().load();
    _activeConfig = config;
    if (!_isTradingHours(config)) {
      dev.log('非交易时段，跳过轮询', name: 'AlertPollingService');
      return;
    }

    await _pollWatchlist();
    await _pollHoldings();
  }

  Future<void> _pollWatchlist() async {
    final list = _watchlistGetter?.call() ?? const <Watchlist>[];
    final alertItems = list.where((w) =>
        w.alertsEnabled && (w.targetPrice != null || w.alertPrice != null));
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
        dev.log('轮询行情失败 ${item.stockCode}: $e', name: 'AlertPollingService');
      }
    }
  }

  Future<void> _pollHoldings() async {
    final positions = _holdingGetter?.call() ?? const <HoldingPosition>[];
    final alertPositions = positions.where(
      (position) =>
          position.batches.any(_needsRecoverAlert) ||
          position.batches.any(_needsZeroCostAlert) ||
          position.batches.any(_needsIrrigationAlert),
    );
    if (alertPositions.isEmpty) return;

    dev.log('轮询 ${alertPositions.length} 个持仓计划提醒', name: 'AlertPollingService');

    for (final position in alertPositions) {
      try {
        final stock = await StockApiService()
            .fetchStockQuote(position.stockCode, position.market);
        if (stock == null || stock.price <= 0) continue;

        for (final batch in position.batches.where(_needsRecoverAlert)) {
          await NotificationService().checkRecoverAndNotify(
            code: batch.stockCode,
            name: batch.stockName,
            batchId: batch.id!,
            price: stock.price,
            recoverPrice: batch.planRecoverPrice!,
            recoverQuantity: batch.planRecoverQuantity,
            quantityUnit: batch.quantityUnit,
          );
        }

        for (final batch in position.batches.where(_needsZeroCostAlert)) {
          await NotificationService().checkZeroCostAndNotify(
            code: batch.stockCode,
            name: batch.stockName,
            batchId: batch.id!,
            price: stock.price,
            triggerPrice: batch.zeroCostAlertPrice!,
            sellQuantity: batch.zeroCostAlertQuantity,
            quantityUnit: batch.quantityUnit,
          );
        }

        for (final batch in position.batches.where(_needsIrrigationAlert)) {
          await NotificationService().checkIrrigationAndNotify(
            code: batch.stockCode,
            name: batch.stockName,
            planKey: 'batch:${batch.id}',
            batchIndex: batch.planBatchIndex ?? 0,
            price: stock.price,
            irrigationPrice: batch.irrigationAlertPrice!,
          );
        }
      } catch (e) {
        dev.log('轮询持仓计划提醒失败 ${position.stockCode}: $e',
            name: 'AlertPollingService');
      }
    }
  }

  bool _needsRecoverAlert(HoldingBatch batch) {
    final price = batch.planRecoverPrice;
    return batch.id != null &&
        batch.recoverAlertEnabled &&
        price != null &&
        price > 0 &&
        batch.remainingQuantity > 0 &&
        !batch.isZeroCost;
  }

  bool _needsZeroCostAlert(HoldingBatch batch) {
    final price = batch.zeroCostAlertPrice;
    final quantity = batch.zeroCostAlertQuantity;
    return batch.id != null &&
        batch.zeroCostAlertEnabled &&
        price != null &&
        price > 0 &&
        quantity != null &&
        quantity > 0 &&
        batch.remainingQuantity > 0 &&
        !batch.isZeroCost;
  }

  bool _needsIrrigationAlert(HoldingBatch batch) {
    final price = batch.irrigationAlertPrice;
    final quantity = batch.irrigationAlertQuantity;
    return batch.id != null &&
        batch.irrigationAlertEnabled &&
        price != null &&
        price > 0 &&
        quantity != null &&
        quantity > 0 &&
        batch.remainingQuantity > 0;
  }

  bool needsHoldingAlert(HoldingPosition position) {
    return position.batches.any(_needsRecoverAlert) ||
        position.batches.any(_needsZeroCostAlert) ||
        position.batches.any(_needsIrrigationAlert);
  }

  /// 是否在交易时段（09:25 ~ 15:05，含集合竞价，周一至周五）
  bool _isTradingHours(AlertPollingConfig config) {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final minutes = now.hour * 60 + now.minute;
    return minutes >= config.startMinutes && minutes <= config.endMinutes;
  }
}
