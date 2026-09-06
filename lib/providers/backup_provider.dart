import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';

class BackupProvider extends ChangeNotifier {
  bool _enabled = false;
  String _destinationPath = '';
  String _deviceName = '';
  int _retentionDays = 30;
  String _lastBackupDate = '';
  String _lastStatus = '';
  bool _isBackingUp = false;
  Timer? _timer;

  bool get enabled => _enabled;
  String get destinationPath => _destinationPath;
  String get deviceName => _deviceName;
  int get retentionDays => _retentionDays;
  String get lastBackupDate => _lastBackupDate;
  String get lastStatus => _lastStatus;
  bool get isBackingUp => _isBackingUp;

  String get _safeDeviceName {
    final n = _deviceName.trim();
    if (n.isEmpty || n == 'Laptop') return 'Laptop';
    final sanitized = n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
    return sanitized.isEmpty ? 'Laptop' : sanitized;
  }

  String get effectiveBackupFolder {
    if (_destinationPath.trim().isEmpty) return '';
    return p.join(_destinationPath.trim(), _safeDeviceName);
  }

  void _safeNotify() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  set enabled(bool v) {
    _enabled = v;
    _saveSettings();
    if (v) {
      _startTimer();
      runBackupIfDue();
    } else {
      _stopTimer();
    }
    _safeNotify();
  }

  set destinationPath(String v) {
    _destinationPath = v;
    _saveSettings();
    _safeNotify();
  }

  set deviceName(String v) {
    _deviceName = v.trim();
    if (_deviceName.isNotEmpty) {
      _deviceName = _deviceName
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    _saveSettings();
    _safeNotify();
  }

  String _todayStamp() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String _backupFileName(String dateStamp) => 'pos_krupuk_backup_$dateStamp.db';

  Future<File> get _settingsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/backup_settings.json');
  }

  Map<String, dynamic> _toSettingsMap() => {
    'enabled': _enabled,
    'destinationPath': _destinationPath,
    'deviceName': _deviceName,
    'retentionDays': _retentionDays,
  };

  void _loadFromMap(Map<String, dynamic> s) {
    _enabled = s['enabled'] == true;
    _destinationPath = s['destinationPath'] ?? '';
    _deviceName = s['deviceName'] ?? '';
    _retentionDays = (s['retentionDays'] as num?)?.toInt() ?? 30;
  }

  String _defaultDeviceName() {
    try {
      final h = Platform.localHostname.trim();
      if (h.isNotEmpty && h.toLowerCase() != 'localhost') {
        return h.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
      }
    } catch (_) {}
    return 'Laptop';
  }

  Future<void> loadSavedSettings() async {
    try {
      final file = await _settingsFile;
      if (await file.exists()) {
        _loadFromMap(jsonDecode(await file.readAsString()));
      }
      if (_deviceName.isEmpty) {
        _deviceName = _defaultDeviceName();
        _saveSettings();
      }
      if (_enabled) _startTimer();
      _safeNotify();
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final file = await _settingsFile;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_toSettingsMap()));
      try {
        await tmp.rename(file.path);
      } on FileSystemException {
        if (await file.exists()) await file.delete();
        await tmp.rename(file.path);
      }
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 1), (_) {
      runBackupIfDue();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Cek apakah backup hari ini sudah ada; jika belum, buat backup baru.
  Future<bool> runBackupIfDue() async {
    if (!_enabled) return false;
    final folder = effectiveBackupFolder;
    if (folder.isEmpty) return false;
    final today = _todayStamp();
    if (File(p.join(folder, _backupFileName(today))).existsSync()) {
      _lastBackupDate = today;
      return true;
    }
    return await backupNow();
  }

  /// Selalu membuat salinan baru (menimpa file backup hari ini jika ada).
  Future<bool> backupNow() async {
    if (effectiveBackupFolder.isEmpty) {
      _lastStatus = 'Pilih folder tujuan backup dulu';
      _safeNotify();
      return false;
    }
    _isBackingUp = true;
    _lastStatus = 'Menyimpan backup...';
    _safeNotify();
    try {
      final folder = effectiveBackupFolder;
      Directory(folder).createSync(recursive: true);
      if (!Directory(folder).existsSync()) {
        throw Exception('Folder tujuan tidak ditemukan');
      }
      final today = _todayStamp();
      final dest = p.join(folder, _backupFileName(today));
      await DatabaseHelper.instance.exportDatabase(dest);
      _lastBackupDate = today;
      _lastStatus = 'Backup berhasil ke folder $_safeDeviceName ($today)';
      _isBackingUp = false;
      _safeNotify();
      _saveSettings();
      await cleanupOldBackups();
      return true;
    } catch (e) {
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}
      _lastStatus = 'Backup gagal: $e';
      _isBackingUp = false;
      _safeNotify();
      return false;
    }
  }

  /// Backup cepat saat aplikasi ditutup — menimpa backup hari ini dengan data
  /// terakhir tanpa membuka ulang database. Mengikuti switch utama backup.
  Future<bool> backupOnClose() async {
    if (!_enabled || effectiveBackupFolder.isEmpty) return false;
    if (_isBackingUp) return false;
    _isBackingUp = true;
    try {
      final folder = effectiveBackupFolder;
      Directory(folder).createSync(recursive: true);
      if (!Directory(folder).existsSync()) {
        throw Exception('Folder tujuan tidak ditemukan');
      }
      final today = _todayStamp();
      final dest = p.join(folder, _backupFileName(today));
      await DatabaseHelper.instance.shutdownExport(dest);
      _lastBackupDate = today;
      _lastStatus = 'Backup saat menutup aplikasi berhasil ($today)';
      await _saveSettings();
      return true;
    } catch (e) {
      _lastStatus = 'Backup saat menutup aplikasi gagal: $e';
      await _saveSettings();
      return false;
    } finally {
      _isBackingUp = false;
    }
  }

  /// Hapus file backup yang lebih lama dari [retentionDays].
  Future<void> cleanupOldBackups() async {
    final folder = effectiveBackupFolder;
    if (folder.isEmpty) return;
    final dir = Directory(folder);
    if (!dir.existsSync()) return;
    final cutoff = DateTime.now().subtract(Duration(days: _retentionDays));
    final pattern = RegExp(r'^pos_krupuk_backup_(\d{4})-(\d{2})-(\d{2})\.db$');
    final files = dir.listSync().whereType<File>().where(
      (f) => pattern.hasMatch(p.basename(f.path)),
    );
    for (final f in files) {
      final m = pattern.firstMatch(p.basename(f.path));
      if (m == null) continue;
      try {
        final d = DateTime(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        );
        if (d.isBefore(cutoff)) await f.delete();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
