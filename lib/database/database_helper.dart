import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
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
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  String _now() => DateTime.now().toIso8601String();

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
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute(
      '''CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, price INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE sales (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT NOT NULL, raw_total INTEGER DEFAULT 0, rounded_total INTEGER DEFAULT 0, paid INTEGER DEFAULT 0, diff INTEGER DEFAULT 0, note TEXT, is_paid_btn_clicked INTEGER DEFAULT 0, debt_paid INTEGER DEFAULT 0, debt_paid_amount INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE sale_items (id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER, name TEXT NOT NULL, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT, FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE)''',
    );
    await db.execute(
      '''CREATE TABLE oil_stocks (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE stock_managements (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, name TEXT NOT NULL, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, batches TEXT, created_at TEXT, updated_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE stock_remainings (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, name TEXT NOT NULL, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE customer_ledgers (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER DEFAULT 0, type TEXT NOT NULL, note TEXT, sale_id INTEGER, created_at TEXT, updated_at TEXT, FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE)''',
    );
    await db.execute(
      '''CREATE TABLE personal_ledgers (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER DEFAULT 0, note TEXT, created_at TEXT, updated_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE saldo_deductions (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, a INTEGER DEFAULT 0, b INTEGER DEFAULT 0, note TEXT, created_at TEXT, updated_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, amount INTEGER DEFAULT 0, note TEXT, created_at TEXT, updated_at TEXT)''',
    );
  }

  // ==================== PRODUCTS ====================
  Future<int> insertProduct(Product product) async {
    final db = await database;
    final data = product.toMap();
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('products', data);
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
    return await db.update(
      'products',
      data,
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== SALES ====================
  Future<int> insertSale(Sale sale) async {
    final db = await database;
    final data = sale.toMap();
    data.remove('id');
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('sales', data);
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
    return await db.update(
      'sales',
      data,
      where: 'id = ?',
      whereArgs: [sale.id],
    );
  }

  Future<void> setSaleDebtPaid(int saleId, bool value) async {
    final db = await database;
    await db.update(
      'sales',
      {'debt_paid': value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [saleId],
    );
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
    await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [id]);
    await db.delete('customer_ledgers', where: 'sale_id = ?', whereArgs: [id]);
    await db.delete('sales', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== SALE ITEMS ====================
  Future<int> insertSaleItem(SaleItem item) async {
    final db = await database;
    final data = item.toMap();
    data.remove('id');
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('sale_items', data);
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
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('oil_stocks', data);
  }

  Future<int> updateOilStock(OilStock oil) async {
    final db = await database;
    final data = oil.toMap();
    data['updated_at'] = _now();
    return await db.update(
      'oil_stocks',
      data,
      where: 'id = ?',
      whereArgs: [oil.id],
    );
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
    return await db.delete('oil_stocks', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== STOCK MANAGEMENTS ====================
  Future<int> insertStockManagement(StockManagement sm) async {
    final db = await database;
    final data = sm.toMap();
    data.remove('id');
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('stock_managements', data);
  }

  Future<int> updateStockManagement(StockManagement sm) async {
    final db = await database;
    final data = sm.toMap();
    data['updated_at'] = _now();
    return await db.update(
      'stock_managements',
      data,
      where: 'id = ?',
      whereArgs: [sm.id],
    );
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
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('stock_remainings', data);
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
    return await db.update(
      'stock_remainings',
      data,
      where: 'id = ?',
      whereArgs: [sr.id],
    );
  }

  // ==================== CUSTOMER LEDGERS ====================
  Future<int> insertCustomerLedger(CustomerLedger ledger) async {
    final db = await database;
    final data = ledger.toMap();
    data.remove('id');
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('customer_ledgers', data);
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
    return await db.update(
      'customer_ledgers',
      data,
      where: 'id = ?',
      whereArgs: [ledger.id],
    );
  }

  Future<int> deleteCustomerLedger(int id) async {
    final db = await database;
    return await db.delete(
      'customer_ledgers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCustomerLedgerByName(String name) async {
    final db = await database;
    await db.delete('customer_ledgers', where: 'name = ?', whereArgs: [name]);
  }

  // ==================== PERSONAL LEDGERS ====================
  Future<int> insertPersonalLedger(PersonalLedger ledger) async {
    final db = await database;
    final data = ledger.toMap();
    data.remove('id');
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('personal_ledgers', data);
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
    return await db.update(
      'personal_ledgers',
      data,
      where: 'id = ?',
      whereArgs: [ledger.id],
    );
  }

  // ==================== SALDO DEDUCTIONS ====================
  Future<int> insertSaldoDeduction(SaldoDeduction saldo) async {
    final db = await database;
    final data = saldo.toMap();
    data.remove('id');
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('saldo_deductions', data);
  }

  Future<int> updateSaldoDeduction(SaldoDeduction saldo) async {
    final db = await database;
    final data = saldo.toMap();
    data['updated_at'] = _now();
    return await db.update(
      'saldo_deductions',
      data,
      where: 'id = ?',
      whereArgs: [saldo.id],
    );
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
    data['created_at'] = _now();
    data['updated_at'] = _now();
    return await db.insert('expenses', data);
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
    await db.delete('oil_stocks');
    await db.delete('saldo_deductions');
  }
}
