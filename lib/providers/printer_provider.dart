import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:path_provider/path_provider.dart';

import '../services/printer_service.dart';

class PrinterProvider extends ChangeNotifier {
  final PrinterService _service = PrinterService();

  // ── Android Bluetooth ──
  List<BtcDevice> _btDevices = [];
  bool _isScanning = false;
  bool _isLoadingDevices = false;
  String _selectedBtAddress = '';
  String _selectedBtName = '';
  String _connectionStatus = 'notConnected';

  // ── Windows USB ──
  List<String> _windowsPrinters = [];
  String _selectedWindowsPrinter = '';
  bool _isLoadingWindowsPrinters = false;

  // ── Settings ──
  bool _autoPrint = false;
  String _storeName = 'POS Krupuk';
  String _address = '';
  String _phone = '';
  String _slogan = 'Terima kasih!';
  String _footer = '';
  String _logoPath = '';

  // ── Getters ──
  List<BtcDevice> get btDevices => _btDevices;
  bool get isScanning => _isScanning;
  bool get isLoadingDevices => _isLoadingDevices;
  String get selectedBtAddress => _selectedBtAddress;
  String get selectedBtName => _selectedBtName;
  String get connectionStatus => _connectionStatus;

  List<String> get windowsPrinters => _windowsPrinters;
  String get selectedWindowsPrinter => _selectedWindowsPrinter;
  bool get isLoadingWindowsPrinters => _isLoadingWindowsPrinters;

  bool get autoPrint => _autoPrint;
  String get storeName => _storeName;
  String get shopAddress => _address;
  String get phone => _phone;
  String get slogan => _slogan;
  String get footer => _footer;
  String get logoPath => _logoPath;

  bool get isConnected {
    if (Platform.isWindows) return _selectedWindowsPrinter.isNotEmpty;
    return _connectionStatus == 'connected';
  }

  void _safeNotify() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  // ── Settings setters ──
  set autoPrint(bool v) {
    _autoPrint = v;
    _saveSettings();
    _safeNotify();
  }

  set storeName(String v) {
    _storeName = v;
    _saveSettings();
    _safeNotify();
  }

  set shopAddress(String v) {
    _address = v;
    _saveSettings();
    _safeNotify();
  }

  set phone(String v) {
    _phone = v;
    _saveSettings();
    _safeNotify();
  }

  set slogan(String v) {
    _slogan = v;
    _saveSettings();
    _safeNotify();
  }

  set footer(String v) {
    _footer = v;
    _saveSettings();
    _safeNotify();
  }

  set logoPath(String v) {
    _logoPath = v;
    _saveSettings();
    _safeNotify();
  }

  // ── Persistence ──
  Map<String, dynamic> _toSettingsMap() => {
    'autoPrint': _autoPrint,
    'storeName': _storeName,
    'address': _address,
    'phone': _phone,
    'slogan': _slogan,
    'footer': _footer,
    'logoPath': _logoPath,
    'selectedBtAddress': _selectedBtAddress,
    'selectedBtName': _selectedBtName,
    'selectedWindowsPrinter': _selectedWindowsPrinter,
  };

  void _loadFromMap(Map<String, dynamic> s) {
    if (s.containsKey('autoPrint')) _autoPrint = s['autoPrint'] == true;
    if (s.containsKey('storeName')) _storeName = s['storeName'] ?? 'POS Krupuk';
    if (s.containsKey('address')) _address = s['address'] ?? '';
    if (s.containsKey('phone')) _phone = s['phone'] ?? '';
    if (s.containsKey('slogan')) _slogan = s['slogan'] ?? 'Terima kasih!';
    if (s.containsKey('footer')) _footer = s['footer'] ?? '';
    if (s.containsKey('logoPath')) _logoPath = s['logoPath'] ?? '';
    _selectedBtAddress = s['selectedBtAddress'] ?? '';
    _selectedBtName = s['selectedBtName'] ?? '';
    _selectedWindowsPrinter = s['selectedWindowsPrinter'] ?? '';
  }

  Future<File> get _settingsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/printer_settings.json');
  }

  Future<void> loadSavedSettings() async {
    try {
      final file = await _settingsFile;
      if (await file.exists()) {
        final json = await file.readAsString();
        _loadFromMap(jsonDecode(json));
        _safeNotify();
        if (Platform.isAndroid && _selectedBtAddress.isNotEmpty) {
          await loadSavedBtDevice();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final file = await _settingsFile;
      await file.writeAsString(jsonEncode(_toSettingsMap()));
    } catch (_) {}
  }

  // ── Windows USB ──
  Future<void> loadWindowsPrinters() async {
    if (!Platform.isWindows) return;
    _isLoadingWindowsPrinters = true;
    _safeNotify();
    _windowsPrinters = await _service.getWindowsPrinters();
    _isLoadingWindowsPrinters = false;
    _safeNotify();
  }

  void selectWindowsPrinter(String name) {
    _selectedWindowsPrinter = name;
    _service.selectWindowsPrinter(name);
    _saveSettings();
    _safeNotify();
  }

  // ── Android Bluetooth ──
  Future<bool> checkAndRequestPermissions() async {
    return await _service.checkAndRequestPermissions();
  }

  Future<void> refreshBtConnectionStatus() async {
    if (_selectedBtAddress.isEmpty) {
      _connectionStatus = 'notConnected';
      _safeNotify();
      return;
    }
    _connectionStatus = 'checking';
    _safeNotify();
    final connected = await _service.checkConnection();
    _connectionStatus = connected ? 'connected' : 'notConnected';
    if (!connected) {
      _selectedBtAddress = '';
      _selectedBtName = '';
    }
    _safeNotify();
  }

  Future<void> loadSavedBtDevice() async {
    if (_selectedBtAddress.isEmpty) return;
    _connectionStatus = 'checking';
    _safeNotify();
    try {
      final connected = await _service.connect(_selectedBtAddress);
      _connectionStatus = connected ? 'connected' : 'notConnected';
    } catch (_) {
      _connectionStatus = 'notConnected';
    }
    _safeNotify();
  }

  Future<void> loadBondedDevices() async {
    _isLoadingDevices = true;
    _safeNotify();
    try {
      _btDevices = await _service.getPairedDevices();
    } catch (_) {
      _btDevices = [];
    }
    _isLoadingDevices = false;
    _safeNotify();
  }

  Future<void> scanDevices() async {
    _isScanning = true;
    _safeNotify();
    try {
      _btDevices = await _service.scanDevices();
    } catch (_) {
      _btDevices = [];
    }
    _isScanning = false;
    _safeNotify();
  }

  Future<bool> connectBt(String macAddress, String name) async {
    final result = await _service.connect(macAddress);
    if (result) {
      _selectedBtAddress = macAddress;
      _selectedBtName = name;
      _connectionStatus = 'connected';
      await _saveSettings();
    }
    _safeNotify();
    return result;
  }

  Future<void> disconnectBt() async {
    await _service.disconnect();
    _connectionStatus = 'notConnected';
    _safeNotify();
  }

  Future<void> resetBtSelection() async {
    try {
      await disconnectBt();
    } catch (_) {}
    _selectedBtAddress = '';
    _selectedBtName = '';
    _connectionStatus = 'notConnected';
    await _saveSettings();
    _safeNotify();
  }

  Future<bool> ensureConnected() async {
    if (Platform.isWindows) return _selectedWindowsPrinter.isNotEmpty;
    if (_selectedBtAddress.isEmpty) return false;
    if (_service.isConnected) {
      _connectionStatus = 'connected';
      _safeNotify();
      return true;
    }
    final result = await _service.connect(_selectedBtAddress);
    _connectionStatus = result ? 'connected' : 'notConnected';
    _safeNotify();
    return result;
  }

  Future<bool> printTest() async {
    final connected = await ensureConnected();
    if (!connected) return false;
    return await _service.printTest();
  }

  Future<bool> printReceipt({
    required List<ReceiptItem> items,
    required String totalText,
    required String paidText,
    required String changeText,
    String changeLabel = 'KEMBALI',
    String customerName = '',
    DateTime? timestamp,
  }) async {
    final connected = await ensureConnected();
    if (!connected) return false;
    return await _service.printReceipt(
      storeName: _storeName,
      items: items,
      totalText: totalText,
      paidText: paidText,
      changeText: changeText,
      changeLabel: changeLabel,
      address: _address,
      phone: _phone,
      slogan: _slogan,
      footer: _footer,
      logoPath: _logoPath,
      customerName: customerName,
      timestamp: timestamp,
    );
  }
}
