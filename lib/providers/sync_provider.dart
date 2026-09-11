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
  String? _deviceId;

  bool _enabled = false;
  bool _busy = false;
  String? _lastError;
  DateTime? _lastSyncedAt;
  int _pendingCount = 0;
  int _revision = 0;

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
    _subscribeRealtime();
    () async {
      await _snapshotIfNeeded();
      await push();
      await pullAll();
    }();
  }

  Future<void> _snapshotIfNeeded() async {
    if ((await _db.getSyncMeta(_keySnapshotDone)) == '1') return;
    await _db.enqueueAllForSnapshot();
    await _db.setSyncMeta(_keySnapshotDone, '1');
    await _refreshPendingCount();
  }

  void _stopEngine() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _pullTimer?.cancel();
    _pullTimer = null;
    for (final ch in _channels) {
      _client?.removeChannel(ch);
    }
    _channels = [];
    _client = null;
  }

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
          pullTable(table);
        },
      );
      _channels.add(channel);
      channel.subscribe();
    }
  }

  static const _netTimeout = Duration(seconds: 15);

  Future<void> push() async {
    if (_busy || _client == null) return;
    _busy = true;
    try {
      final pending = await _db.getPendingOutbox();
      if (pending.isNotEmpty) {
        final groups = <String, Map<String, List<Map<String, dynamic>>>>{};
        for (final entry in pending) {
          final eid = entry['id'] as int;
          final table = entry['table_name'] as String;
          final op = entry['operation'] as String;
          final payload =
              jsonDecode(entry['payload'] as String? ?? '{}')
                  as Map<String, dynamic>;
          if (payload['id'] == null) {
            await _db.deleteOutboxEntry(eid);
            continue;
          }
          final g = groups.putIfAbsent(
            table,
            () => {'upsert': <Map<String, dynamic>>[], 'delete': <Map<String, dynamic>>[]},
          );
          final map = Map<String, dynamic>.from(payload);
          map['_eid'] = eid;
          g[op]!.add(map);
        }
        // Parent dulu (products/sales/expenses) sebelum child.
        for (final table in businessTables) {
          final g = groups.remove(table);
          if (g == null) continue;
          final upserts = g['upsert']!;
          for (var i = 0; i < upserts.length; i += 500) {
            final batch = upserts.sublist(
              i,
              math.min(i + 500, upserts.length),
            );
            final body = batch.map((r) {
              final m = Map<String, dynamic>.from(r);
              m.remove('_eid');
              m['updated_by'] = _deviceId;
              return m;
            }).toList();
            try {
              await _client!.from(table).upsert(body).timeout(_netTimeout);
              for (final r in batch) {
                await _db.deleteOutboxEntry(r['_eid'] as int);
              }
            } catch (e) {
              _lastError = '$e';
            }
          }
          final deletes = g['delete']!;
          for (var i = 0; i < deletes.length; i += 200) {
            final batch = deletes.sublist(
              i,
              math.min(i + 200, deletes.length),
            );
            final ids =
                batch.map((r) => r['id'].toString()).toList();
            try {
              await _client!
                  .from(table)
                  .update({
                    'deleted_at': DateTime.now().toUtc().toIso8601String(),
                  })
                  .inFilter('id', ids)
                  .timeout(_netTimeout);
              for (final r in batch) {
                await _db.deleteOutboxEntry(r['_eid'] as int);
              }
            } catch (e) {
              _lastError = '$e';
            }
          }
        }
      }
      await _refreshPendingCount();
      _lastSyncedAt = DateTime.now();
    } catch (e) {
      _lastError = kDebugMode ? '$e' : 'Gagal mengunggah data';
    } finally {
      _busy = false;
    }
  }

  Future<void> pullAll() async {
    if (_busy || _client == null) return;
    for (final table in businessTables) {
      await pullTable(table);
    }
    _lastSyncedAt = DateTime.now();
    await _refreshPendingCount();
    notifyListeners();
  }

  Future<void> pullTable(String table) async {
    if (_busy || _client == null) return;
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
        var applied = false;
        DateTime? maxUpdated;
        for (final row in rows) {
          final updated = row['updated_at'] as String?;
          if (updated != null) {
            final parsed = DateTime.tryParse(updated);
            if (parsed != null &&
                (maxUpdated == null || parsed.isAfter(maxUpdated))) {
              maxUpdated = parsed;
            }
          }
          final uuid = row['id'] as String?;
          if (uuid == null) continue;
          final deleted = row['deleted_at'] as String?;
          if (deleted != null && deleted.isNotEmpty) {
            await _db.applyRemoteDelete(table, uuid);
          } else {
            await _db.applyRemoteRow(table, row);
          }
          applied = true;
        }
        if (maxUpdated != null) {
          cursor = maxUpdated.toUtc().toIso8601String();
          await _db.setSyncMeta(cursorKey, cursor);
        }
        if (applied) _revision++;
        keepGoing = rows.length == 500;
      }
      notifyListeners();
    } catch (e) {
      _lastError = kDebugMode ? '$e' : 'Gagal menarik data $table';
    } finally {
      _busy = false;
    }
  }

  Future<void> _refreshPendingCount() async {
    final pending = await _db.getPendingOutbox();
    _pendingCount = pending.length;
  }

  @override
  void dispose() {
    _stopEngine();
    super.dispose();
  }
}