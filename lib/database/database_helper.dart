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
import '../constants/formatters.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  bool _isClosed = false;

  DatabaseHelper._init();

  /// True jika database sedang ditutup (export/import).
  bool get isClosed => _isClosed;

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
    _isClosed = true;
    if (_database != null) {
      final db = _database!;
      _database = null;
      await db.close();
    }
  }

  Future<String> exportDatabase(String destPath) async {
    final src = await getDatabaseFilePath();
    if (!File(src).existsSync()) {
      throw Exception('Database belum ditemukan');
    }
    // Force WAL checkpoint supaya semua data tertulis ke file utama
    // sebelum copy, TANPA menutup database (sync tetap jalan).
    try {
      final db = await database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await File(src).copy(destPath);
    return destPath;
  }

  Future<Uint8List> exportDatabaseBytes() async {
    final src = await getDatabaseFilePath();
    if (!File(src).existsSync()) {
      throw Exception('Database belum ditemukan');
    }
    // Force WAL checkpoint supaya semua data tertulis ke file utama.
    try {
      final db = await database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    final bytes = await File(src).readAsBytes();
    return bytes;
  }

  Future<void> shutdownExport(String destPath) async {
    // Digunakan saat app mau tutup (close). Tutup DB dulu supaya file aman.
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
    // Tutup database lama, timpa file, lalu buka ulang.
    // Sync engine akan otomatis pause karena _busy / _client == null.
    await closeDatabase();
    final dest = await getDatabaseFilePath();
    await Directory(dirname(dest)).create(recursive: true);
    await File(srcPath).copy(dest);
    await database;
    return true;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _isClosed = false;
    _database = await _initDB('pos_krupuk.db');
    await _ensureHistoricalFreeze();
    return _database!;
  }

  Future<void> _ensureHistoricalFreeze() async {
    final db = _database!;
    // Always unfreeze today (active working day)
    final today = DateTime.now().toIso8601String().substring(0, 10);
    for (final table in _slotTables) {
      await db.update(table, {'frozen': 0},
          where: 'date = ?', whereArgs: [today]);
    }
    // One-time: freeze all historical dates
    final flag = await getSyncMeta('freeze_v1_done');
    if (flag != null) return;
    for (final table in _slotTables) {
      await db.update(table, {'frozen': 1},
          where: 'date < ? AND date != "" AND date IS NOT NULL',
          whereArgs: [today]);
    }
    await setSyncMeta('freeze_v1_done', '1');
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
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  String _now() => DateTime.now().toIso8601String();

  static final Uuid _uuidGen = Uuid();
  String newUuid() => _uuidGen.v4();

  /// UUID DETERMINISTIK untuk slot materialisasi "copy & putus". Semua HP
  /// menghasilkan nilai yang SAMA untuk (table, date, name), sehingga slot
  /// yang sama dibuat sebagai baris yang sama (bukan uuid acak) dan data
  /// tidak "nyasar" antar HP / hari.
  String slotUuid(String table, String date, String? name) {
    final s = StringBuffer('$table|$date');
    if (name != null && name.isNotEmpty) s.write('|$name');
    return _uuidGen.v5(Namespace.url.value, s.toString());
  }

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
        // Simpan FK lokal agar saat push bisa di-resolve ulang jika uuid
        // induk belum ada / berubah (mis. sesaat setelah import/data lama).
        p['_local_sale_id'] = sid;
        final rows = await database.then(
          (d) => d.query('sales', columns: ['uuid'], where: 'id = ?', whereArgs: [sid]),
        );
        final saleUuid = rows.isEmpty ? null : rows.first['uuid'] as String?;
        p['sale_id'] = saleUuid;
      }
      final pid = p.remove('product_id');
      if (pid != null && pid is int) {
        p['_local_product_id'] = pid;
        final rows = await database.then(
          (d) => d.query('products', columns: ['uuid'], where: 'id = ?', whereArgs: [pid]),
        );
        final productUuid = rows.isEmpty ? null : rows.first['uuid'] as String?;
        p['product_id'] = productUuid;
      }
    } else if (table == 'customer_ledgers') {
      final sid = p.remove('sale_id');
      if (sid != null && sid is int) {
        p['_local_sale_id'] = sid;
        final rows = await database.then(
          (d) => d.query('sales', columns: ['uuid'], where: 'id = ?', whereArgs: [sid]),
        );
        final saleUuid = rows.isEmpty ? null : rows.first['uuid'] as String?;
        p['sale_id'] = saleUuid;
      } else {
        // Hutang manual tanpa sale -> kirim null eksplisit (kolom nullable).
        p['sale_id'] = null;
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

  /// UUID terkini untuk baris induk (dipakai push untuk resolve-ulang FK).
  Future<String?> saleUuidByLocalId(int id) => _uuidOf('sales', id);

  Future<String?> productUuidByLocalId(int id) => _uuidOf('products', id);

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
      debugPrint('SYNC snapshot $table: ${rows.length} (total ${_totalEnqueued})');
      for (final r in rows) {
        final id = r['id'];
        if (id is int) await _enqueueRow(table, 'update', id);
      }
      _totalEnqueued += rows.length;
    }
  }

  int _totalEnqueued = 0;

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

  static final DateTime _epoch =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Tabel "copy & putus" per hari. Slot di-resolusi dengan last-writer-wins:
  /// oil_stocks & saldo_deductions -> slot = tanggal;
  /// stock_managements/stock_remainings/personal_ledgers -> slot = tanggal+nama.
  static const _slotTables = {
    'oil_stocks',
    'stock_managements',
    'stock_remainings',
    'personal_ledgers',
    'saldo_deductions',
  };

  bool _isSlotTable(String table) => _slotTables.contains(table);

  /// Subset slot yang identitasnya per tanggal + nama (bukan per tanggal saja).
  static const _nameSlotTables = {
    'stock_managements',
    'stock_remainings',
    'personal_ledgers',
  };

  bool _isNameSlot(String table) => _nameSlotTables.contains(table);

  DateTime _parseTs(String? s) {
    if (s == null || s.isEmpty) return _epoch;
    return DateTime.tryParse(s) ?? _epoch;
  }

  Future<DateTime> _maxSlotUpdatedAt(
    String table,
    String date,
    String? name,
  ) async {
    final db = await database;
    final rows = await db.query(
      table,
      columns: ['updated_at'],
      where: name == null || name.isEmpty
          ? 'date = ?'
          : 'date = ? AND name = ?',
      whereArgs: name == null || name.isEmpty ? [date] : [date, name],
    );
    var max = _epoch;
    for (final r in rows) {
      final t = _parseTs(r['updated_at'] as String?);
      if (t.isAfter(max)) max = t;
    }
    return max;
  }

  Future<List<int>> _slotLocalIds(
    String table,
    String date,
    String? name,
  ) async {
    final db = await database;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: name == null || name.isEmpty
          ? 'date = ?'
          : 'date = ? AND name = ?',
      whereArgs: name == null || name.isEmpty ? [date] : [date, name],
    );
    return rows.map((r) => r['id'] as int).toList();
  }

  /// Baris terakhir per slot untuk sumber "copy & putus": hanya mengambil
  /// baris dari tanggal TERDEKAT sebelum [beforeDate] (bukan semua tanggal
  /// di masa lalu). Ini mencegah record dari tanggal jauh/empty-date (yang
  /// sync dari HP lain) ikut "nyasar" ke tanggal baru.
  Future<List<Map<String, dynamic>>> _latestSlotRows(
    String table,
    String beforeDate,
  ) async {
    final db = await database;
    // Step 1: Cari tanggal terakhir yang valid sebelum beforeDate
    final latestDateRow = await db.rawQuery(
      "SELECT MAX(date) as latest_date FROM $table WHERE date < ? AND date != '' AND date IS NOT NULL",
      [beforeDate],
    );
    final latestDate = latestDateRow.isNotEmpty
        ? latestDateRow.first['latest_date'] as String?
        : null;
    if (latestDate == null || latestDate.isEmpty) return [];

    // Step 2: Ambil hanya record dari tanggal tersebut
    final maps = await db.query(
      table,
      where: 'date = ?',
      whereArgs: [latestDate],
      orderBy: 'updated_at DESC, id DESC',
    );
    final bySlot = <String, Map<String, dynamic>>{};
    for (final m in maps) {
      final isNamed = _isNameSlot(table);
      final nm = isNamed ? (m['name'] as String? ?? '') : '';
      final key = isNamed ? nm : latestDate;
      bySlot.putIfAbsent(key, () => m);
    }
    return bySlot.values.toList();
  }

  Future<String?> _latestSlotDate(String table, String beforeDate) async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT MAX(date) as d FROM $table WHERE date < ? AND date != '' AND date IS NOT NULL",
      [beforeDate],
    );
    return r.isNotEmpty ? r.first['d'] as String? : null;
  }

  /// Baris slot TERAKHIR per nama dalam rentang bulan (untuk ringkasan):
  /// diambil baris dengan tanggal terbaru, dan di antara duplikat slot yang
  /// sama dipakai yang `updated_at`-nya terbesar.
  Future<List<Map<String, dynamic>>> _latestNameRowsInMonth(
    String table,
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      table,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date DESC, updated_at DESC, id DESC',
    );
    final byName = <String, Map<String, dynamic>>{};
    for (final m in maps) {
      final nm = m['name'] as String? ?? '';
      if (nm.isEmpty) continue;
      byName.putIfAbsent(nm, () => m);
    }
    return byName.values.toList();
  }

  Future<bool> _localRowNewerThan(
    String table,
    int id,
    DateTime remoteTs,
  ) async {
    final db = await database;
    final rows = await db.query(
      table,
      columns: ['updated_at'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return _parseTs(rows.first['updated_at'] as String?).isAfter(remoteTs);
  }

  /// Urutan pull: induk dulu agar FK child terselesaikan.
  static const _pendingTableOrder = [
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

  Future<void> _savePendingRemote(
    String table,
    String uuid,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    await db.insert(
      'sync_pending',
      {
        'table_name': table,
        'uuid': uuid,
        'payload': jsonEncode(payload),
        'created_at': _now(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePendingRemote(String table, String uuid) async {
    final db = await database;
    await db.delete(
      'sync_pending',
      where: 'table_name = ? AND uuid = ?',
      whereArgs: [table, uuid],
    );
  }

  /// Coba terapkan ulang baris yang tadinya menunggu induknya tiba lokal.
  /// Dipanggil tiap akhir siklus pull & saat push.
  Future<int> processPendingRemote() async {
    final db = await database;
    final rows = await db.query('sync_pending', orderBy: 'id ASC');
    if (rows.isEmpty) return 0;
    final order = <String, int>{
      for (var i = 0; i < _pendingTableOrder.length; i++)
        _pendingTableOrder[i]: i,
    };
    rows.sort(
      (a, b) => (order[a['table_name']] ?? 999)
          .compareTo(order[b['table_name']] ?? 999),
    );
    var applied = 0;
    for (final entry in rows) {
      final table = entry['table_name'] as String;
      final uuid = entry['uuid'] as String;
      final raw = entry['payload'] as String? ?? '{}';
      Map<String, dynamic>? payload;
      try {
        final d = jsonDecode(raw);
        if (d is Map<String, dynamic>) payload = d;
      } catch (_) {
        payload = null;
      }
      if (payload == null) {
        await deletePendingRemote(table, uuid);
        continue;
      }
      final ok = await applyRemoteRow(table, payload);
      if (ok) {
        await deletePendingRemote(table, uuid);
        applied++;
      }
    }
    return applied;
  }

  Future<void> resetAllPullCursors() async {
    final db = await database;
    for (final table in _pendingTableOrder) {
      await db.insert(
        'sync_meta',
        {'key': 'pull_cursor_$table', 'value': '1970-01-01T00:00:00Z'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Terapkan baris remote ke tabel lokal. `payload` memakai kolom remote:
  /// `id` = uuid, kolom FK (sale_id/product_id) berisi uuid. TIDAK menulis outbox.
  /// Return `true` bila baris berhasil diproses (kursor aman maju), `false` bila
  /// masih menunggu induk (disimpan ke sync_pending utk dicoba ulang).
  Future<bool> applyRemoteRow(
    String table,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    final uuid = payload['id'] as String?;
    if (uuid == null) return true;

    final origPayload = Map<String, dynamic>.from(payload);
    final row = Map<String, dynamic>.from(payload);
    row.remove('id');
    row['uuid'] = uuid;

    final remoteTs = _parseTs(row['updated_at'] as String?);

    // ---- Resolve FK: sale_items & customer_ledgers ----
    if (table == 'sale_items') {
      final saleUuid = row.remove('sale_id') as String?;
      if (saleUuid != null && saleUuid.isNotEmpty) {
        final saleId = await _localSaleIdByUuid(saleUuid);
        if (saleId == null) {
          await _savePendingRemote(table, uuid, origPayload);
          return false;
        }
        row['sale_id'] = saleId;
      } else {
        // sale_id kosong/null dari remote -> baris tidak valid, skip
        return true;
      }
      final productUuid = row.remove('product_id') as String?;
      if (productUuid != null && productUuid.isNotEmpty) {
        final productId = await _localProductIdByUuid(productUuid);
        if (productId != null) {
          row['product_id'] = productId;
        } else {
          row['product_id'] = null;
        }
      }
    } else if (table == 'customer_ledgers') {
      final saleUuid = row.remove('sale_id') as String?;
      if (saleUuid != null && saleUuid.isNotEmpty) {
        final saleId = await _localSaleIdByUuid(saleUuid);
        if (saleId == null) {
          await _savePendingRemote(table, uuid, origPayload);
          return false;
        }
        row['sale_id'] = saleId;
      }
    }

    row.remove('deleted_at');
    row.remove('updated_by');
    row.remove('frozen');
    final savedTs = row['updated_at'] as String?;
    row['updated_at'] = (savedTs == null || savedTs.isEmpty)
        ? _now()
        : savedTs;

    // ---- Baris sudah ada secara lokal (UUID sama) ----
    final existingId = await _localIdByUuid(table, uuid);
    if (existingId != null) {
      // Frozen = tidak boleh di-overwrite oleh remote
      if (_isSlotTable(table)) {
        final frozenRow = await db.query(table, columns: ['frozen'],
            where: 'id = ?', whereArgs: [existingId]);
        if (frozenRow.isNotEmpty && (frozenRow.first['frozen'] as int? ?? 0) == 1) {
          return true;
        }
      }
      if (await _localRowNewerThan(table, existingId, remoteTs)) return true;
      row.remove('created_at');
      row['id'] = existingId;
      await db.update(table, row, where: 'id = ?', whereArgs: [existingId]);
      await deletePendingRemote(table, uuid);
      return true;
    }

    // ---- Slot tables: deduplikasi by date (+ name) ----
    if (_isSlotTable(table)) {
      final date = row['date'] as String?;
      if (date == null || date.isEmpty) return true;
      final name = row['name'] as String?;
      final localIds = await _slotLocalIds(table, date, name);
      if (localIds.isEmpty) {
        if ((await slotDeletedSince(table, date, name)).isAfter(remoteTs)) {
          return true;
        }
        await db.insert(table, row);
        await deletePendingRemote(table, uuid);
        return true;
      }
      // Frozen = tidak boleh di-overwrite oleh remote
      final frozenCheck = await db.query(table, columns: ['frozen'],
          where: 'date = ? ${_isNameSlot(table) ? 'AND name = ?' : ''}',
          whereArgs: _isNameSlot(table) ? [date, name] : [date]);
      if (frozenCheck.any((r) => (r['frozen'] as int? ?? 0) == 1)) {
        return true;
      }
      // Slot sudah terisi: bandingkan updated_at (LWW).
      // Ambil max updated_at dari SEMUA baris slot (bukan hanya satu).
      final maxLocal = await _maxSlotUpdatedAt(table, date, name);
      if (maxLocal.isAfter(remoteTs)) return true;
      // Remote lebih baru: hapus semua baris lama, insert remote.
      for (final id in localIds) {
        await db.delete(table, where: 'id = ?', whereArgs: [id]);
      }
      await db.insert(table, row);
      await deletePendingRemote(table, uuid);
      return true;
    }

    await db.insert(table, row);
    await deletePendingRemote(table, uuid);
    return true;
  }

  Future<void> applyRemoteDelete(
    String table,
    String uuid, [
    Map<String, dynamic>? row,
  ]) async {
    final db = await database;
    await deletePendingRemote(table, uuid);
    if (_isSlotTable(table)) {
      final date = row?['date'] as String?;
      if (date == null || date.isEmpty) {
        await db.delete(table, where: 'uuid = ?', whereArgs: [uuid]);
        return;
      }
      final name = row?['name'] as String?;
      final tomb = _parseTs(row?['updated_at'] as String?);
      // Cek apakah tombstone ini UUID-nya ada di lokal.
      // Jika TIDAK ada, ini tombstone lama (stale) dari record yang sudah
      // di-replace oleh materialisasi "copy & putus". SKIP saja — jangan
      // hapus record materialisasi baru yang UUID-nya beda.
      final tombLocalId = await _localIdByUuid(table, uuid);
      if (tombLocalId == null) {
        // Tombstone tidak match lokal. Update marker tapi jangan hapus.
        if (tomb.isAfter(await slotDeletedSince(table, date, name))) {
          await markSlotDeleted(table, date, name, at: tomb);
        }
        return;
      }
      final localIds = await _slotLocalIds(table, date, name);
      if (localIds.isEmpty) {
        await db.delete(table, where: 'uuid = ?', whereArgs: [uuid]);
        if (tomb.isAfter(await slotDeletedSince(table, date, name))) {
          await markSlotDeleted(table, date, name, at: tomb);
        }
        return;
      }
      // Frozen = jangan hapus
      final frozenCheck = await db.query(table, columns: ['frozen'],
          where: 'date = ? ${_isNameSlot(table) ? 'AND name = ?' : ''}',
          whereArgs: _isNameSlot(table) ? [date, name] : [date]);
      if (frozenCheck.any((r) => (r['frozen'] as int? ?? 0) == 1)) {
        return;
      }
      // Delete = peniadaan seluruh slot; hanya berlaku jika ts-nya lebih baru
      // dari nilai slot lokal saat ini.
      final maxLocal = await _maxSlotUpdatedAt(table, date, name);
      if (!tomb.isAfter(maxLocal)) return;
      for (final id in localIds) {
        await db.delete(table, where: 'id = ?', whereArgs: [id]);
      }
      await markSlotDeleted(table, date, name, at: tomb);
      final left = await db.query(
        table,
        columns: ['id'],
        where: 'date = ?',
        whereArgs: [date],
      );
      if (left.isEmpty) await markDayMaterialized(table, date, at: tomb);
      return;
    }
    // Non-slot: LWW guard — jangan hapus baris lokal yang diedit LEBIH BARU
    // daripada tombstone (device lain sudah lanjut mengedit setelah dihapus).
    final existingId = await _localIdByUuid(table, uuid);
    if (existingId != null) {
      final tomb = _parseTs(row?['updated_at'] as String?);
      if (await _localRowNewerThan(table, existingId, tomb)) return;
    }
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
    if (oldVersion < 6) {
      await _createSyncTables(db);
    }
    if (oldVersion < 7) {
      for (final table in _slotTables) {
        final cols = await db.rawQuery('PRAGMA table_info($table)');
        final names = cols.map((c) => c['name']).toSet();
        if (!names.contains('frozen')) {
          await db.execute('ALTER TABLE $table ADD COLUMN frozen INTEGER DEFAULT 0');
        }
      }
      // Freeze all historical dates (before today) on upgrade
      final today = DateTime.now().toIso8601String().substring(0, 10);
      for (final table in _slotTables) {
        await db.update(table, {'frozen': 1},
            where: 'date < ? AND date != "" AND date IS NOT NULL',
            whereArgs: [today]);
      }
    }
  }

  Future<void> _createSyncTables(Database db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL, operation TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT, synced_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS sync_meta (key TEXT PRIMARY KEY, value TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS sync_pending (id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL, uuid TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT, UNIQUE (table_name, uuid))''',
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
      '''CREATE TABLE oil_stocks (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, qty REAL DEFAULT 0, price REAL DEFAULT 0, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT, frozen INTEGER DEFAULT 0)''',
    );
    await db.execute(
      '''CREATE TABLE stock_managements (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, name TEXT NOT NULL, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, batches TEXT, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT, frozen INTEGER DEFAULT 0)''',
    );
    await db.execute(
      '''CREATE TABLE stock_remainings (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, name TEXT NOT NULL, qty REAL DEFAULT 0, price INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT, frozen INTEGER DEFAULT 0)''',
    );
    await db.execute(
      '''CREATE TABLE customer_ledgers (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER DEFAULT 0, type TEXT NOT NULL, note TEXT, sale_id INTEGER, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT, FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE)''',
    );
    await db.execute(
      '''CREATE TABLE personal_ledgers (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER DEFAULT 0, note TEXT, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT, frozen INTEGER DEFAULT 0)''',
    );
    await db.execute(
      '''CREATE TABLE saldo_deductions (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, a INTEGER DEFAULT 0, b INTEGER DEFAULT 0, note TEXT, created_at TEXT, updated_at TEXT, uuid TEXT, deleted_at TEXT, frozen INTEGER DEFAULT 0)''',
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

  /// Cari transaksi berdasarkan nama pelanggan pada satu tanggal.
  Future<List<Sale>> searchSales(String date, String query) async {
    final db = await database;
    final maps = await db.query(
      'sales',
      where: 'date = ? AND name LIKE ? COLLATE NOCASE',
      whereArgs: [date, '%${query.trim()}%'],
      orderBy: 'id ASC',
      limit: 50,
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
    if (value) {
      // Cari hutang belum lunas dari customer yang sama (sebelum tanggal ini)
      final saleRows = await db.query('sales',
          columns: ['name', 'date', 'paid', 'rounded_total'],
          where: 'id = ?', whereArgs: [saleId]);
      if (saleRows.isEmpty) return;
      final sale = saleRows.first;
      final prevSale = await getPreviousUnpaidSale(
          sale['name'] as String, sale['date'] as String);
      final prevDiff = prevSale?.diff ?? 0;
      // debtPaidAmount = jumlah yang dialokasikan ke bayar hutang kemarin
      final paid = sale['paid'] as int;
      final debtPaidAmount = prevDiff > 0
          ? (paid > prevDiff ? prevDiff : paid)
          : 0;
      final roundedTotal = sale['rounded_total'] as int;
      final newDiff = roundedTotal - (paid - debtPaidAmount);
      await db.update(
        'sales',
        {
          'debt_paid': 1,
          'debt_paid_amount': debtPaidAmount,
          'diff': newDiff,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
    } else {
      // Reset: semua bayar untuk hari ini
      final saleRows = await db.query('sales',
          columns: ['paid', 'rounded_total'],
          where: 'id = ?', whereArgs: [saleId]);
      if (saleRows.isEmpty) return;
      final sale = saleRows.first;
      final paid = sale['paid'] as int;
      final roundedTotal = sale['rounded_total'] as int;
      await db.update(
        'sales',
        {
          'debt_paid': 0,
          'debt_paid_amount': 0,
          'diff': roundedTotal - paid,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
    }
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
  Future<int> insertOilStock(OilStock oil, {String? uuid}) async {
    final db = await database;
    final data = oil.toMap();
    data.remove('id');
    data.remove('frozen');
    final rowUuid = uuid ?? newUuid();
    data['uuid'] = rowUuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('oil_stocks', data);
    await _enqueueOutbox('oil_stocks', 'insert', data, rowUuid);
    return id;
  }

  Future<int> updateOilStock(OilStock oil) async {
    final db = await database;
    // Auto-unfreeze jika frozen (edit transparan)
    final wasFrozen = await _isRowFrozen(db, 'oil_stocks', oil.id);
    if (wasFrozen) await unfreezeSlot('oil_stocks', oil.date ?? '');
    final data = oil.toMap();
    data['updated_at'] = _now();
    data.remove('frozen');
    final id = await db.update(
      'oil_stocks',
      data,
      where: 'id = ?',
      whereArgs: [oil.id],
    );
    if (oil.id != null) {
      await _enqueueRow('oil_stocks', 'update', oil.id!);
    }
    // Auto re-freeze
    if (wasFrozen) await freezeSlot('oil_stocks', oil.date ?? '');
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
    final raw = await _latestSlotRows('oil_stocks', beforeDate);
    // Satu baris slot pertama = tanggal terbaru dgn updated_at terbesar.
    if (raw.isEmpty) return null;
    return OilStock.fromMap(raw.first);
  }

  /// Copy & putus minyak: jika [date] belum punya catatan, salin nilai hari
  /// terakhir sebelumnya menjadi milik [date] (id baru).
  Future<bool> isDayMaterialized(String table, String date) async {
    final v = await getSyncMeta('mater_${table}_$date');
    return v != null && v.isNotEmpty;
  }

  Future<void> markDayMaterialized(
    String table,
    String date, {
    DateTime? at,
  }) async {
    await setSyncMeta(
      'mater_${table}_$date',
      (at ?? DateTime.now()).toIso8601String(),
    );
  }

  Future<void> markSlotDeleted(
    String table,
    String date,
    String? name, {
    DateTime? at,
  }) async {
    final key = (name == null || name.isEmpty)
        ? 'del|$table|$date'
        : 'del|$table|$date|$name';
    await setSyncMeta(key, (at ?? DateTime.now()).toIso8601String());
  }

  Future<bool> isSlotDeleted(
    String table,
    String date,
    String? name,
  ) async {
    final key = (name == null || name.isEmpty)
        ? 'del|$table|$date'
        : 'del|$table|$date|$name';
    final v = await getSyncMeta(key);
    return v != null && v.isNotEmpty;
  }

  /// Waktu terakhir slot ini sengaja dihapus (timestamp marker). Missing /
  /// legacy bernilai epoch sehingga baris remote dengan ts nyata boleh masuk.
  Future<DateTime> slotDeletedSince(
    String table,
    String date,
    String? name,
  ) async {
    final key = (name == null || name.isEmpty)
        ? 'del|$table|$date'
        : 'del|$table|$date|$name';
    final v = await getSyncMeta(key);
    if (v == null || v.isEmpty) return _epoch;
    return DateTime.tryParse(v) ?? _epoch;
  }

  Future<void> clearMaterializedFlag(String table, String date) async {
    final key = 'mater_${table}_$date';
    final db = await database;
    await db.delete('sync_meta', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> clearSlotDeletedFlags(String table, String date) async {
    final db = await database;
    await db.delete('sync_meta',
        where: "key LIKE ? AND key LIKE ?",
        whereArgs: ['del|$table|$date%', 'del|$table|$date|%']);
  }

  Future<void> clearAllSlotFlags(String table, String date) async {
    await clearMaterializedFlag(table, date);
    await clearSlotDeletedFlags(table, date);
  }

  // ==================== FREEZE HELPERS ====================
  Future<void> freezeSlot(String table, String date, {String? name}) async {
    final db = await database;
    if (_isNameSlot(table) && name != null) {
      await db.update(table, {'frozen': 1},
          where: 'date = ? AND name = ?', whereArgs: [date, name]);
    } else {
      await db.update(table, {'frozen': 1},
          where: 'date = ?', whereArgs: [date]);
    }
  }

  Future<void> unfreezeSlot(String table, String date, {String? name}) async {
    final db = await database;
    if (_isNameSlot(table) && name != null) {
      await db.update(table, {'frozen': 0},
          where: 'date = ? AND name = ?', whereArgs: [date, name]);
    } else {
      await db.update(table, {'frozen': 0},
          where: 'date = ?', whereArgs: [date]);
    }
  }

  Future<void> freezeDateAllSlots(String date) async {
    for (final table in _slotTables) {
      await freezeSlot(table, date);
    }
  }

  Future<bool> _isRowFrozen(Database db, String table, int? id) async {
    if (id == null) return false;
    final r = await db.query(table, columns: ['frozen'],
        where: 'id = ?', whereArgs: [id]);
    return r.isNotEmpty && (r.first['frozen'] as int? ?? 0) == 1;
  }

  Future<OilStock?> materializeOilStock(String date) async {
    var existing = await getOilStocksByDate(date);
    if (existing.isNotEmpty) {
      await markDayMaterialized('oil_stocks', date);
      return existing.first;
    }
    // Flag set tapi data kosong (habis dihapus sync/tombstone) → clear & retry
    if (await isDayMaterialized('oil_stocks', date)) {
      await clearAllSlotFlags('oil_stocks', date);
      existing = await getOilStocksByDate(date);
      if (existing.isNotEmpty) {
        await markDayMaterialized('oil_stocks', date);
        return existing.first;
      }
    }
    final latest = await getLatestOilStock(date);
    if (latest == null) return null;
    await insertOilStock(
      OilStock(date: date, qty: latest.qty, price: latest.price),
      uuid: slotUuid('oil_stocks', date, null),
    );
    await markDayMaterialized('oil_stocks', date);
    final srcDate = await _latestSlotDate('oil_stocks', date);
    if (srcDate != null && srcDate.isNotEmpty) {
      await freezeSlot('oil_stocks', srcDate);
    }
    final rows = await getOilStocksByDate(date);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Nilai minyak TERAKHIR dalam rentang bulan (untuk total ringkasan).
  Future<OilStock?> getLatestOilStockByMonth(
    String startDate,
    String endDate,
  ) async {
    final all = await getOilStocksByMonth(startDate, endDate);
    if (all.isEmpty) return null;
    return all.reduce((a, b) => (a.date ?? '').compareTo(b.date ?? '') >= 0 ? a : b);
  }

  Future<int> deleteOilStock(int id) async {
    final db = await database;
    final dayRow = await db.query(
      'oil_stocks',
      columns: ['date'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final day = dayRow.isNotEmpty ? dayRow.first['date'] as String? : null;
    await _enqueueDeleteById('oil_stocks', id);
    final affected = await db.delete('oil_stocks', where: 'id = ?', whereArgs: [id]);
    if (affected > 0 && day != null) {
      await markSlotDeleted('oil_stocks', day, null);
      final left = await db.query('oil_stocks', where: 'date = ?', whereArgs: [day]);
      if (left.isEmpty) await markDayMaterialized('oil_stocks', day);
    }
    return affected;
  }

  // ==================== STOCK MANAGEMENTS ====================
  Future<int> insertStockManagement(StockManagement sm, {String? uuid}) async {
    final db = await database;
    final data = sm.toMap();
    data.remove('id');
    data.remove('frozen');
    final rowUuid = uuid ?? newUuid();
    data['uuid'] = rowUuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('stock_managements', data);
    await _enqueueOutbox('stock_managements', 'insert', data, rowUuid);
    return id;
  }

  Future<int> updateStockManagement(StockManagement sm) async {
    final db = await database;
    final wasFrozen = await _isRowFrozen(db, 'stock_managements', sm.id);
    if (wasFrozen) await unfreezeSlot('stock_managements', sm.date ?? '', name: sm.name);
    final data = sm.toMap();
    data['updated_at'] = _now();
    data.remove('frozen');
    final id = await db.update(
      'stock_managements',
      data,
      where: 'id = ?',
      whereArgs: [sm.id],
    );
    if (sm.id != null) {
      await _enqueueRow('stock_managements', 'update', sm.id!);
    }
    if (wasFrozen) await freezeSlot('stock_managements', sm.date ?? '', name: sm.name);
    return id;
  }

  Future<List<StockManagement>> getStockManagementsByMonth(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final maps = await db.query(
      'stock_managements',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'id ASC',
    );
    return maps.map((m) => StockManagement.fromMap(m)).toList();
  }

  Future<List<StockManagement>> getStockManagementsByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'stock_managements',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => StockManagement.fromMap(m)).toList();
  }

  Future<List<StockManagement>> getLatestStockManagements(
    String beforeDate,
  ) async {
    final raw = await _latestSlotRows('stock_managements', beforeDate);
    return raw.map((m) => StockManagement.fromMap(m)).toList();
  }

  /// Copy & putus stok pemegang: jika [date] belum punya catatan, salin
  /// record terakhir tiap pemegang (dengan nilai sak-nya) menjadi milik [date]
  /// dengan id record & id batch baru.
  Future<List<StockManagement>> materializeStockManagements(String date) async {
    var existing = await getStockManagementsByDate(date);
    if (existing.isNotEmpty) {
      await markDayMaterialized('stock_managements', date);
      return existing;
    }
    if (await isDayMaterialized('stock_managements', date)) {
      await clearAllSlotFlags('stock_managements', date);
      existing = await getStockManagementsByDate(date);
      if (existing.isNotEmpty) {
        await markDayMaterialized('stock_managements', date);
        return existing;
      }
    }
    final latestAll = await getLatestStockManagements(date);
    if (latestAll.isEmpty) return [];
    final byName = <String, StockManagement>{};
    for (final sm in latestAll) {
      byName.putIfAbsent(sm.name, () => sm);
    }
    for (final src in byName.values) {
      final srcBatches = src.batches ?? [];
      final copiedBatches = srcBatches.isNotEmpty
          ? <Map<String, dynamic>>[
              for (int i = 0; i < srcBatches.length; i++)
                {
                  'id': '${DateTime.now().microsecondsSinceEpoch}_$i',
                  'date': date,
                  'price': (srcBatches[i]['price'] as num?)?.toInt() ?? src.price,
                  'sacks': [
                    for (final s in ((srcBatches[i]['sacks'] as List?) ?? []))
                      (s as num).toDouble(),
                  ],
                },
            ]
          : null;
      await insertStockManagement(
        StockManagement(
          date: date,
          name: src.name,
          qty: src.qty,
          price: src.price,
          batches: copiedBatches,
        ),
        uuid: slotUuid('stock_managements', date, src.name),
      );
    }
    await markDayMaterialized('stock_managements', date);
    final srcDate = await _latestSlotDate('stock_managements', date);
    if (srcDate != null && srcDate.isNotEmpty) {
      await freezeSlot('stock_managements', srcDate);
    }
    return getStockManagementsByDate(date);
  }

  /// Record stok pemegang TERAKHIR per nama dalam rentang bulan.
  Future<List<StockManagement>> getLatestStockManagementsByMonth(
    String startDate,
    String endDate,
  ) async {
    final raw =
        await _latestNameRowsInMonth('stock_managements', startDate, endDate);
    return raw.map((m) => StockManagement.fromMap(m)).toList();
  }

  Future<int> deleteStockManagement(int id) async {
    final db = await database;
    final dayRow = await db.query(
      'stock_managements',
      columns: ['date', 'name'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final day =
        dayRow.isNotEmpty ? dayRow.first['date'] as String? : null;
    final name =
        dayRow.isNotEmpty ? dayRow.first['name'] as String? : null;
    await _enqueueDeleteById('stock_managements', id);
    final affected = await db.delete(
      'stock_managements',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected > 0 && day != null) {
      await markSlotDeleted('stock_managements', day, name);
      final left = await db.query(
        'stock_managements',
        where: 'date = ?',
        whereArgs: [day],
      );
      if (left.isEmpty) await markDayMaterialized('stock_managements', day);
    }
    return affected;
  }

  // ==================== STOCK REMAININGS ====================
  Future<int> insertStockRemaining(StockRemaining sr, {String? uuid}) async {
    final db = await database;
    final data = sr.toMap();
    data.remove('id');
    data.remove('frozen');
    final rowUuid = uuid ?? newUuid();
    data['uuid'] = rowUuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('stock_remainings', data);
    await _enqueueOutbox('stock_remainings', 'insert', data, rowUuid);
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
    final raw = await _latestSlotRows('stock_remainings', beforeDate);
    return raw.map((m) => StockRemaining.fromMap(m)).toList();
  }

  /// Copy & putus sisa barang: jika [date] belum punya catatan, salin record
  /// terakhir tiap nama barang menjadi milik [date] (id baru).
  Future<List<StockRemaining>> materializeStockRemainings(String date) async {
    var existing = await getStockRemainingsByDate(date);
    if (existing.isNotEmpty) {
      await markDayMaterialized('stock_remainings', date);
      return existing;
    }
    if (await isDayMaterialized('stock_remainings', date)) {
      await clearAllSlotFlags('stock_remainings', date);
      existing = await getStockRemainingsByDate(date);
      if (existing.isNotEmpty) {
        await markDayMaterialized('stock_remainings', date);
        return existing;
      }
    }
    final latestAll = await getLatestStockRemainings(date);
    if (latestAll.isEmpty) return [];
    final byName = <String, StockRemaining>{};
    for (final sr in latestAll) {
      byName.putIfAbsent(sr.name, () => sr);
    }
    for (final src in byName.values) {
      await insertStockRemaining(
        StockRemaining(
          date: date,
          name: src.name,
          qty: src.qty,
          price: src.price,
        ),
        uuid: slotUuid('stock_remainings', date, src.name),
      );
    }
    await markDayMaterialized('stock_remainings', date);
    final srcDate = await _latestSlotDate('stock_remainings', date);
    if (srcDate != null && srcDate.isNotEmpty) {
      await freezeSlot('stock_remainings', srcDate);
    }
    return getStockRemainingsByDate(date);
  }

  /// Record sisa barang TERAKHIR per nama dalam rentang bulan.
  Future<List<StockRemaining>> getLatestStockRemainingsByMonth(
    String startDate,
    String endDate,
  ) async {
    final raw =
        await _latestNameRowsInMonth('stock_remainings', startDate, endDate);
    return raw.map((m) => StockRemaining.fromMap(m)).toList();
  }

  Future<int> deleteStockRemaining(int id) async {
    final db = await database;
    final dayRow = await db.query(
      'stock_remainings',
      columns: ['date', 'name'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final day = dayRow.isNotEmpty ? dayRow.first['date'] as String? : null;
    final name = dayRow.isNotEmpty ? dayRow.first['name'] as String? : null;
    await _enqueueDeleteById('stock_remainings', id);
    final affected = await db.delete(
      'stock_remainings',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected > 0 && day != null) {
      await markSlotDeleted('stock_remainings', day, name);
      final left = await db.query(
        'stock_remainings',
        where: 'date = ?',
        whereArgs: [day],
      );
      if (left.isEmpty) await markDayMaterialized('stock_remainings', day);
    }
    return affected;
  }

  Future<int> updateStockRemaining(StockRemaining sr) async {
    final db = await database;
    final wasFrozen = await _isRowFrozen(db, 'stock_remainings', sr.id);
    if (wasFrozen) await unfreezeSlot('stock_remainings', sr.date ?? '', name: sr.name);
    final data = sr.toMap();
    data['updated_at'] = _now();
    data.remove('frozen');
    final id = await db.update(
      'stock_remainings',
      data,
      where: 'id = ?',
      whereArgs: [sr.id],
    );
    if (sr.id != null) await _enqueueRow('stock_remainings', 'update', sr.id!);
    if (wasFrozen) await freezeSlot('stock_remainings', sr.date ?? '', name: sr.name);
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
  Future<int> insertPersonalLedger(PersonalLedger ledger, {String? uuid}) async {
    final db = await database;
    final data = ledger.toMap();
    data.remove('id');
    data.remove('frozen');
    final rowUuid = uuid ?? newUuid();
    data['uuid'] = rowUuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('personal_ledgers', data);
    await _enqueueOutbox('personal_ledgers', 'insert', data, rowUuid);
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
    final raw = await _latestSlotRows('personal_ledgers', beforeDate);
    return raw.map((m) => PersonalLedger.fromMap(m)).toList();
  }

  /// Copy & putus hutang pribadi: jika [date] belum punya catatan, salin
  /// record terakhir tiap nama menjadi milik [date] (id baru).
  Future<List<PersonalLedger>> materializePersonalLedgers(String date) async {
    var existing = await getPersonalLedgersByDate(date);
    if (existing.isNotEmpty) {
      await markDayMaterialized('personal_ledgers', date);
      return existing;
    }
    if (await isDayMaterialized('personal_ledgers', date)) {
      await clearAllSlotFlags('personal_ledgers', date);
      existing = await getPersonalLedgersByDate(date);
      if (existing.isNotEmpty) {
        await markDayMaterialized('personal_ledgers', date);
        return existing;
      }
    }
    final latestAll = await getLatestPersonalLedgers(date);
    if (latestAll.isEmpty) return [];
    final byName = <String, PersonalLedger>{};
    for (final l in latestAll) {
      byName.putIfAbsent(l.name, () => l);
    }
    for (final src in byName.values) {
      await insertPersonalLedger(
        PersonalLedger(
          date: date,
          name: src.name,
          amount: src.amount,
          note: src.note,
        ),
        uuid: slotUuid('personal_ledgers', date, src.name),
      );
    }
    await markDayMaterialized('personal_ledgers', date);
    final srcDate = await _latestSlotDate('personal_ledgers', date);
    if (srcDate != null && srcDate.isNotEmpty) {
      await freezeSlot('personal_ledgers', srcDate);
    }
    return getPersonalLedgersByDate(date);
  }

  /// Record hutang pribadi TERAKHIR per nama dalam rentang bulan.
  Future<List<PersonalLedger>> getLatestPersonalLedgersByMonth(
    String startDate,
    String endDate,
  ) async {
    final raw =
        await _latestNameRowsInMonth('personal_ledgers', startDate, endDate);
    return raw.map((m) => PersonalLedger.fromMap(m)).toList();
  }

  Future<int> deletePersonalLedger(int id) async {
    final db = await database;
    final dayRow = await db.query(
      'personal_ledgers',
      columns: ['date', 'name'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final day = dayRow.isNotEmpty ? dayRow.first['date'] as String? : null;
    final name = dayRow.isNotEmpty ? dayRow.first['name'] as String? : null;
    await _enqueueDeleteById('personal_ledgers', id);
    final affected = await db.delete(
      'personal_ledgers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected > 0 && day != null) {
      await markSlotDeleted('personal_ledgers', day, name);
      final left = await db.query(
        'personal_ledgers',
        where: 'date = ?',
        whereArgs: [day],
      );
      if (left.isEmpty) await markDayMaterialized('personal_ledgers', day);
    }
    return affected;
  }

  Future<int> updatePersonalLedger(PersonalLedger ledger) async {
    final db = await database;
    final wasFrozen = await _isRowFrozen(db, 'personal_ledgers', ledger.id);
    if (wasFrozen) await unfreezeSlot('personal_ledgers', ledger.date ?? '', name: ledger.name);
    final data = ledger.toMap();
    data.remove('id');
    data.remove('date');
    data.remove('created_at');
    data.remove('frozen');
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
    if (wasFrozen) await freezeSlot('personal_ledgers', ledger.date ?? '', name: ledger.name);
    return id;
  }

  // ==================== SALDO DEDUCTIONS ====================
  Future<int> insertSaldoDeduction(SaldoDeduction saldo, {String? uuid}) async {
    final db = await database;
    final data = saldo.toMap();
    data.remove('id');
    data.remove('frozen');
    final rowUuid = uuid ?? newUuid();
    data['uuid'] = rowUuid;
    data['created_at'] = _now();
    data['updated_at'] = _now();
    final id = await db.insert('saldo_deductions', data);
    await _enqueueOutbox('saldo_deductions', 'insert', data, rowUuid);
    return id;
  }

  Future<int> updateSaldoDeduction(SaldoDeduction saldo) async {
    final db = await database;
    final wasFrozen = await _isRowFrozen(db, 'saldo_deductions', saldo.id);
    if (wasFrozen) await unfreezeSlot('saldo_deductions', saldo.date ?? '');
    final data = saldo.toMap();
    data['updated_at'] = _now();
    data.remove('frozen');
    final id = await db.update(
      'saldo_deductions',
      data,
      where: 'id = ?',
      whereArgs: [saldo.id],
    );
    if (saldo.id != null) {
      await _enqueueRow('saldo_deductions', 'update', saldo.id!);
    }
    if (wasFrozen) await freezeSlot('saldo_deductions', saldo.date ?? '');
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
    final raw = await _latestSlotRows('saldo_deductions', beforeDate);
    // Satu baris slot pertama = tanggal terbaru dgn updated_at terbesar.
    if (raw.isEmpty) return null;
    return SaldoDeduction.fromMap(raw.first);
  }

  /// Copy & putus pengurangan saldo: jika [date] belum punya catatan, salin
  /// nilai terakhir sebelumnya menjadi milik [date] (id baru).
  Future<SaldoDeduction?> materializeSaldoDeduction(String date) async {
    var existing = await getSaldoDeductionsByDate(date);
    if (existing.isNotEmpty) {
      await markDayMaterialized('saldo_deductions', date);
      return existing.first;
    }
    if (await isDayMaterialized('saldo_deductions', date)) {
      await clearAllSlotFlags('saldo_deductions', date);
      existing = await getSaldoDeductionsByDate(date);
      if (existing.isNotEmpty) {
        await markDayMaterialized('saldo_deductions', date);
        return existing.first;
      }
    }
    final latest = await getLatestSaldoDeduction(date);
    if (latest == null) return null;
    await insertSaldoDeduction(
      SaldoDeduction(
        date: date,
        a: latest.a,
        b: latest.b,
        note: latest.note,
      ),
      uuid: slotUuid('saldo_deductions', date, null),
    );
    await markDayMaterialized('saldo_deductions', date);
    final srcDate = await _latestSlotDate('saldo_deductions', date);
    if (srcDate != null && srcDate.isNotEmpty) {
      await freezeSlot('saldo_deductions', srcDate);
    }
    final rows = await getSaldoDeductionsByDate(date);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Nilai pengurangan saldo TERAKHIR dalam rentang bulan.
  Future<SaldoDeduction?> getLatestSaldoDeductionByMonth(
    String startDate,
    String endDate,
  ) async {
    final all = await getSaldoDeductionsByMonth(startDate, endDate);
    if (all.isEmpty) return null;
    return all.reduce((a, b) => (a.date ?? '').compareTo(b.date ?? '') >= 0 ? a : b);
  }

  Future<int> deleteSaldoDeduction(int id) async {
    final db = await database;
    final dayRow = await db.query(
      'saldo_deductions',
      columns: ['date'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final day = dayRow.isNotEmpty ? dayRow.first['date'] as String? : null;
    await _enqueueDeleteById('saldo_deductions', id);
    final affected = await db.delete(
      'saldo_deductions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected > 0 && day != null) {
      await markSlotDeleted('saldo_deductions', day, null);
      final left = await db.query(
        'saldo_deductions',
        where: 'date = ?',
        whereArgs: [day],
      );
      if (left.isEmpty) await markDayMaterialized('saldo_deductions', day);
    }
    return affected;
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

  /// Hapus hanya tabel data Hasil (slot "copy & putus") pada rentang tanggal
  /// tertentu. Tidak menyentuh sales, expenses, customer_ledgers, maupun
  /// products.
  Future<void> clearSlotDataByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    const tables = [
      'oil_stocks',
      'stock_managements',
      'stock_remainings',
      'personal_ledgers',
      'saldo_deductions',
    ];
    for (final table in tables) {
      await _enqueueBulkDelete(table, 'date BETWEEN ? AND ?', [
        startDate,
        endDate,
      ]);
      await db.delete(
        table,
        where: 'date BETWEEN ? AND ?',
        whereArgs: [startDate, endDate],
      );
    }
  }

  /// Rapikan duplikat baris slot (date[,name]): pertahankan satu baris dengan
  /// `updated_at` terbesar per slot (aturan LWW yang sama dengan tampilan),
  /// hapus sisanya secara lokal + tombstone (agar cloud & HP lain ikut rapi).
  /// Idempoten: tidak melakukan apa-apa bila sudah bersih. Dipanggil saat
  /// "Perbaiki Data" untuk membersihkan jumlah / sumber copy yang nyasar dari
  /// era uuid acak.
  Future<int> repairSlotDuplicates() async {
    final db = await database;
    var repaired = 0;
    for (final table in _slotTables) {
      final maps = await db.query(table, orderBy: 'id ASC');
      final bySlot = <String, List<Map<String, dynamic>>>{};
      for (final m in maps) {
        final date = m['date'] as String? ?? '';
        final nm = _isNameSlot(table) ? (m['name'] as String? ?? '') : '';
        final key = '$date|$nm';
        bySlot.putIfAbsent(key, () => []).add(m);
      }
      for (final group in bySlot.values) {
        if (group.length <= 1) continue;
        // Frozen rows always win — never delete them
        final hasFrozen = group.any((r) => (r['frozen'] as int? ?? 0) == 1);
        if (hasFrozen) {
          // Only delete non-frozen duplicates
          for (final r in group) {
            if ((r['frozen'] as int? ?? 0) == 1) continue;
            final uuid = r['uuid'] as String?;
            if (uuid == null || uuid.isEmpty) continue;
            await _enqueueDeleteById(table, r['id'] as int);
            await db.delete(table, where: 'id = ?', whereArgs: [r['id'] as int]);
            repaired++;
          }
          continue;
        }
        group.sort((a, b) {
          final ta = _parseTs(a['updated_at'] as String?);
          final tb = _parseTs(b['updated_at'] as String?);
          final c = tb.compareTo(ta);
          if (c != 0) return c;
          return (a['id'] as int).compareTo(b['id'] as int);
        });
        for (final r in group.skip(1)) {
          final uuid = r['uuid'] as String?;
          if (uuid == null || uuid.isEmpty) continue;
          await _enqueueDeleteById(table, r['id'] as int);
          await db.delete(
            table,
            where: 'id = ?',
            whereArgs: [r['id'] as int],
          );
          repaired++;
        }
      }
    }
    return repaired;
  }

  /// Hapus sale_items yang sale_id-nya null atau tidak memiliki sales record
  /// yang valid. Ini terjadi jika sync pull gagal resolve FK.
  Future<int> repairOrphanedSaleItems() async {
    final db = await database;
    final orphaned = await db.rawQuery('''
      SELECT si.id FROM sale_items si
      LEFT JOIN sales s ON si.sale_id = s.id
      WHERE s.id IS NULL OR si.sale_id IS NULL
    ''');
    var repaired = 0;
    for (final row in orphaned) {
      final id = row['id'] as int;
      await _enqueueDeleteById('sale_items', id);
      await db.delete('sale_items', where: 'id = ?', whereArgs: [id]);
      repaired++;
    }
    return repaired;
  }

  /// Hapus customer_ledgers yang sale_id-nya tidak null tapi tidak memiliki
  /// sales record yang valid (kecuali hutang manual yang memang tanpa sale).
  Future<int> repairOrphanedCustomerLedgers() async {
    final db = await database;
    final orphaned = await db.rawQuery('''
      SELECT cl.id FROM customer_ledgers cl
      LEFT JOIN sales s ON cl.sale_id = s.id
      WHERE cl.sale_id IS NOT NULL AND s.id IS NULL
    ''');
    var repaired = 0;
    for (final row in orphaned) {
      final id = row['id'] as int;
      await _enqueueDeleteById('customer_ledgers', id);
      await db.delete('customer_ledgers', where: 'id = ?', whereArgs: [id]);
      repaired++;
    }
    return repaired;
  }

  /// Jalankan semua perbaikan data sekaligus. Mengembalikan jumlah total
  /// baris yang diperbaiki/dihapus.
  Future<int> repairAll() async {
    final d1 = await repairSlotDuplicates();
    final d2 = await repairOrphanedSaleItems();
    final d3 = await repairOrphanedCustomerLedgers();
    final total = d1 + d2 + d3;
    if (total > 0) {
      debugPrint(
        'REPAIR: slot_dup=$d1 orphan_sale=$d2 orphan_ledger=$d3 total=$total',
      );
    }
    return total;
  }

  /// Repair AGRESIF: dipanggil saat startup untuk memperbaiki data yang
  /// sudah terlanjur salah. Membersihkan:
  /// 1. Duplikat di SEMUA tabel (bukan hanya slot)
  /// 2. Orphaned sale_items & customer_ledgers
  /// 3. Recalculate sale.rounded_total & sale.diff dari sale_items
  Future<int> forceRepairAll() async {
    final db = await database;
    var total = 0;

    // 1. Duplikat slot tables (sama seperti repairAll)
    total += await repairSlotDuplicates();

    // 2. Duplikat sales: hapus sales yang identik (date+name+rounded_total+paid)
    //    Pertahankan yang id-nya paling kecil (paling awal dibuat).
    final dupSales = await db.rawQuery('''
      SELECT s1.id FROM sales s1
      INNER JOIN sales s2
        ON s1.date = s2.date
        AND s1.name = s2.name
        AND s1.rounded_total = s2.rounded_total
        AND s1.paid = s2.paid
        AND s1.id > s2.id
    ''');
    for (final row in dupSales) {
      final id = row['id'] as int;
      // Hapus sale_items dulu (FK constraint)
      final items = await db.query('sale_items', columns: ['id'],
          where: 'sale_id = ?', whereArgs: [id]);
      for (final item in items) {
        await _enqueueDeleteById('sale_items', item['id'] as int);
        await db.delete('sale_items', where: 'id = ?',
            whereArgs: [item['id']]);
      }
      // Hapus customer_ledgers terkait
      final ledgers = await db.query('customer_ledgers', columns: ['id'],
          where: 'sale_id = ?', whereArgs: [id]);
      for (final ledger in ledgers) {
        await _enqueueDeleteById('customer_ledgers', ledger['id'] as int);
        await db.delete('customer_ledgers', where: 'id = ?',
            whereArgs: [ledger['id']]);
      }
      await _enqueueDeleteById('sales', id);
      await db.delete('sales', where: 'id = ?', whereArgs: [id]);
      total++;
    }

    // 3. Duplikat expenses: hapus yang identik (date+amount+note)
    final dupExpenses = await db.rawQuery('''
      SELECT e1.id FROM expenses e1
      INNER JOIN expenses e2
        ON e1.date = e2.date
        AND e1.amount = e2.amount
        AND COALESCE(e1.note,'') = COALESCE(e2.note,'')
        AND e1.id > e2.id
    ''');
    for (final row in dupExpenses) {
      final id = row['id'] as int;
      await _enqueueDeleteById('expenses', id);
      await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
      total++;
    }

    // 3b. Duplikat sale_items: hapus item yang product_id sama dalam 1 sale
    // (pertahankan yang id terkecil = paling awal diinput).
    final dupItems = await db.rawQuery('''
      SELECT si1.id FROM sale_items si1
      INNER JOIN sale_items si2
        ON si1.sale_id = si2.sale_id
        AND COALESCE(si1.product_id,'') = COALESCE(si2.product_id,'')
        AND si1.id > si2.id
    ''');
    for (final row in dupItems) {
      final id = row['id'] as int;
      await _enqueueDeleteById('sale_items', id);
      await db.delete('sale_items', where: 'id = ?', whereArgs: [id]);
      total++;
    }

    // 4. Recalculate sale totals dari sale_items yang valid
    final sales = await db.query('sales');
    for (final s in sales) {
      final saleId = s['id'] as int;
      final items = await db.query('sale_items',
          where: 'sale_id = ?', whereArgs: [saleId]);
      final recalcedTotal = items.fold<int>(0, (sum, item) {
        final qty = (item['qty'] as num?)?.toDouble() ?? 0;
        final price = (item['price'] as num?)?.toInt() ?? 0;
        return sum + (qty * price).round();
      });
      final roundedTotal = items.isEmpty
          ? (s['paid'] as int?) ?? 0
          : roundTotal(recalcedTotal);
      final paid = (s['paid'] as int?) ?? 0;
      final debtPaidAmt = (s['debt_paid_amount'] as int?) ?? 0;
      final isDebtPaid = (s['debt_paid'] as int?) == 1;
      // Jika debtPaid aktif, diff hanya untuk hari ini (kurangi bagian kemarin)
      final diff = isDebtPaid
          ? roundedTotal - (paid - debtPaidAmt)
          : roundedTotal - paid;

      // Update jika berubah
      if (roundedTotal != (s['rounded_total'] as int?) ||
          diff != (s['diff'] as int?)) {
        await db.update(
          'sales',
          {
            'raw_total': recalcedTotal,
            'rounded_total': roundedTotal,
            'diff': diff,
            'updated_at': _now(),
          },
          where: 'id = ?',
          whereArgs: [saleId],
        );
        await _enqueueRow('sales', 'update', saleId);
        total++;
      }
    }

    // 5. Fix debtPaid sales yang debtPaidAmount-nya masih 0
    final debtPaidSales = await db.query('sales',
        where: 'debt_paid = 1 AND debt_paid_amount = 0');
    for (final s in debtPaidSales) {
      final saleId = s['id'] as int;
      final name = s['name'] as String;
      final date = s['date'] as String;
      final paid = s['paid'] as int;
      final prevSale = await getPreviousUnpaidSale(name, date);
      final prevDiff = prevSale?.diff ?? 0;
      final debtPaidAmount = prevDiff > 0
          ? (paid > prevDiff ? prevDiff : paid)
          : 0;
      final roundedTotal = s['rounded_total'] as int;
      final newDiff = roundedTotal - (paid - debtPaidAmount);
      await db.update(
        'sales',
        {'debt_paid_amount': debtPaidAmount, 'diff': newDiff},
        where: 'id = ?',
        whereArgs: [saleId],
      );
      await _enqueueRow('sales', 'update', saleId);
      total++;
    }

    // 6. Orphaned records
    total += await repairOrphanedSaleItems();
    total += await repairOrphanedCustomerLedgers();

    if (total > 0) {
      debugPrint('FORCE_REPAIR: fixed $total rows');
    }
    return total;
  }

  // ==================== DUMP DATA ====================
  Future<String> dumpAllData() async {
    final db = await database;
    final sb = StringBuffer();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    sb.writeln('=== DUMP DATA HP - $today ===\n');

    // OIL
    sb.writeln('OIL:');
    final oil = await db.query('oil_stocks', orderBy: 'date DESC, id DESC', limit: 5);
    for (final r in oil) {
      final f = (r['frozen'] as int? ?? 0) == 1 ? ' [FROZEN]' : '';
      sb.writeln('  id=${r['id']} date=${r['date']} qty=${r['qty']} price=${r['price']}$f');
    }

    // STOCK_MGMT
    sb.writeln('\nSTOCK_MGMT:');
    final sm = await db.query('stock_managements', orderBy: 'date DESC, id DESC', limit: 20);
    for (final r in sm) {
      final f = (r['frozen'] as int? ?? 0) == 1 ? ' [FROZEN]' : '';
      sb.writeln('  id=${r['id']} date=${r['date']} name=${r['name']} price=${r['price']} qty=${r['qty']}$f');
    }

    // STOCK_REMAIN
    sb.writeln('\nSTOCK_REMAIN:');
    final sr = await db.query('stock_remainings', orderBy: 'date DESC, id DESC', limit: 20);
    for (final r in sr) {
      final f = (r['frozen'] as int? ?? 0) == 1 ? ' [FROZEN]' : '';
      sb.writeln('  id=${r['id']} date=${r['date']} name=${r['name']} price=${r['price']} qty=${r['qty']} subtotal=${(r['qty'] as double) * (r['price'] as int)}$f');
    }

    // PERSONAL_LEDGER
    sb.writeln('\nPERSONAL_LEDGER:');
    final pl = await db.query('personal_ledgers', orderBy: 'date DESC, id DESC', limit: 20);
    for (final r in pl) {
      final f = (r['frozen'] as int? ?? 0) == 1 ? ' [FROZEN]' : '';
      sb.writeln('  id=${r['id']} date=${r['date']} name=${r['name']} amount=${r['amount']}$f');
    }

    // SALDO_DEDUCTION
    sb.writeln('\nSALDO_DEDUCTION:');
    final sd = await db.query('saldo_deductions', orderBy: 'date DESC, id DESC', limit: 5);
    for (final r in sd) {
      final f = (r['frozen'] as int? ?? 0) == 1 ? ' [FROZEN]' : '';
      sb.writeln('  id=${r['id']} date=${r['date']} a=${r['a']} b=${r['b']}$f');
    }

    final result = sb.toString();
    debugPrint(result);
    return result;
  }

  // ==================== FIX TAB HASIL DATA ====================
  Future<String> fixTabHasilData() async {
    final db = await database;
    final sb = StringBuffer();
    const date = '2026-09-16';
    const prevDate = '2026-09-15';
    const tables = [
      'oil_stocks',
      'stock_managements',
      'stock_remainings',
      'personal_ledgers',
      'saldo_deductions',
    ];
    var fixed = 0;

    sb.writeln('=== FIX TAB HASIL: $date ===\n');

    // 1. Clear materialized_days & slot_deleted flags untuk 2026-09-16
    sb.writeln('1. Clearing flags...');
    for (final t in tables) {
      final matKey = 'mater_${t}_$date';
      final old = await getSyncMeta(matKey);
      if (old != null) {
        await db.delete('sync_meta', where: 'key = ?', whereArgs: [matKey]);
        sb.writeln('  Cleared $matKey (was: $old)');
        fixed++;
      }
    }
    for (final t in tables) {
      for (final key in [
        'del|$t|$date',
        'del|$t|$date|gun',
        'del|$t|$date|MUJILAN',
        'del|$t|$date|my',
        'del|$t|$date|mt',
        'del|$t|$date|259',
      ]) {
        final old = await getSyncMeta(key);
        if (old != null) {
          await db.delete('sync_meta', where: 'key = ?', whereArgs: [key]);
          sb.writeln('  Cleared $key');
          fixed++;
        }
      }
    }
    sb.writeln('  Flags cleared: $fixed\n');

    // 2. Fix STOCK_MGMT 2026-09-15: restore qty sesuai log
    sb.writeln('2. Fixing STOCK_MGMT $prevDate...');
    final smRows = await db.query('stock_managements',
        where: 'date = ?', whereArgs: [prevDate]);
    for (final r in smRows) {
      final name = r['name'] as String;
      final id = r['id'] as int;
      final curQty = (r['qty'] as num).toDouble();
      final price = r['price'] as int;
      double? fixQty;
      if (name == 'gun' && curQty != 100) {
        fixQty = 100;
      } else if (name == 'MUJILAN' && curQty != 25) {
        fixQty = 25;
      }
      if (fixQty != null) {
        final oldSubtotal = (curQty * price).round();
        final newSubtotal = (fixQty * price).round();
        await db.update('stock_managements', {
          'qty': fixQty,
          'updated_at': _now(),
        }, where: 'id = ?', whereArgs: [id]);
        await _enqueueRow('stock_managements', 'update', id);
        sb.writeln('  $name: qty $curQty -> $fixQty (subtotal $oldSubtotal -> $newSubtotal)');
        fixed++;
      }
    }
    sb.writeln('');

    // 3. Delete stale tombstone outbox entries untuk 2026-09-16
    sb.writeln('3. Cleaning outbox tombstones...');
    final outbox = await db.query('outbox', where: 'synced_at IS NULL');
    var cleaned = 0;
    for (final e in outbox) {
      final op = e['operation'] as String;
      if (op != 'delete') continue;
      final raw = e['payload'] as String? ?? '{}';
      if (!raw.contains(date)) continue;
      await db.delete('outbox', where: 'id = ?', whereArgs: [e['id']]);
      cleaned++;
    }
    sb.writeln('  Removed $cleaned stale outbox entries\n');

    // 4. Re-materialize semua slot tables untuk 2026-09-16
    sb.writeln('4. Re-materializing $date...');
    final oil = await materializeOilStock(date);
    sb.writeln('  OIL: ${oil != null ? "qty=${oil.qty}" : "EMPTY"}');

    final sm = await materializeStockManagements(date);
    sb.writeln('  STOCK_MGMT: ${sm.length} records');
    for (final s in sm) {
      sb.writeln('    ${s.name}: qty=${s.qty} price=${s.price} subtotal=${s.subtotal}');
    }

    final sr = await materializeStockRemainings(date);
    sb.writeln('  STOCK_REMAIN: ${sr.length} records');
    for (final s in sr) {
      sb.writeln('    ${s.name}: qty=${s.qty} price=${s.price} subtotal=${s.subtotal}');
    }

    final pl = await materializePersonalLedgers(date);
    sb.writeln('  PERSONAL_LEDGER: ${pl.length} records');
    for (final p in pl) {
      sb.writeln('    ${p.name}: amount=${p.amount}');
    }

    final sd = await materializeSaldoDeduction(date);
    sb.writeln('  SALDO_DEDUCTION: ${sd != null ? "a=${sd.a} b=${sd.b}" : "EMPTY"}');

    // 5. Dump final
    sb.writeln('\n5. Final dump:');
    final finalSm = await db.query('stock_managements',
        where: 'date = ?', whereArgs: [date]);
    sb.writeln('  stock_managements $date: ${finalSm.length} rows');
    for (final r in finalSm) {
      sb.writeln('    ${r['name']}: qty=${r['qty']} price=${r['price']}');
    }
    final finalOil = await db.query('oil_stocks',
        where: 'date = ?', whereArgs: [date]);
    sb.writeln('  oil_stocks $date: ${finalOil.length} rows');
    for (final r in finalOil) {
      sb.writeln('    qty=${r['qty']} price=${r['price']}');
    }
    final finalSr = await db.query('stock_remainings',
        where: 'date = ?', whereArgs: [date]);
    sb.writeln('  stock_remainings $date: ${finalSr.length} rows');
    final finalPl = await db.query('personal_ledgers',
        where: 'date = ?', whereArgs: [date]);
    sb.writeln('  personal_ledgers $date: ${finalPl.length} rows');
    final finalSd = await db.query('saldo_deductions',
        where: 'date = ?', whereArgs: [date]);
    sb.writeln('  saldo_deductions $date: ${finalSd.length} rows');

    final result = sb.toString();
    debugPrint(result);
    return result;
  }
}
