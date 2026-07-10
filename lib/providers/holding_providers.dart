import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/holding_batch.dart';
import '../database/database_helper.dart';
import '../services/alert_polling_service.dart';

class HoldingPositionsNotifier
    extends StateNotifier<Map<String, List<HoldingBatch>>> {
  HoldingPositionsNotifier() : super({});

  final _db = DatabaseHelper();
  Map<String, HoldingLedger> _ledgers = {};

  Future<void> load() async {
    final result = <String, List<HoldingBatch>>{};
    final ledgers = <String, HoldingLedger>{};
    final ledgerRows = await _db.getHoldingLedgers();
    for (final ledger in ledgerRows.map(HoldingLedger.fromMap)) {
      ledgers[ledger.key] = ledger;
    }
    final rows = await _db.getHoldingBatches();
    for (final batch in rows.map(HoldingBatch.fromMap)) {
      final key = '${batch.assetType}:${batch.market}:${batch.stockCode}';
      ledgers.putIfAbsent(
        key,
        () => HoldingLedger(
          assetType: batch.assetType,
          market: batch.market,
          stockCode: batch.stockCode,
          stockName: batch.stockName,
          createdAt: batch.buyDate,
        ),
      );
      result.putIfAbsent(key, () => []).add(batch);
    }
    _ledgers = ledgers;
    state = result;
    _syncRecoverPolling();
  }

  Future<void> addBatch(HoldingBatch batch) async {
    await _db.addHoldingBatch(batch.toMap());
    await load();
  }

  Future<void> recordSell(
    int batchId,
    double sellPrice,
    double sellQty, {
    bool replace = false,
    DateTime? sellDate,
  }) async {
    HoldingBatch? existing;
    for (final batches in state.values) {
      for (final batch in batches) {
        if (batch.id == batchId) {
          existing = batch;
          break;
        }
      }
      if (existing != null) break;
    }
    final previousQty = replace ? 0.0 : existing?.sellQuantity ?? 0.0;
    final previousAmount =
        replace ? 0.0 : (existing?.sellPrice ?? 0.0) * previousQty;
    final maxQty = existing?.quantity ?? double.infinity;
    final nextQty = (previousQty + sellQty).clamp(0.0, maxQty);
    final nextAmount = previousAmount + sellPrice * sellQty;
    final nextPrice = nextQty > 0 ? nextAmount / nextQty : sellPrice;
    await _db.updateHoldingBatch(batchId, {
      'sell_price': nextPrice,
      'sell_quantity': nextQty,
      'sell_date': (sellDate ?? DateTime.now()).toIso8601String(),
    });
    await load();
  }

  Future<void> recordCashIncome(int batchId, double cashIncome) async {
    await _db.updateHoldingBatch(batchId, {
      'cash_income': cashIncome,
    });
    await load();
  }

  Future<void> updateBatchAlertToggles(
    int batchId, {
    bool? recoverAlertEnabled,
    bool? zeroCostAlertEnabled,
    bool? irrigationAlertEnabled,
  }) async {
    final data = <String, dynamic>{};
    if (recoverAlertEnabled != null) {
      data['recover_alert_enabled'] = recoverAlertEnabled ? 1 : 0;
    }
    if (zeroCostAlertEnabled != null) {
      data['zero_cost_alert_enabled'] = zeroCostAlertEnabled ? 1 : 0;
    }
    if (irrigationAlertEnabled != null) {
      data['irrigation_alert_enabled'] = irrigationAlertEnabled ? 1 : 0;
    }
    if (data.isEmpty) return;
    await _db.updateHoldingBatch(batchId, data);
    await load();
  }

  Future<void> updateBatchHarvestAlerts(
    int batchId, {
    required double? zeroCostAlertPrice,
    required double? zeroCostAlertQuantity,
    required double? irrigationAlertPrice,
    required double? irrigationAlertQuantity,
  }) async {
    await _db.updateHoldingBatch(batchId, {
      'zero_cost_alert_price': zeroCostAlertPrice,
      'zero_cost_alert_quantity': zeroCostAlertQuantity,
      'irrigation_alert_price': irrigationAlertPrice,
      'irrigation_alert_quantity': irrigationAlertQuantity,
    });
    await load();
  }

  Future<void> deleteBatch(int id) async {
    await _db.deleteHoldingBatch(id);
    await load();
  }

  Future<void> deletePosition({
    required String assetType,
    required String market,
    required String stockCode,
  }) async {
    await _db.deleteHoldingBatchesForAsset(
      assetType: assetType,
      market: market,
      stockCode: stockCode,
    );
    await _db.deleteHoldingLedger(
      assetType: assetType,
      market: market,
      stockCode: stockCode,
    );
    await load();
  }

  List<HoldingPosition> get holdings {
    final keys = <String>{..._ledgers.keys, ...state.keys};
    return keys.map((key) {
      final batches = state[key] ?? const <HoldingBatch>[];
      final ledger = _ledgers[key];
      final name = batches.isNotEmpty
          ? batches.first.stockName
          : ledger?.stockName ?? key;
      final first = batches.isNotEmpty ? batches.first : null;
      return HoldingPosition(
        assetType: first?.assetType ?? ledger?.assetType ?? 'stock',
        market: first?.market ?? ledger?.market ?? 'SH',
        stockCode: first?.stockCode ?? ledger?.stockCode ?? key,
        stockName: name,
        batches: batches,
      );
    }).toList();
  }

  double get totalInvested => holdings.fold(0.0, (s, h) => s + h.totalInvested);

  double get totalRecovered =>
      holdings.fold(0.0, (s, h) => s + h.totalRecovered);

  void _syncRecoverPolling() {
    final polling = AlertPollingService();
    final hasHoldingAlerts = holdings.any(polling.needsHoldingAlert);
    if (hasHoldingAlerts) {
      polling.updateHoldings(holdingGetter: () => holdings);
    } else {
      polling.updateHoldings();
    }
  }
}

final holdingPositionsProvider = StateNotifierProvider<HoldingPositionsNotifier,
    Map<String, List<HoldingBatch>>>((ref) => HoldingPositionsNotifier());
