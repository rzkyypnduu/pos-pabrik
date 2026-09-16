import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';

/// Mesin sinkronisasi dua-arah ke Supabase.
///
/// Aliran:
///  - Setiap tulis lokal masuk tabel `outbox`.
///  - Push: upload outbox ke cloud (upsert by `id` = uuid, parent dulu).
///  - Pull: tarik baris yg `updated_at` > kursor per tabel, terapkan lokal.
///  - Realtime: event perubahan cloud memicu pull tabel tsb.
///  - Delete lokal -> tombstone `deleted_at` di cloud (baris tetap ada utk
///    device lain), lalu device lain menghapus baris lokalnya saat pull.
class SyncProvider extends ChangeNotifier {
  static const _keyEnabled = 'sync_enabled';
  static const _keyUrl = 'supabase_url';
  static const _keyAnon = 'supabase_anon_key';
  static const _keyDeviceId = 'sync_device_id';
  static const _keySnapshotDone = 'sync_snapshot_done';
  static const _keyResnapshotDone = 'sync_resnapshot_done';

  /// Urutan penting: tabel induk (products, sales, expenses) harus diproses
  /// lebih dulu agar FK sale_id/product_id pada child terselesaikan.
  static const businessTables = [
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

  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = Uuid();

  SupabaseClient? _client;
  List<RealtimeChannel> _channels = [];
  Timer? _pushTimer;
  Timer? _pullTimer;
  Timer? _reconcileTimer;
  String? _deviceId;

  bool _enabled = false;
  bool _busy = false;
  String? _lastError;
  DateTime? _lastSyncedAt;
  int _pendingCount = 0;
  int _revision = 0;
  int _reconcileCount = 0;

  String? _url;
  String? _anonKey;
  String? get url => _url;
  String? get anonKey => _anonKey;
  bool get enabled => _enabled;
  bool get busy => _busy;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  int get pendingCount => _pendingCount;
  String? get deviceId => _deviceId;
  int get revision => _revision;

  Future<void> loadConfig() async {
    _deviceId = await _db.getSyncMeta(_keyDeviceId);
    if (_deviceId == null) {
      _deviceId = _uuid.v4();
      await _db.setSyncMeta(_keyDeviceId, _deviceId!);
    }
    _url = await _db.getSyncMeta(_keyUrl);
    _anonKey = await _db.getSyncMeta(_keyAnon);
    _enabled = (await _db.getSyncMeta(_keyEnabled)) == '1';
    await _refreshPendingCount();
    notifyListeners();
    if (_enabled) _startEngine();
  }

  Future<void> saveConfig({
    required String url,
    required String anonKey,
    required bool enabled,
  }) async {
    _url = url.trim();
    _anonKey = anonKey.trim();
    _enabled = enabled;
    await _db.setSyncMeta(_keyUrl, _url!);
    await _db.setSyncMeta(_keyAnon, _anonKey!);
    await _db.setSyncMeta(_keyEnabled, enabled ? '1' : '0');
    notifyListeners();
    if (enabled) {
      _startEngine();
    } else {
      _stopEngine();
    }
  }

  Future<bool> testConnection({String? url, String? anonKey}) async {
    final u = url ?? _url;
    final k = anonKey ?? _anonKey;
    if (u == null || u.isEmpty || k == null || k.isEmpty) {
      _lastError = 'Project URL / Anon Key kosong';
      notifyListeners();
      return false;
    }
    try {
      final c = _clientFor(u.replaceAll(RegExp(r'\/+$'), ''), k);
      await c.from('sync_meta').select('device_id').limit(1);
      return true;
    } catch (e) {
      _lastError = '$e';
      notifyListeners();
      return false;
    }
  }

  SupabaseClient _clientFor(String url, String anonKey) =>
      SupabaseClient(url, anonKey);

  void _startEngine() {
    if (_url == null || _url!.isEmpty || _anonKey == null || _anonKey!.isEmpty) {
      return;
    }
    _client = _clientFor(_url!, _anonKey!);
    _pushTimer?.cancel();
    _pushTimer = Timer.periodic(const Duration(seconds: 4), (_) => push());
    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(const Duration(seconds: 8), (_) => pullAll());
    _reconcileTimer?.cancel();
    _reconcileTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => reconcileAll(),
    );
    _subscribeRealtime();
    () async {
      await _snapshotIfNeeded();
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final repaired = await _db.forceRepairAll();
        if (repaired > 0) {
          debugPrint('SYNC startup repair: $repaired rows fixed');
          _revision++;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('SYNC startup repair skipped: $e');
      }
      await push();
      await reconcileAll();
    }();
  }

  Future<void> _snapshotIfNeeded() async {
    final snapOk = (await _db.getSyncMeta(_keySnapshotDone)) == '1';
    final resnapOk = (await _db.getSyncMeta(_keyResnapshotDone)) == '1';
    if (snapOk && resnapOk) return;
    debugPrint('SYNC snapshot: running');
    await _db.enqueueAllForSnapshot();
    await _db.setSyncMeta(_keySnapshotDone, '1');
    await _db.setSyncMeta(_keyResnapshotDone, '1');
    debugPrint('SYNC snapshot: done');
    await _refreshPendingCount();
  }

  void _stopEngine() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _pullTimer?.cancel();
    _pullTimer = null;
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
    for (final ch in _channels) {
      _client?.removeChannel(ch);
    }
    _channels = [];
    _client = null;
  }

  final Set<String> _pullQueue = {};
  bool _pullInFlight = false;

  void _subscribeRealtime() {
    final client = _client;
    if (client == null) return;
    for (final table in businessTables) {
      final channel = client.channel('public:$table');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (payload) {
          _requestPull(table);
        },
      );
      _channels.add(channel);
      channel.subscribe();
    }
  }

  /// Antre pull per-tabel agar event Realtime tidak dibuang begitu saja saat
  /// `_busy`; beberapa event untuk tabel yang sama diangkut menjadi satu.
  Future<void> _requestPull(String table) async {
    _pullQueue.add(table);
    if (_busy || _pullInFlight) return;
    _pullInFlight = true;
    try {
      while (_pullQueue.isNotEmpty) {
        final t = _pullQueue.first;
        _pullQueue.remove(t);
        await pullTable(t);
      }
    } finally {
      _pullInFlight = false;
    }
  }

  static const _netTimeout = Duration(seconds: 15);

  Future<void> push() async {
    if (_busy || _client == null) return;
    if (_db.isClosed) return; // Database sedang backup/import
    _busy = true;
    try {
      // Guard: jangan push jika database sedang ditutup (backup/import).
      final pending = await _db.getPendingOutbox();
      debugPrint('SYNC push start: ${pending.length} pending');
      if (pending.isNotEmpty) {
        final groups = <String, Map<String, List<Map<String, dynamic>>>>{};
        for (final entry in pending) {
          final eid = entry['id'] as int;
          final table = entry['table_name'] as String;
          final op = entry['operation'] as String;
          final raw = entry['payload'] as String? ?? '{}';
          Map<String, dynamic>? payload;
          try {
            final d = jsonDecode(raw);
            if (d is Map<String, dynamic>) payload = d;
          } catch (e) {
            _lastError = '$e';
          }
          if (payload == null) {
            await _db.deleteOutboxEntry(eid);
            continue;
          }
          if (payload['id'] == null) {
            await _db.deleteOutboxEntry(eid);
            continue;
          }
          final g = groups.putIfAbsent(
            table,
            () => {
              'upsert': <Map<String, dynamic>>[],
              'delete': <Map<String, dynamic>>[],
            },
          );
          final map = Map<String, dynamic>.from(payload);
          map['_eid'] = eid;
          if (op == 'delete') {
            g['delete']!.add(map);
          } else {
            g['upsert']!.add(map);
          }
        }
        // Parent dulu (products/sales/expenses) sebelum child.
        for (final table in businessTables) {
          final g = groups.remove(table);
          if (g == null) continue;
          final upserts = g['upsert']!;
          final deduped = <String, Map<String, dynamic>>{};
          for (final r in upserts) {
            // Resolve-ulang FK yang masih kosong dari UUID yang disimpan saat
            // enqueue, supaya sale_items yang sempat ter-enqueue sebelum
            // salenya tersinkron tetap ikut ter-upload (bukan dibuang).
            final lsid = r['_local_sale_id'];
            if (lsid is int &&
                (r['sale_id'] == null || (r['sale_id'] as String? ?? '').isEmpty)) {
              final saleUuid = await _db.saleUuidByLocalId(lsid);
              if (saleUuid != null && saleUuid.isNotEmpty) {
                r['sale_id'] = saleUuid;
              }
            }
            final lpid = r['_local_product_id'];
            if (lpid is int &&
                (r['product_id'] == null || (r['product_id'] as String? ?? '').isEmpty)) {
              final productUuid = await _db.productUuidByLocalId(lpid);
              if (productUuid != null && productUuid.isNotEmpty) {
                r['product_id'] = productUuid;
              }
            }
            if (table == 'sale_items' &&
                (r['sale_id'] == null || (r['sale_id'] as String? ?? '').isEmpty)) {
              // Induk belum punya uuid lokal: TIDAK dihapus (tetap di outbox),
              // ditunda ke siklus berikut saat uuid induk sudah muncul.
              continue;
            }
            // Catatan: customer_ledgers SAH tanpa sale_id (hutang manual),
            // jadi TIDAK dibuang di sini — selalu di-upload.
            deduped[r['id'].toString()] = r;
          }
          // Stempel revisi yang DIJAMIN melebihi semua revisi di cloud, supaya
          // kursor device lain (`.gt('updated_at', cursor)`) pasti menariknya
          // apa pun selisih jam antar HP.
          final stamp = await _monotonicStamp(table);
          final list = deduped.values.toList();
          for (var i = 0; i < list.length; i += 500) {
            final batch = list.sublist(
              i,
              math.min(i + 500, list.length),
            );
            await _sendUpsertBatchWithIsolation(table, batch, stamp);
          }
          final deletes = g['delete']!;
          for (var i = 0; i < deletes.length; i += 200) {
            final batch = deletes.sublist(
              i,
              math.min(i + 200, deletes.length),
            );
            await _sendDeleteWithIsolation(table, batch, stamp);
          }
        }
      }
      // Selesaikan baris yang sempat menunggu induknya (sale_items/
      // customer_ledgers) yang mungkin sudah ter-pull oleh device ini tadi.
      final appliedPending = await _db.processPendingRemote();
      if (appliedPending > 0) _revision += appliedPending;
      await _refreshPendingCount();
      _lastSyncedAt = DateTime.now();
    } catch (e, st) {
      debugPrint('SYNC push err: $e\n$st');
      _lastError = kDebugMode ? '$e\n$st' : '$e';
      await _refreshPendingCount();
    } finally {
      _busy = false;
    }
  }

  Future<void> pullAll() async {
    if (_busy || _client == null) return;
    if (_db.isClosed) return; // Database sedang backup/import
    for (final table in businessTables) {
      await pullTable(table);
    }
    // Selesaikan baris yang tadi menunggu induknya (sale_items/customer_ledgers).
    final appliedPending = await _db.processPendingRemote();
    if (appliedPending > 0) _revision += appliedPending;
    _lastSyncedAt = DateTime.now();
    await _refreshPendingCount();
    notifyListeners();
  }

  Future<void> pullTable(String table) async {
    if (_busy || _client == null) return;
    if (_db.isClosed) return; // Database sedang backup/import
    _busy = true;
    try {
      final client = _client!;
      final cursorKey = 'pull_cursor_$table';
      var cursor = await _db.getSyncMeta(cursorKey) ?? '1970-01-01T00:00:00Z';
      var keepGoing = true;
      while (keepGoing) {
        final res = await client
            .from(table)
            .select('*')
            .gt('updated_at', cursor)
            .order('updated_at')
            .limit(500)
            .timeout(_netTimeout);
        final rows = (res as List?) ?? [];
        if (rows.isEmpty) {
          keepGoing = false;
          continue;
        }
        var processed = false;
        DateTime? maxApplied;
        DateTime? minSkipped;
        for (final row in rows) {
          DateTime? parsed;
          final updated = row['updated_at'] as String?;
          if (updated != null) parsed = DateTime.tryParse(updated);
          final uuid = row['id'] as String?;
          if (uuid == null) continue;
          var ok = true;
          final deleted = row['deleted_at'] as String?;
          if (deleted != null && deleted.isNotEmpty) {
            await _db.applyRemoteDelete(table, uuid, row);
          } else {
            ok = await _db.applyRemoteRow(table, row);
          }
          processed = true;
          if (parsed != null) {
            if (ok) {
              if (maxApplied == null || parsed.isAfter(maxApplied)) {
                maxApplied = parsed;
              }
            } else {
              if (minSkipped == null || parsed.isBefore(minSkipped)) {
                minSkipped = parsed;
              }
            }
          }
        }
        // Kursor hanya maju sampai sebelum baris yang masih di-skip,
        // supaya baris itu tidak pernah "tertelan" kursor.
        DateTime? advanceTo = maxApplied;
        if (minSkipped != null &&
            (advanceTo == null || minSkipped.isBefore(advanceTo))) {
          advanceTo =
              minSkipped.subtract(const Duration(milliseconds: 1));
        }
        if (advanceTo != null) {
          cursor = advanceTo.toUtc().toIso8601String();
          await _db.setSyncMeta(cursorKey, cursor);
        }
        if (processed) _revision++;
        keepGoing = rows.length == 500;
      }
      notifyListeners();
    } catch (e, st) {
      debugPrint('SYNC pull $table: $e\n$st');
      _lastError = '$e';
    } finally {
      _busy = false;
    }
  }

  /// Perbaikan data: set ulang kursor ke epoch lalu tarik ulang semua tabel.
  /// Idempoten (LWW + tombstone melindungi baris lokal yang lebih baru).
  Future<void> repullAll() async {
    if (_client == null) return;
    debugPrint('SYNC repull all: reset cursors + reconcile');
    // Tunggu hingga tidak ada push/pull/reconcile yang sedang berjalan,
    // supaya reset kursor tidak diam-diam batal (`_busy` guard) dan hasilnya
    // benar-benar masuk dalam siklus ini.
    for (var i = 0; i < 40; i++) {
      if (!_busy && !_reconcileInFlight) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await _db.resetAllPullCursors();
    // Rapikan SEMUA data: duplikat slot, sale_items orphaned, customer_ledgers
    // orphaned. Kirim tombstone-nya supaya cloud & HP lain ikut rapi.
    try {
      final repaired = await _db.forceRepairAll();
      if (repaired > 0) _revision++;
    } catch (_) {}
    await push();
    await reconcileAll();
  }

  bool _reconcileInFlight = false;

  /// Penyelaras penuh dengan server (model database terpusat):
  /// menarik SELURUH baris semua tabel (tanpa kursor/timestamp) lalu
  /// menyamakan diri. Dipanggil tiap 30 detik, saat app dibuka, saat
  /// "Sinkron Sekarang", dan "Perbaiki Data". Dijamin semua HP akhirnya
  /// melihat data yang sama karena server adalah sumber kebenaran.
  Future<void> reconcileAll() async {
    if (_busy || _client == null || _reconcileInFlight) return;
    if (_db.isClosed) return; // Database sedang backup/import
    _reconcileInFlight = true;
    try {
      // Jangan menarik kembali baris yang masih punya antrean HAPUS lokal
      // (belum ter-upload) supaya tidak "hidup lagi" sesaat di HP ini.
      final pending = await _db.getPendingOutbox();
      final pendingDeletes = <String, Set<String>>{};
      for (final e in pending) {
        final table = e['table_name'] as String;
        final op = e['operation'] as String;
        if (op != 'delete') continue;
        final raw = e['payload'] as String? ?? '{}';
        try {
          final d = jsonDecode(raw);
          if (d is Map<String, dynamic> && d['id'] is String) {
            pendingDeletes
                .putIfAbsent(table, () => {})
                .add(d['id'] as String);
          }
        } catch (_) {}
      }
      for (final table in businessTables) {
        await pullFullTable(table, pendingDeletes[table]);
      }
      final appliedPending = await _db.processPendingRemote();
      if (appliedPending > 0) _revision += appliedPending;
      // Perbaiki duplikat/orphaned secara periodik (tiap ~5 menit, bukan
      // tiap reconcile) supaya data tetap bersih tanpa menambah beban.
      _reconcileCount++;
      if (_reconcileCount % 10 == 0) {
        try {
          final repaired = await _db.forceRepairAll();
          if (repaired > 0) _revision++;
        } catch (_) {}
      }
      _lastSyncedAt = DateTime.now();
      await _refreshPendingCount();
      notifyListeners();
    } catch (e, st) {
      debugPrint('SYNC reconcile: $e\n$st');
      _lastError = '$e';
    } finally {
      _reconcileInFlight = false;
    }
  }

  /// Tarik SELURUH isi satu tabel dari server (paginasi via id uuid, bukan
  /// updated_at) lalu terapkan ke lokal.
  Future<void> pullFullTable(
    String table, [
    Set<String>? skipDeletes,
  ]) async {
    if (_busy || _client == null) return;
    _busy = true;
    try {
      final client = _client!;
      String? lastId;
      while (true) {
        final base = client.from(table).select('*');
        final query = lastId == null
            ? base.order('id').limit(500)
            : base.gt('id', lastId).order('id').limit(500);
        final res = await query.timeout(_netTimeout);
        final rows = (res as List?) ?? [];
        if (rows.isEmpty) break;
        lastId = rows.last['id'] as String?;
        var processed = false;
        for (final row in rows) {
          final uuid = row['id'] as String?;
          if (uuid == null) continue;
          final deleted = row['deleted_at'] as String?;
          if (deleted != null && deleted.isNotEmpty) {
            await _db.applyRemoteDelete(table, uuid, row);
          } else {
            if (skipDeletes?.contains(uuid) ?? false) {
              processed = true;
              continue;
            }
            await _db.applyRemoteRow(table, row);
          }
          processed = true;
        }
        if (processed) _revision++;
        if (rows.length < 500) break;
      }
      notifyListeners();
    } catch (e, st) {
      debugPrint('SYNC pullFull $table: $e\n$st');
      _lastError = '$e';
    } finally {
      _busy = false;
    }
  }

  Future<void> _refreshPendingCount() async {
    final pending = await _db.getPendingOutbox();
    _pendingCount = pending.length;
  }

  /// Stempel revisi yang DIJAMIN lebih baru dari semua revisi yang sudah ada
  /// di cloud. Ini menggantikan `DateTime.now()` HP: jika jam device tertinggal
  /// dari device lain, stamp tetap dipaksa maju (cloudMax + 1ms) sehingga
  /// kursor device lain pasti terlewati dan perubahan ikut tertarik.
  Future<String> _monotonicStamp(String table) async {
    var t = DateTime.now().toUtc();
    try {
      final res = await _client!
          .from(table)
          .select('updated_at')
          .order('updated_at', ascending: false)
          .limit(1)
          .timeout(_netTimeout);
      final rows = (res as List?) ?? [];
      if (rows.isNotEmpty) {
        final ts =
            DateTime.tryParse(rows.first['updated_at'] as String? ?? '');
        if (ts != null && ts.isAfter(t)) {
          t = ts.add(const Duration(milliseconds: 1));
        }
      }
    } catch (e) {
      debugPrint('SYNC stamp $table: $e');
    }
    return t.toIso8601String();
  }

  /// Kirim batch upsert dengan isolasi per-baris: jika seluruh batch ditolak,
  /// coba satu-satu agar satu baris "beracun" (mis. FK rusak) tidak memblokir
  /// baris sehat (penyebab Total kg 0 pada semua HP).
  Future<void> _sendUpsertBatchWithIsolation(
    String table,
    List<Map<String, dynamic>> batch,
    String stamp,
  ) async {
    final client = _client;
    if (client == null) return;
    final body = batch.map((r) {
      final m = Map<String, dynamic>.from(r);
      m.remove('_eid');
      // Kolom bantu resolusi FK (bukan kolom remote) tidak boleh ikut terkirim.
      m.remove('_local_sale_id');
      m.remove('_local_product_id');
      // Wajib: setiap push memajukan updated_at supaya baris yang
      // diedit/dihapus ter-tarik oleh `.gt('updated_at', cursor)` di
      // device lain (server tidak otomatis me-refresh nya).
      m['updated_at'] = stamp;
      m['updated_by'] = _deviceId;
      return m;
    }).toList();
    try {
      await client.from(table).upsert(body).timeout(_netTimeout);
      for (final r in batch) {
        await _db.deleteOutboxEntry(r['_eid'] as int);
      }
      return;
    } catch (e, st) {
      debugPrint('SYNC upsert $table (${body.length}): $e\n$st');
      _lastError = '$e';
    }
    // Batch besar gagal total → jatuhkan ke per baris supaya satu baris
    // bermasalah tidak menghentikan sisanya.
    for (final r in batch) {
      final m = Map<String, dynamic>.from(r);
      m.remove('_eid');
      m.remove('_local_sale_id');
      m.remove('_local_product_id');
      m['updated_at'] = stamp;
      m['updated_by'] = _deviceId;
      try {
        await client.from(table).upsert([m]).timeout(_netTimeout);
        await _db.deleteOutboxEntry(r['_eid'] as int);
      } catch (e, st) {
        debugPrint('SYNC upsert single $table #${r['id']}: $e\n$st');
        _lastError = '$e';
      }
    }
  }

  /// Kirim tombstone (soft delete) dengan isolasi per-baris seperti di atas.
  Future<void> _sendDeleteWithIsolation(
    String table,
    List<Map<String, dynamic>> batch,
    String stamp,
  ) async {
    final client = _client;
    if (client == null) return;
    final ids = batch.map((r) => r['id'].toString()).toList();
    try {
      await client
          .from(table)
          .update({
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            // Tombstone juga perlu updated_at lebih baru agar ter-tarik
            // oleh `>` cursor di device lain.
            'updated_at': stamp,
          })
          .inFilter('id', ids)
          .timeout(_netTimeout);
      for (final r in batch) {
        await _db.deleteOutboxEntry(r['_eid'] as int);
      }
      return;
    } catch (e, st) {
      debugPrint('SYNC delete $table (${ids.length}): $e\n$st');
      _lastError = '$e';
    }
    for (final id in ids) {
      try {
        await client
            .from(table)
            .update({
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': stamp,
            })
            .inFilter('id', [id])
            .timeout(_netTimeout);
        final eid =
            batch.firstWhere((r) => r['id'].toString() == id)['_eid'] as int;
        await _db.deleteOutboxEntry(eid);
      } catch (e, st) {
        debugPrint('SYNC delete single $table #$id: $e\n$st');
        _lastError = '$e';
      }
    }
  }

  @override
  void dispose() {
    _stopEngine();
    super.dispose();
  }
}