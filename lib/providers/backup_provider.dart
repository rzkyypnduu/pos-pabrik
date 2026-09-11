import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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

  bool get _isSafDestination =>
      _destinationPath.trim().startsWith('content://');

  bool get isSafDestination => _isSafDestination;

  bool get hasDestination => _isSafDestination || effectiveBackupFolder.isNotEmpty;

  String get destinationDisplay {
    final d = _destinationPath.trim();
    if (d.isEmpty) return '';
    if (_isSafDestination) return 'Google Drive / folder tersambung (SAF)';
    return d;
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
    if (!hasDestination) return false;
    final today = _todayStamp();
    final fileName = _backupFileName(today);
    if (_isSafDestination) {
      if (await _safFileExists(fileName)) {
        _lastBackupDate = today;
        return true;
      }
    } else {
      final folder = effectiveBackupFolder;
      if (File(p.join(folder, fileName)).existsSync()) {
        _lastBackupDate = today;
        return true;
      }
    }
    return await backupNow();
  }

  /// Selalu membuat salinan baru (menimpa file backup hari ini jika ada).
  Future<bool> backupNow() async {
    if (!hasDestination) {
      _lastStatus = 'Pilih folder tujuan backup dulu';
      _safeNotify();
      return false;
    }
    if (!_isSafDestination && !await _hasAllFilesAccess()) {
      _lastStatus = 'Backup gagal: aktifkan Akses Semua File di Pengaturan HP dulu';
      _safeNotify();
      return false;
    }
    _isBackingUp = true;
    _lastStatus = 'Menyimpan backup...';
    _safeNotify();
    try {
      final today = _todayStamp();
      final fileName = _backupFileName(today);
      if (_isSafDestination) {
        final bytes = await DatabaseHelper.instance.exportDatabaseBytes();
        await _writeSafFile(fileName, bytes);
      } else {
        final folder = effectiveBackupFolder;
        Directory(folder).createSync(recursive: true);
        if (!Directory(folder).existsSync()) {
          throw Exception('Folder tujuan tidak ditemukan');
        }
        final dest = p.join(folder, fileName);
        await DatabaseHelper.instance.exportDatabase(dest);
      }
      _lastBackupDate = today;
      _lastStatus = 'Backup berhasil ke folder $_safeDeviceName ($today)';
      _isBackingUp = false;
      _safeNotify();
      _saveSettings();
      if (!_isSafDestination) await cleanupOldBackups();
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
    if (!_enabled || !hasDestination) return false;
    if (_isBackingUp) return false;
    if (!_isSafDestination && !await _hasAllFilesAccess()) return false;
    _isBackingUp = true;
    try {
      final today = _todayStamp();
      final fileName = _backupFileName(today);
      if (_isSafDestination) {
        final bytes = await DatabaseHelper.instance.exportDatabaseBytes();
        await _writeSafFile(fileName, bytes);
      } else {
        final folder = effectiveBackupFolder;
        Directory(folder).createSync(recursive: true);
        if (!Directory(folder).existsSync()) {
          throw Exception('Folder tujuan tidak ditemukan');
        }
        final dest = p.join(folder, fileName);
        await DatabaseHelper.instance.shutdownExport(dest);
      }
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

  Future<bool> _hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      const channel = MethodChannel('pos_krupuk/storage');
      final ok = await channel.invokeMethod<bool>('hasAllFilesAccess');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasAllFilesAccess() => _hasAllFilesAccess();

  Future<bool> requestAllFilesAccess() async {
    try {
      const channel = MethodChannel('pos_krupuk/storage');
      await channel.invokeMethod<void>('requestAllFilesAccess');
      return await _hasAllFilesAccess();
    } catch (_) {
      return false;
    }
  }

  /// Buka picker folder Android (SAF) agar bisa memilih Google Drive dll.
  Future<String?> pickSafDirectory() async {
    try {
      const channel = MethodChannel('pos_krupuk/storage');
      return await channel.invokeMethod<String?>('pickSafDirectory');
    } catch (_) {
      return null;
    }
  }

  Future<bool> _safFileExists(String fileName) async {
    try {
      const channel = MethodChannel('pos_krupuk/storage');
      final ok = await channel.invokeMethod<bool>('safFileExists', {
        'treeUri': _destinationPath.trim(),
        'subDir': _safeDeviceName,
        'fileName': fileName,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeSafFile(String fileName, Uint8List bytes) async {
    const channel = MethodChannel('pos_krupuk/storage');
    final ok = await channel.invokeMethod<bool>('writeSafFile', {
      'treeUri': _destinationPath.trim(),
      'subDir': _safeDeviceName,
      'fileName': fileName,
      'bytes': bytes,
    });
    if (ok != true) throw Exception('Gagal menulis ke folder terpilih');
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
