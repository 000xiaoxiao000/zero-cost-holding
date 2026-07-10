import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;

import '../models/holding_batch.dart';
import '../models/watchlist.dart';
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

  static const _intervalMinutes = 3;

  Timer? _timer;
  List<Watchlist> Function()? _watchlistGetter;
  List<HoldingPosition> Function()? _holdingGetter;
  bool _running = false;

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

  void _syncTimer() {
    final hasSources = _watchlistGetter != null || _holdingGetter != null;
    if (!hasSources) {
      stop();
      return;
    }
    if (_running) return;
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
    _watchlistGetter = null;
    _holdingGetter = null;
    _running = false;
    dev.log('AlertPollingService 已停止', name: 'AlertPollingService');
  }

  bool get isRunning => _running;

  Future<void> _poll() async {
    if (!_isTradingHours()) {
      dev.log('非交易时段，跳过轮询', name: 'AlertPollingService');
      return;
    }

    await _pollWatchlist();
    await _pollHoldings();
  }

  Future<void> _pollWatchlist() async {
    final list = _watchlistGetter?.call() ?? const <Watchlist>[];
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
        dev.log('轮询行情失败 ${item.stockCode}: $e', name: 'AlertPollingService');
      }
    }
  }

  Future<void> _pollHoldings() async {
    final positions = _holdingGetter?.call() ?? const <HoldingPosition>[];
    final alertPositions = positions.where(
      (position) =>
          position.batches.any(_needsRecoverAlert) ||
          _nextIrrigationAlert(position) != null,
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

        final irrigation = _nextIrrigationAlert(position);
        if (irrigation != null) {
          await NotificationService().checkIrrigationAndNotify(
            code: position.stockCode,
            name: position.stockName,
            planKey: irrigation.planKey,
            batchIndex: irrigation.batchIndex,
            price: stock.price,
            irrigationPrice: irrigation.price,
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

  _IrrigationAlert? _nextIrrigationAlert(HoldingPosition position) {
    final plans = <String, _IrrigationPlan>{};
    for (final batch in position.batches) {
      final plan = _IrrigationPlan.fromBatch(batch);
      if (plan == null) continue;
      final existing = plans[plan.key];
      if (existing == null ||
          plan.maxRecordedIndex > existing.maxRecordedIndex) {
        plans[plan.key] = plan;
      }
    }
    if (plans.isEmpty) return null;

    _IrrigationAlert? next;
    for (final plan in plans.values) {
      if (!plan.enabled) continue;
      final nextIndex = plan.maxRecordedIndex + 1;
      if (nextIndex > plan.seedCount) continue;
      final price =
          plan.startPrice * math.pow(1 - plan.dropStepPct / 100, nextIndex - 1);
      if (price <= 0) continue;
      final alert = _IrrigationAlert(
        planKey: plan.key,
        batchIndex: nextIndex,
        price: price.toDouble(),
      );
      if (next == null || alert.price > next.price) next = alert;
    }
    return next;
  }

  bool needsHoldingAlert(HoldingPosition position) {
    return position.batches.any(_needsRecoverAlert) ||
        _nextIrrigationAlert(position) != null;
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

class _IrrigationPlan {
  final String key;
  final double startPrice;
  final int seedCount;
  final double dropStepPct;
  final int maxRecordedIndex;
  final bool enabled;

  const _IrrigationPlan({
    required this.key,
    required this.startPrice,
    required this.seedCount,
    required this.dropStepPct,
    required this.maxRecordedIndex,
    required this.enabled,
  });

  static _IrrigationPlan? fromBatch(HoldingBatch batch) {
    final startPrice = batch.planStartPrice;
    final seedCount = batch.planSeedCount;
    final dropStepPct = batch.planDropStep;
    final index = batch.planBatchIndex;
    if (startPrice == null ||
        startPrice <= 0 ||
        seedCount == null ||
        seedCount <= 0 ||
        dropStepPct == null ||
        dropStepPct <= 0 ||
        dropStepPct >= 100 ||
        index == null ||
        index <= 0) {
      return null;
    }
    return _IrrigationPlan(
      key:
          '${batch.assetType}:${batch.market}:${batch.stockCode}:${startPrice.toStringAsFixed(4)}:${seedCount}:${dropStepPct.toStringAsFixed(4)}',
      startPrice: startPrice,
      seedCount: seedCount,
      dropStepPct: dropStepPct,
      maxRecordedIndex: index,
      enabled: batch.irrigationAlertEnabled,
    );
  }
}

class _IrrigationAlert {
  final String planKey;
  final int batchIndex;
  final double price;

  const _IrrigationAlert({
    required this.planKey,
    required this.batchIndex,
    required this.price,
  });
}
