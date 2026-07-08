import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'stock_holding.db');
    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _ensureSchema,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE watchlist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL DEFAULT 'SH',
        added_at TEXT NOT NULL,
        note TEXT,
        target_price REAL,
        alert_price REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE holding_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_type TEXT NOT NULL DEFAULT 'stock',
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        buy_price REAL NOT NULL,
        quantity REAL NOT NULL,
        commission REAL DEFAULT 0.0,
        buy_date TEXT NOT NULL,
        note TEXT,
        cash_income REAL DEFAULT 0.0,
        sell_price REAL,
        sell_quantity REAL,
        sell_date TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_holding_batches_code ON holding_batches(stock_code)
    ''');

    await db.execute('''
      CREATE INDEX idx_watchlist_code ON watchlist(stock_code)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(
        db,
        table: 'holding_batches',
        column: 'asset_type',
        definition: "TEXT NOT NULL DEFAULT 'stock'",
      );
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(
        db,
        table: 'holding_batches',
        column: 'cash_income',
        definition: 'REAL DEFAULT 0.0',
      );
    }
  }

  Future<void> _ensureSchema(Database db) async {
    await _addColumnIfMissing(
      db,
      table: 'holding_batches',
      column: 'asset_type',
      definition: "TEXT NOT NULL DEFAULT 'stock'",
    );
    await _addColumnIfMissing(
      db,
      table: 'holding_batches',
      column: 'cash_income',
      definition: 'REAL DEFAULT 0.0',
    );
  }

  Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  // ── Watchlist CRUD ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getWatchlist() async {
    final db = await database;
    return db.query('watchlist', orderBy: 'added_at DESC');
  }

  Future<int> addToWatchlist(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('watchlist', data,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> isInWatchlist(String code) async {
    final db = await database;
    final res = await db.query('watchlist',
        where: 'stock_code = ?', whereArgs: [code], limit: 1);
    return res.isNotEmpty;
  }

  Future<int> removeFromWatchlist(String code) async {
    final db = await database;
    return db.delete('watchlist', where: 'stock_code = ?', whereArgs: [code]);
  }

  Future<int> updateWatchlistItem(int id, Map<String, dynamic> data) async {
    final db = await database;
    return db.update('watchlist', data, where: 'id = ?', whereArgs: [id]);
  }

  // ── HoldingBatch CRUD ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getHoldingBatches({
    String? stockCode,
  }) async {
    final db = await database;
    if (stockCode != null) {
      return db.query('holding_batches',
          where: 'stock_code = ?',
          whereArgs: [stockCode],
          orderBy: 'buy_date DESC');
    }
    return db.query('holding_batches', orderBy: 'buy_date DESC');
  }

  Future<List<String>> getDistinctHoldingCodes() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT DISTINCT stock_code FROM holding_batches');
    return result.map((r) => r['stock_code'] as String).toList();
  }

  Future<int> addHoldingBatch(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('holding_batches', data);
  }

  Future<int> updateHoldingBatch(int id, Map<String, dynamic> data) async {
    final db = await database;
    return db.update('holding_batches', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteHoldingBatch(int id) async {
    final db = await database;
    return db.delete('holding_batches', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteHoldingBatchesForAsset({
    required String assetType,
    required String stockCode,
  }) async {
    final db = await database;
    return db.delete(
      'holding_batches',
      where: 'asset_type = ? AND stock_code = ?',
      whereArgs: [assetType, stockCode],
    );
  }
}
