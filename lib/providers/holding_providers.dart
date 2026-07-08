import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/holding_batch.dart';
import '../database/database_helper.dart';

class HoldingPositionsNotifier
    extends StateNotifier<Map<String, List<HoldingBatch>>> {
  HoldingPositionsNotifier() : super({});

  final _db = DatabaseHelper();

  Future<void> load() async {
    final result = <String, List<HoldingBatch>>{};
    final rows = await _db.getHoldingBatches();
    for (final batch in rows.map(HoldingBatch.fromMap)) {
      final key = '${batch.assetType}:${batch.stockCode}';
      result.putIfAbsent(key, () => []).add(batch);
    }
    state = result;
  }

  Future<void> addBatch(HoldingBatch batch) async {
    await _db.addHoldingBatch(batch.toMap());
    await load();
  }

  Future<void> recordSell(
      int batchId, String code, double sellPrice, double sellQty) async {
    await _db.updateHoldingBatch(batchId, {
      'sell_price': sellPrice,
      'sell_quantity': sellQty,
      'sell_date': DateTime.now().toIso8601String(),
    });
    await load();
  }

  Future<void> recordCashIncome(int batchId, double cashIncome) async {
    await _db.updateHoldingBatch(batchId, {
      'cash_income': cashIncome,
    });
    await load();
  }

  Future<void> deleteBatch(int id) async {
    await _db.deleteHoldingBatch(id);
    await load();
  }

  Future<void> deletePosition({
    required String assetType,
    required String stockCode,
  }) async {
    await _db.deleteHoldingBatchesForAsset(
      assetType: assetType,
      stockCode: stockCode,
    );
    await load();
  }

  List<HoldingPosition> get holdings {
    return state.entries.map((entry) {
      final batches = entry.value;
      final name = batches.isNotEmpty ? batches.first.stockName : entry.key;
      final first = batches.isNotEmpty ? batches.first : null;
      return HoldingPosition(
        assetType: first?.assetType ?? 'stock',
        stockCode: first?.stockCode ?? entry.key,
        stockName: name,
        batches: batches,
      );
    }).toList();
  }

  double get totalInvested => holdings.fold(0.0, (s, h) => s + h.totalInvested);

  double get totalRecovered =>
      holdings.fold(0.0, (s, h) => s + h.totalRecovered);
}

final holdingPositionsProvider = StateNotifierProvider<HoldingPositionsNotifier,
    Map<String, List<HoldingBatch>>>((ref) => HoldingPositionsNotifier());
