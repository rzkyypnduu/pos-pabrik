import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/oil_stock.dart';
import '../models/stock_management.dart';
import '../models/stock_remaining.dart';
import '../models/customer_ledger.dart';
import '../models/personal_ledger.dart';
import '../models/saldo_deduction.dart';
import '../models/expense.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  static void initialize() {
    if (kIsWeb) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<String> getDatabaseFilePath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = await getApplicationDocumentsDirectory();
      return join(dir.path, 'pos_krupuk', 'pos_krupuk.db');
    } else {
      final dbPath = await getDatabasesPath();
      return join(dbPath, 'pos_krupuk.db');
    }
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      final db = _database!;
      _database = null;
      await db.close();
    }
  }

  Future<String> exportDatabase(String destPath) async {
    await closeDatabase();
    final src = await getDatabaseFilePath();
    if (!File(src).existsSync()) {
      throw Exception('Database belum ditemukan');
    }
    await File(src).copy(destPath);
    await database;
    return destPath;
  }

  Future<Uint8List> exportDatabaseBytes() async {
    await closeDatabase();
    final src = await getDatabaseFilePath();
    if (!File(src).existsSync()) {
      throw Exception('Database belum ditemukan');
    }
    final bytes = await File(src).readAsBytes();
    await database;
    return bytes;
  }

  Future<void> shutdownExport(String destPath) async {
    await closeDatabase();
    final src = await getDatabaseFilePath();
    if (!File(src).existsSync()) {
      throw Exception('Database belum ditemukan');
    }
    await File(src).copy(destPath);
  }

  Future<bool> importDatabase(String srcPath) async {
    if (!File(srcPath).existsSync()) {
      throw Exception('File tidak ditemukan');
    }
    await closeDatabase();
    final dest = await getDatabaseFilePath();
    await Directory(dirname(dest)).create(recursive: true);
    await File(srcPath).copy(dest);
    await database;
    return true;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_krupuk.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (kIsWeb) {
      path = filePath;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = await getApplicationDocumentsDirectory();
      path = join(dir.path, 'pos_krupuk', filePath);
      await Directory(join(dir.path, 'pos_krupuk')).create(recursive: true);
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }
    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  String _now() => DateTime.now().toIso8601String();

  static final Uuid _uuidGen = Uuid();
  String newUuid() => _uuidGen.v4();

  // ==================== SYNC INFRASTRUCTURE ====================

  Future<void> _enqueueOutbox(
    String table,
    String operation,
    Map<String, dynamic> row,
    String rowUuid,
  ) async {
    final db = await database;
    final payload = await _remotePayloadFor(table, row);
    payload['id'] = rowUuid;
    await db.insert('outbox', {
      'table_name': table,
      'operation': operation,
      'payload': jsonEncode(payload),
      'created_at': _now(),
    });
  }

  /// Ubah baris lokal menjadi payload siap-upload (kolom remote):
  /// buang id lokal/created_at/updated_at, ganti FK int -> uuid.
  Future<Map<String, dynamic>> _remotePayloadFor(
    String table,
    Map<String, dynamic> row,
  ) async {
    final p = Map<String, dynamic>.from(row);
    p.remove('id');
    p.remove('created_at');
    p.remove('updated_at');
    p.remove('deleted_at');
    p.remove('uuid');
    if (table == 'sale_items') {
      final sid = p.remove('sale_id');
      if (sid != null && sid is int) {
        final rows = await database.then(
          (d) => d.query('sales', columns: ['uuid'], where: 'id = ?', whereArgs: [sid]),
        );
        final saleUuid = rows.isEmpty ? null : rows.first['uuid'] as String?;
        p['sale_id'] = saleUuid;
      }
      final pid = p.remove('product_id');
      if (pid != null && pid is int) {
        final rows = await database.then(
          (d) => d.query('products', columns: ['uuid'], where: 'id = ?', whereArgs: [pid]),
        );
        final productUuid = rows.isEmpty ? null : rows.first['uuid'] as String?;
        p['product_id'] = productUuid;
      }
    } else if (table == 'customer_ledgers') {
      final sid = p.remove('sale_id');
      if (sid != null && sid is int) {
        final rows = await database.then(
          (d) => d.query('sales', columns: ['uuid'], where: 'id = ?', whereArgs: [sid]),
        );
        final saleUuid = rows.isEmpty ? null : rows.first['uuid'] as String?;
        p['sale_id'] = saleUuid;
      }
    }
    return p;
  }

  Future<String?> _uuidOf(String table, int id) async {
    final db = await database;
    final rows = await db.query(
      table,
      columns: ['uuid'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['uuid'] as String?;
  }

  Future<void> _enqueueDeleteById(String table, int id) async {
    final u = await _uuidOf(table, id);
    if (u == null) return;
    await _enqueueOutbox(table, 'delete', {}, u);
  }

  Future<void> _enqueueRow(String table, String operation, int id) async {
    final db = await database;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final uuid = rows.first['uuid'] as String?;
    if (uuid == null) return;
    await _enqueueOutbox(table, operation, rows.first, uuid);
  }

  Future<void> _enqueueBulkDelete(
    String table,
    String? where,
    List<Object?>? whereArgs,
  ) async {
    final db = await database;
    final rows = await db.query(
      table,
      columns: ['uuid'],
      where: where,
      whereArgs: whereArgs,
    );
    for (final r in rows) {
      final u = r['uuid'] as String?;
      if (u != null) await _enqueueOutbox(table, 'delete', {}, u);
    }
  }

  Future<List<Map<String, dynamic>>> getPendingOutbox() async {
    final db = await database;
    return await db.query(
      'outbox',
      where: 'synced_at IS NULL',
      orderBy: 'id ASC',
    );
  }

  /// Snapshot awal: enqueue SEMUA baris lokal ke outbox (parent dulu)
  /// agar data lama (pra-sync) ikut ter-upload. Dijalankan satu kali.
  Future<void> enqueueAllForSnapshot() async {
    const tables = [
      'products',
      'sales',
      'expenses',
      'sale_items',
      'customer_ledgers',
      'oil_stocks',
      'stock_managements',
      'stock_remainings',
      'personal_ledgers',
      'saldo_deductions',
    ];
    final db = await database;
    for (final table in tables) {
      final rows = await db.query(table, columns: ['id']);
      for (final r in rows) {
        final id = r['id'];
        if (id is int) await _enqueueRow(table, 'update', id);
      }
    }
  }

  Future<void> setOutboxSynced(int id) async {
    final db = await database;
    await db.update(
      'outbox',
      {'synced_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteOutboxEntry(int id) async {
    final db = await database;
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<String?> getSyncMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      'sync_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSyncMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'sync_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==================== APPLY REMOTE (tidak mengisi outbox) ====================

  Future<int?> _localIdByUuid(String table, String uuid) async {
    final db = await database;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  Future<int?> _localSaleIdByUuid(String uuid) =>
      _localIdByUuid('sales', uuid);

  Future<int?> _localProductIdByUuid(String uuid) =>
      _localIdByUuid('products', uuid);

  /// Terapkan baris remote ke tabel lokal. `payload` memakai kolom remote:
  /// `id` = uuid, kolom FK (sale_id/product_id) berisi uuid. TIDAK menulis outbox.
  Future<void> applyRemoteRow(
    String table,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    final uuid = payload['id'] as String?;
    if (uuid == null) return;

    final row = Map<String, dynamic>.from(payload);
    row.remove('id');
    row['uuid'] = uuid;

    if (table == 'sale_items') {
      final saleUuid = row.remove('sale_id') as String?;
      if (saleUuid != null && saleUuid.isNotEmpty) {
        final saleId = await _localSaleIdByUuid(saleUuid);
        if (saleId == null) {
          // Induk belum ada lokal -> tunggu diproses lagi nanti (parent dulu).
          return;
        }
        row['sale_id'] = saleId;
      }
      final productUuid = row.remove('product_id') as String?;
      if (productUuid != null && productUuid.isNotEmpty) {
        final productId = await _localProductIdByUuid(productUuid);
        if (productId != null) row['product_id'] = productId;
      }
    } else if (table == 'customer_ledgers') {
      final saleUuid = row.remove('sale_id') as String?;
      if (saleUuid != null && saleUuid.isNotEmpty) {
        final saleId = await _localSaleIdByUuid(saleUuid);
        if (saleId == null) return;
        row['sale_id'] = saleId;
      }
    }

    row.remove('updated_at');
    row.remove('deleted_at');
    row.remove('updated_by');
    row['updated_at'] = _now();

    final existingId = await _localIdByUuid(table, uuid);
    if (existingId != null) {
      row.remove('created_at');
      row['id'] = existingId;
      await db.update(table, row, where: 'id = ?', whereArgs: [existingId]);
    } else {
      await db.insert(table, row);
    }
  }

  Future<void> applyRemoteDelete(String table, String uuid) async {
    final db = await database;
    await db.delete(table, where: 'uuid = ?', whereArgs: [uuid]);
  }

  @override
  String toString() => 'DatabaseHelper';

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final cols = await db.rawQuery('PRAGMA table_info(sales)');
      final hasDebtPaid = cols.any((c) => c['name'] == 'debt_paid');
      if (!hasDebtPaid) {
        await db.execute(
          'ALTER TABLE sales ADD COLUMN debt_paid INTEGER DEFAULT 0',
        );
      }
    }
    if (oldVersion < 3) {
      final cols = await db.rawQuery('PRAGMA table_info(sales)');
      final hasDebtPaidAmount = cols.any(
        (c) => c['name'] == 'debt_paid_amount',
      );
      if (!hasDebtPaidAmount) {
        await db.execute(
          'ALTER TABLE sales ADD COLUMN debt_paid_amount INTEGER DEFAULT 0',
        );
      }
    }
    if (oldVersion < 4) {
      final cols = await db.rawQuery('PRAGMA table_info(oil_stocks)');
      final priceCol = cols.firstWhere(
        (c) => c['name'] == 'price',
        orElse: () => {},
      );
      if (priceCol.isNotEmpty &&
          (priceCol['type'] as String?)?.toUpperCase() == 'INTEGER') {
        await db.execute('ALTER TABLE oil_stocks RENAME TO oil_stocks_old');
        await db.execute(
          '''CREATE TABLE oil_stocks (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, qty REAL DEFAULT 0, price REAL DEFAULT 0, created_at TEXT, updated_at TEXT)''',
        );
        await db.execute(
          'INSERT INTO oil_stocks (id, date, qty, price, created_at, updated_at) SELECT id, date, qty, price, created_at, updated_at FROM oil_stocks_old',
        );
        await db.execute('DROP TABLE oil_stocks_old');
      }
    }
    if (oldVersion < 5) {
      const syncTables = [
        'products',
        'sales',
        'sale_items',
        'oil_stocks',
        'stock_managements',
        'stock_remainings',
        'customer_ledgers',
        'personal_ledgers',
        'saldo_deductions',
        'expenses',
      ];
      for (final table in syncTables) {
        final cols = await db.rawQuery('PRAGMA table_info($table)');
        final names = cols.map((c) => c['name']).toSet();
        if (!names.contains('uuid')) {
          await db.execute('ALTER TABLE $table ADD COLUMN uuid TEXT');
        }
        if (!names.contains('deleted_at')) {
          await db.execute('ALTER TABLE $table ADD COLUMN deleted_at TEXT');
        }
        final missing = await db.query(
          table,
          columns: ['id'],
          where: 'uuid IS NULL',
        );
        for (final row in missing) {
          await db.update(
            table,
            {'uuid': _uuidGen.v4()},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      await _createSyncTables(db);
    }
  }

  Future<void> _createSyncTables(Database db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL, operation TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT, synced_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS sync_meta (key TEXT PRIMARY KEY, value TEXT)''',
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute(
      '''CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, price INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE sales (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT NOT NULL, raw_total INTEGER DEFAULT 0, rounded_total INTEGER DEFAULT 0, paid INTEGER DEFAULT 0, diff INTEGER DEFAULT 0, note TEXT, is_paid_btn_clicked INTEGER DEFAULT 0, debt_paid INTEGER DEFAULT 0, debt_paid_amount INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE sale_items (id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER, name TEXT NOT NULL, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT, FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE)''',
    );
    await db.execute(
      '''CREATE TABLE oil_stocks (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, qty REAL DEFAULT 0, price REAL DEFAULT 0, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE stock_managements (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, name TEXT NOT NULL, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, batches TEXT, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE stock_remainings (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, name TEXT NOT NULL, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE customer_ledgers (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER DEFAULT 0, type TEXT NOT NULL, note TEXT, sale_id INTEGER, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT, FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE)''',
    );
    await db.execute(
      '''CREATE TABLE personal_ledgers (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER DEFAULT 0, note TEXT, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE saldo_deductions (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, a INTEGER DEFAULT 0, b INTEGER DEFAULT 0, note TEXT, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, amount INTEGER DEFAULT 0, note TEXT, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT)''',
    );
    await _createSyncTables(db);
  }

  // ==================== PRODUCTS ====================
  Future<int> insertProduct(Product product) async {
    final db = await database;
    final data = product.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('products', data);
    await _enqueueOutbox('products', 'insert', data, uuid);
    return id;
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final maps = await db.query('products', orderBy: 'name ASC');
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    final data = product.toMap();
    data['updated_at'] = _now();
    final id = await db.update(
      'products',
      data,
      where: 'id = ?',
      whereArgs: [product.id],
    );
    final uuid = await _uuidOf('products', product.id ?? -1);
    if (uuid != null) {
      await _enqueueOutbox('products', 'update', data, uuid);
    }
    return id;
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    await _enqueueDeleteById('products', id);
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== SALES ====================
  Future<int> insertSale(Sale sale) async {
    final db = await database;
    final data = sale.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('sales', data);
    await _enqueueOutbox('sales', 'insert', data, uuid);
    return id;
  }

  Future<List<Sale>> getSalesByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'sales',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => Sale.fromMap(m)).toList();
  }

  Future<List<String>> getUniqueSaleNames() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT name FROM sales ORDER BY name ASC',
    );
    return result.map((r) => r['name'] as String).toList();
  }

  Future<List<Sale>> getSalesByMonth(String startDate, String endDate) async {
    final db = await database;
    final maps = await db.query(
      'sales',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => Sale.fromMap(m)).toList();
  }

  Future<int> updateSale(Sale sale) async {
    final db = await database;
    final data = sale.toMap();
    data['updated_at'] = _now();
    final id = await db.update(
      'sales',
      data,
      where: 'id = ?',
      whereArgs: [sale.id],
    );
    if (sale.id != null) await _enqueueRow('sales', 'update', sale.id!);
    return id;
  }

  Future<void> setSaleDebtPaid(int saleId, bool value) async {
    final db = await database;
    await db.update(
      'sales',
      {'debt_paid': value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [saleId],
    );
    await _enqueueRow('sales', 'update', saleId);
  }

  Future<Sale?> getPreviousUnpaidSale(String name, String beforeDate) async {
    final db = await database;
    final maps = await db.query(
      'sales',
      where: 'name = ? AND date < ? AND diff > 0',
      whereArgs: [name, beforeDate],
      orderBy: 'date DESC, id DESC',
      limit: 1,
    );
    return maps.isEmpty ? null : Sale.fromMap(maps.first);
  }

  Future<void> deleteSale(int id) async {
    final db = await database;
    final items = await db.query(
      'sale_items',
      columns: ['id'],
      where: 'sale_id = ?',
      whereArgs: [id],
    );
    for (final item in items) {
      await _enqueueDeleteById('sale_items', item['id'] as int);
    }
    final ledgers = await db.query(
      'customer_ledgers',
      columns: ['id'],
      where: 'sale_id = ?',
      whereArgs: [id],
    );
    for (final ledger in ledgers) {
      await _enqueueDeleteById('customer_ledgers', ledger['id'] as int);
    }
    await _enqueueDeleteById('sales', id);
    await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [id]);
    await db.delete('customer_ledgers', where: 'sale_id = ?', whereArgs: [id]);
    await db.delete('sales', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== SALE ITEMS ====================
  Future<int> insertSaleItem(SaleItem item) async {
    final db = await database;
    final data = item.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('sale_items', data);
    await _enqueueOutbox('sale_items', 'insert', data, uuid);
    return id;
  }

  Future<void> deleteSaleItemsBySaleId(int saleId) async {
    final db = await database;
    final items = await db.query(
      'sale_items',
      columns: ['id'],
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
    for (final item in items) {
      await _enqueueDeleteById('sale_items', item['id'] as int);
    }
    await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
  }

  Future<List<SaleItem>> getSaleItemsBySaleId(int saleId) async {
    final db = await database;
    final maps = await db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id ASC',
    );
    return maps.map((m) => SaleItem.fromMap(m)).toList();
  }

  Future<List<SaleItem>> getSaleItemsByDate(String date) async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT si.* FROM sale_items si INNER JOIN sales s ON si.sale_id = s.id WHERE s.date = ? ORDER BY si.id ASC',
      [date],
    );
    return maps.map((m) => SaleItem.fromMap(m)).toList();
  }

  Future<List<SaleItem>> getSaleItemsByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT si.* FROM sale_items si INNER JOIN sales s ON si.sale_id = s.id WHERE s.date BETWEEN ? AND ? ORDER BY s.date ASC, si.id ASC',
      [startDate, endDate],
    );
    return maps.map((m) => SaleItem.fromMap(m)).toList();
  }

  // ==================== ANALYTICS ====================
  Future<List<Map<String, dynamic>>> getTopProductsByMonth(
    String startDate,
    String endDate, {
    int limit = 10,
  }) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT si.name, SUM(si.qty) as totalQty, SUM(si.qty * si.price) as totalSubtotal
      FROM sale_items si
      INNER JOIN sales s ON si.sale_id = s.id
      WHERE s.date BETWEEN ? AND ?
      GROUP BY si.name
      ORDER BY totalQty DESC
      LIMIT ?
    ''',
      [startDate, endDate, limit],
    );
    return maps;
  }

  Future<List<Map<String, dynamic>>> getTopCustomersByMonth(
    String startDate,
    String endDate, {
    int limit = 10,
    String sortBy = 'paid',
  }) async {
    final db = await database;
    final orderBy = sortBy == 'transactions'
        ? 'totalTransactions'
        : 'totalPaid';
    final maps = await db.rawQuery(
      '''
      SELECT s.name, COUNT(*) as totalTransactions, SUM(s.rounded_total) as totalSpent, SUM(s.paid) as totalPaid
      FROM sales s
      WHERE s.date BETWEEN ? AND ?
      GROUP BY s.name
      ORDER BY $orderBy DESC
      LIMIT ?
    ''',
      [startDate, endDate, limit],
    );
    return maps;
  }

  Future<List<Map<String, dynamic>>> getDailySalesByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT date, SUM(rounded_total) as totalSales, SUM(paid) as totalPaid, COUNT(*) as transactionCount
      FROM sales
      WHERE date BETWEEN ? AND ?
      GROUP BY date
      ORDER BY date ASC
    ''',
      [startDate, endDate],
    );
    return maps;
  }

  // ==================== OIL STOCKS ====================
  Future<int> insertOilStock(OilStock oil) async {
    final db = await database;
    final data = oil.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('oil_stocks', data);
    await _enqueueOutbox('oil_stocks', 'insert', data, uuid);
    return id;
  }

  Future<int> updateOilStock(OilStock oil) async {
    final db = await database;
    final data = oil.toMap();
    data['updated_at'] = _now();
    final id = await db.update(
      'oil_stocks',
      data,
      where: 'id = ?',
      whereArgs: [oil.id],
    );
    if (oil.id != null) await _enqueueRow('oil_stocks', 'update', oil.id!);
    return id;
  }

  Future<List<OilStock>> getOilStocksByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'oil_stocks',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'id ASC',
    );
    return maps.map((m) => OilStock.fromMap(m)).toList();
  }

  Future<List<OilStock>> getOilStocksByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'oil_stocks',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => OilStock.fromMap(m)).toList();
  }

  Future<OilStock?> getLatestOilStock(String beforeDate) async {
    final db = await database;
    final maps = await db.query(
      'oil_stocks',
      where: 'date < ?',
      whereArgs: [beforeDate],
      orderBy: 'date DESC, id DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return OilStock.fromMap(maps.first);
  }

  Future<int> deleteOilStock(int id) async {
    final db = await database;
    await _enqueueDeleteById('oil_stocks', id);
    return await db.delete('oil_stocks', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== STOCK MANAGEMENTS ====================
  Future<int> insertStockManagement(StockManagement sm) async {
    final db = await database;
    final data = sm.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('stock_managements', data);
    await _enqueueOutbox('stock_managements', 'insert', data, uuid);
    return id;
  }

  Future<int> updateStockManagement(StockManagement sm) async {
    final db = await database;
    final data = sm.toMap();
    data['updated_at'] = _now();
    final id = await db.update(
      'stock_managements',
      data,
      where: 'id = ?',
      whereArgs: [sm.id],
    );
    if (sm.id != null) {
      await _enqueueRow('stock_managements', 'update', sm.id!);
    }
    return id;
  }

  Future<List<StockManagement>> getStockManagementsByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'stock_managements',
      where: '(date BETWEEN ? AND ? OR date IS NULL)',
      whereArgs: [startDate, endDate],
      orderBy: 'id ASC',
    );
    return maps.map((m) => StockManagement.fromMap(m)).toList();
  }

  Future<List<StockManagement>> getStockManagementsByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'stock_managements',
      where: 'date = ? OR date IS NULL',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => StockManagement.fromMap(m)).toList();
  }

  Future<List<StockManagement>> getLatestStockManagements(
    String beforeDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'stock_managements',
      where: 'date < ?',
      whereArgs: [beforeDate],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map((m) => StockManagement.fromMap(m)).toList();
  }

  Future<int> deleteStockManagement(int id) async {
    final db = await database;
    await _enqueueDeleteById('stock_managements', id);
    return await db.delete(
      'stock_managements',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== STOCK REMAININGS ====================
  Future<int> insertStockRemaining(StockRemaining sr) async {
    final db = await database;
    final data = sr.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('stock_remainings', data);
    await _enqueueOutbox('stock_remainings', 'insert', data, uuid);
    return id;
  }

  Future<List<StockRemaining>> getStockRemainingsByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'stock_remainings',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'id ASC',
    );
    return maps.map((m) => StockRemaining.fromMap(m)).toList();
  }

  Future<List<StockRemaining>> getStockRemainingsByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'stock_remainings',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => StockRemaining.fromMap(m)).toList();
  }

  Future<List<StockRemaining>> getLatestStockRemainings(
    String beforeDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'stock_remainings',
      where: 'date < ?',
      whereArgs: [beforeDate],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map((m) => StockRemaining.fromMap(m)).toList();
  }

  Future<int> deleteStockRemaining(int id) async {
    final db = await database;
    await _enqueueDeleteById('stock_remainings', id);
    return await db.delete(
      'stock_remainings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateStockRemaining(StockRemaining sr) async {
    final db = await database;
    final data = sr.toMap();
    data['updated_at'] = _now();
    final id = await db.update(
      'stock_remainings',
      data,
      where: 'id = ?',
      whereArgs: [sr.id],
    );
    if (sr.id != null) await _enqueueRow('stock_remainings', 'update', sr.id!);
    return id;
  }

  // ==================== CUSTOMER LEDGERS ====================
  Future<int> insertCustomerLedger(CustomerLedger ledger) async {
    final db = await database;
    final data = ledger.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('customer_ledgers', data);
    await _enqueueOutbox('customer_ledgers', 'insert', data, uuid);
    return id;
  }

  Future<List<CustomerLedger>> getAllCustomerLedgers() async {
    final db = await database;
    final maps = await db.query(
      'customer_ledgers',
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => CustomerLedger.fromMap(m)).toList();
  }

  Future<List<CustomerLedger>> getCustomerLedgersByName(String name) async {
    final db = await database;
    final maps = await db.query(
      'customer_ledgers',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => CustomerLedger.fromMap(m)).toList();
  }

  Future<List<CustomerLedger>> getCustomerLedgersByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'customer_ledgers',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => CustomerLedger.fromMap(m)).toList();
  }

  Future<List<CustomerLedger>> getCustomerLedgersByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'customer_ledgers',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => CustomerLedger.fromMap(m)).toList();
  }

  Future<int> updateCustomerLedger(CustomerLedger ledger) async {
    final db = await database;
    final data = ledger.toMap();
    data['updated_at'] = _now();
    final id = await db.update(
      'customer_ledgers',
      data,
      where: 'id = ?',
      whereArgs: [ledger.id],
    );
    if (ledger.id != null) {
      await _enqueueRow('customer_ledgers', 'update', ledger.id!);
    }
    return id;
  }

  Future<int> deleteCustomerLedger(int id) async {
    final db = await database;
    await _enqueueDeleteById('customer_ledgers', id);
    return await db.delete(
      'customer_ledgers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCustomerLedgerByName(String name) async {
    final db = await database;
    await _enqueueBulkDelete('customer_ledgers', 'name = ?', [name]);
    await db.delete('customer_ledgers', where: 'name = ?', whereArgs: [name]);
  }

  // ==================== PERSONAL LEDGERS ====================
  Future<int> insertPersonalLedger(PersonalLedger ledger) async {
    final db = await database;
    final data = ledger.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('personal_ledgers', data);
    await _enqueueOutbox('personal_ledgers', 'insert', data, uuid);
    return id;
  }

  Future<List<PersonalLedger>> getPersonalLedgersByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'personal_ledgers',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => PersonalLedger.fromMap(m)).toList();
  }

  Future<List<PersonalLedger>> getPersonalLedgersByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'personal_ledgers',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => PersonalLedger.fromMap(m)).toList();
  }

  Future<List<PersonalLedger>> getLatestPersonalLedgers(
    String beforeDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'personal_ledgers',
      where: 'date < ?',
      whereArgs: [beforeDate],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map((m) => PersonalLedger.fromMap(m)).toList();
  }

  Future<int> deletePersonalLedger(int id) async {
    final db = await database;
    await _enqueueDeleteById('personal_ledgers', id);
    return await db.delete(
      'personal_ledgers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePersonalLedger(PersonalLedger ledger) async {
    final db = await database;
    final data = ledger.toMap();
    data.remove('id');
    data.remove('date');
    data.remove('created_at');
    data['updated_at'] = _now();
    final id = await db.update(
      'personal_ledgers',
      data,
      where: 'id = ?',
      whereArgs: [ledger.id],
    );
    if (ledger.id != null) {
      await _enqueueRow('personal_ledgers', 'update', ledger.id!);
    }
    return id;
  }

  // ==================== SALDO DEDUCTIONS ====================
  Future<int> insertSaldoDeduction(SaldoDeduction saldo) async {
    final db = await database;
    final data = saldo.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('saldo_deductions', data);
    await _enqueueOutbox('saldo_deductions', 'insert', data, uuid);
    return id;
  }

  Future<int> updateSaldoDeduction(SaldoDeduction saldo) async {
    final db = await database;
    final data = saldo.toMap();
    data['updated_at'] = _now();
    final id = await db.update(
      'saldo_deductions',
      data,
      where: 'id = ?',
      whereArgs: [saldo.id],
    );
    if (saldo.id != null) {
      await _enqueueRow('saldo_deductions', 'update', saldo.id!);
    }
    return id;
  }

  Future<List<SaldoDeduction>> getSaldoDeductionsByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'saldo_deductions',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => SaldoDeduction.fromMap(m)).toList();
  }

  Future<List<SaldoDeduction>> getSaldoDeductionsByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'saldo_deductions',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((m) => SaldoDeduction.fromMap(m)).toList();
  }

  Future<SaldoDeduction?> getLatestSaldoDeduction(String beforeDate) async {
    final db = await database;
    final maps = await db.query(
      'saldo_deductions',
      where: 'date < ?',
      whereArgs: [beforeDate],
      orderBy: 'date DESC, id DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return SaldoDeduction.fromMap(maps.first);
  }

  Future<int> deleteSaldoDeduction(int id) async {
    final db = await database;
    await _enqueueDeleteById('saldo_deductions', id);
    return await db.delete(
      'saldo_deductions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== EXPENSES ====================
  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    final data = expense.toMap();
    data.remove('id');
    final uuid = newUuid();
    data['uuid'] = uuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('expenses', data);
    await _enqueueOutbox('expenses', 'insert', data, uuid);
    return id;
  }

  Future<List<Expense>> getExpensesByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<List<Expense>> getExpensesByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'id ASC',
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    await _enqueueDeleteById('expenses', id);
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== SEED ====================
  Future<void> seedProducts() async {
    final db = await database;
    const names = [
      'Kuning',
      'Lempeng',
      'Kabur',
      'Flowning',
      'Gelung',
      'Kecil OM',
      'Kecil MJ',
      'PJO',
      'Kecil 2',
      'TG',
      'TG Mini',
      'Drg',
      'Lj',
      'Uren',
      'TM',
    ];
    final existing = await db.rawQuery('SELECT LOWER(name) as n FROM products');
    final existingNames = existing
        .map((e) => (e['n'] as String).toLowerCase())
        .toSet();
    for (final name in names) {
      if (!existingNames.contains(name.toLowerCase())) {
        await insertProduct(Product(name: name, price: 0));
      }
    }
  }

  // ==================== RESET ====================
  Future<void> resetMonth(String startDate, String endDate) async {
    final db = await database;
    await _enqueueBulkDelete('sales', 'date BETWEEN ? AND ?', [
      startDate,
      endDate,
    ]);
    await _enqueueBulkDelete('expenses', 'date BETWEEN ? AND ?', [
      startDate,
      endDate,
    ]);
    await _enqueueBulkDelete('oil_stocks', 'date BETWEEN ? AND ?', [
      startDate,
      endDate,
    ]);
    await _enqueueBulkDelete('stock_managements', 'date BETWEEN ? AND ?', [
      startDate,
      endDate,
    ]);
    await _enqueueBulkDelete('stock_remainings', 'date BETWEEN ? AND ?', [
      startDate,
      endDate,
    ]);
    await _enqueueBulkDelete('personal_ledgers', 'date BETWEEN ? AND ?', [
      startDate,
      endDate,
    ]);
    await _enqueueBulkDelete('saldo_deductions', 'date BETWEEN ? AND ?', [
      startDate,
      endDate,
    ]);
    await db.delete(
      'sales',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
    );
    await db.delete(
      'expenses',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
    );
    await db.delete(
      'oil_stocks',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
    );
    await db.delete(
      'stock_managements',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
    );
    await db.delete(
      'stock_remainings',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
    );
    await db.delete(
      'personal_ledgers',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
    );
    await db.delete(
      'saldo_deductions',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
    );
  }

  Future<void> resetAll() async {
    final db = await database;
    await _enqueueBulkDelete('sale_items', null, null);
    await _enqueueBulkDelete('sales', null, null);
    await _enqueueBulkDelete('customer_ledgers', null, null);
    await _enqueueBulkDelete('personal_ledgers', null, null);
    await _enqueueBulkDelete('oil_stocks', null, null);
    await _enqueueBulkDelete('stock_managements', null, null);
    await _enqueueBulkDelete('stock_remainings', null, null);
    await _enqueueBulkDelete('products', null, null);
    await _enqueueBulkDelete('saldo_deductions', null, null);
    await _enqueueBulkDelete('expenses', null, null);
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('customer_ledgers');
    await db.delete('personal_ledgers');
    await db.delete('oil_stocks');
    await db.delete('stock_managements');
    await db.delete('stock_remainings');
    await db.delete('products');
    await db.delete('saldo_deductions');
    await db.delete('expenses');
  }

  Future<void> clearOilAndSaldo() async {
    final db = await database;
    await _enqueueBulkDelete('oil_stocks', null, null);
    await _enqueueBulkDelete('saldo_deductions', null, null);
    await db.delete('oil_stocks');
    await db.delete('saldo_deductions');
  }
}
