import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:image/image.dart' as img;
import 'package:windows_printer/windows_printer.dart';

class PrinterService {
  // ── Android Bluetooth ──
  final FlutterClassicBluetooth _bluetooth = FlutterClassicBluetooth();
  BtcConnection? _connection;
  String? _connectedMac;
  String? _connectedName;
  bool _isConnected = false;

  // ── Windows USB ──
  String _selectedWindowsPrinter = '';
  List<String> _windowsPrinters = [];

  bool get isConnected => _isConnected;
  String? get connectedMac => _connectedMac;
  String? get connectedName => _connectedName;
  String get selectedWindowsPrinter => _selectedWindowsPrinter;
  List<String> get windowsPrinters => _windowsPrinters;

  // ── Permissions ──
  Future<bool> checkAndRequestPermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await _bluetooth.requestPermissions();
      return status == BtcPermissionStatus.granted ||
          status == BtcPermissionStatus.notRequired;
    } catch (_) {
      return false;
    }
  }

  // ── Windows USB ──
  Future<List<String>> getWindowsPrinters() async {
    if (!Platform.isWindows) return [];
    try {
      _windowsPrinters = await WindowsPrinter.getAvailablePrinters();
      return _windowsPrinters;
    } catch (_) {
      return [];
    }
  }

  void selectWindowsPrinter(String name) {
    _selectedWindowsPrinter = name;
  }

  bool printWindows(Uint8List bytes) {
    if (_selectedWindowsPrinter.isEmpty) return false;
    try {
      WindowsPrinter.printRawData(
        printerName: _selectedWindowsPrinter,
        data: bytes,
        useRawDatatype: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Android Bluetooth ──
  Future<bool> isBluetoothOn() async {
    try {
      return await _bluetooth.isEnabled();
    } catch (_) {
      return false;
    }
  }

  Future<List<BtcDevice>> scanDevices() async {
    try {
      return await _bluetooth.scan(timeout: const Duration(seconds: 8));
    } catch (_) {
      return [];
    }
  }

  Future<List<BtcDevice>> getPairedDevices() async {
    try {
      return await _bluetooth.getPairedDevices();
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect(String macAddress) async {
    try {
      await _connection?.close();
      _connection = await _bluetooth.connect(
        address: macAddress,
        timeout: const Duration(seconds: 15),
      );
      _isConnected = _connection!.isConnected;
      if (_isConnected) {
        _connectedMac = macAddress;
      } else {
        _connection = null;
      }
      return _isConnected;
    } catch (_) {
      _connection = null;
      _isConnected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _connection?.finish();
    } catch (_) {}
    _connection = null;
    _isConnected = false;
    _connectedMac = null;
    _connectedName = null;
  }

  Future<bool> checkConnection() async {
    if (_connection == null) {
      _isConnected = false;
      return false;
    }
    try {
      _isConnected = _connection!.isConnected;
      if (_isConnected) {
        await _connection!.output.writeBytes([0x00]);
        return true;
      }
    } catch (_) {}
    _isConnected = false;
    _connection = null;
    return false;
  }

  // ── Print (platform-aware) ──
  Future<bool> printTest() async {
    final bytes = _buildTestBytes();
    if (Platform.isWindows) {
      return printWindows(Uint8List.fromList(bytes));
    }
    if (!_isConnected || _connection == null) return false;
    try {
      await _connection!.output.writeBytes(bytes);
      await _connection!.output.allSent;
      return true;
    } catch (_) {
      _isConnected = false;
      _connection = null;
      return false;
    }
  }

  Future<bool> printReceipt({
    required String storeName,
    required List<ReceiptItem> items,
    required String totalText,
    required String paidText,
    required String changeText,
    String address = '',
    String phone = '',
    String slogan = 'Terima kasih!',
    String footer = '',
    String logoPath = '',
    String customerName = '',
    int paperWidth = 384,
  }) async {
    final bytes = await _buildReceiptBytes(
      storeName: storeName,
      items: items,
      totalText: totalText,
      paidText: paidText,
      changeText: changeText,
      address: address,
      phone: phone,
      slogan: slogan,
      footer: footer,
      logoPath: logoPath,
      customerName: customerName,
      paperWidth: paperWidth,
    );
    if (Platform.isWindows) {
      return printWindows(Uint8List.fromList(bytes));
    }
    if (!_isConnected || _connection == null) return false;
    try {
      await _connection!.output.writeBytes(bytes);
      await _connection!.output.allSent;
      return true;
    } catch (_) {
      _isConnected = false;
      _connection = null;
      return false;
    }
  }

  // ════════════════════════════════════════════════════
  //  ESC/POS HELPERS
  // ════════════════════════════════════════════════════

  static const int _paperChars = 32;

  List<int> _init() => [0x1B, 0x40];
  List<int> _setCodePage() => [0x1B, 0x74, 16]; // UTF-8 (code page 16)

  List<int> _lineSpacing(int dots) => [0x1B, 0x33, dots];

  List<int> _normalText() => [0x1D, 0x21, 0x00];
  List<int> _doubleWidthHeight() => [0x1D, 0x21, 0x11];

  List<int> _boldOn() => [0x1B, 0x45, 0x01];
  List<int> _boldOff() => [0x1B, 0x45, 0x00];

  List<int> _alignCenter() => [0x1B, 0x61, 0x01];
  List<int> _alignLeft() => [0x1B, 0x61, 0x00];
  List<int> _alignRight() => [0x1B, 0x61, 0x02];

  List<int> _feedLines(int n) => [0x1B, 0x64, n];
  List<int> _cut() => [0x1D, 0x56, 0x00];

  List<int> _text(String s) => Uint8List.fromList(utf8.encode(s));
  List<int> _nl() => _text('\r\n');

  List<int> _hr() => _text('${'=' * _paperChars}\r\n');

  List<int> _textLine(String s) {
    final clamped = s.length > _paperChars ? s.substring(0, _paperChars) : s;
    return _text('$clamped\r\n');
  }

  List<int> _wrapCenter(String s, {int? maxChars}) {
    final limit = maxChars ?? _paperChars;
    final lines = <String>[];
    final words = s.split(' ');
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ('$current $word'.length <= limit) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    final b = <int>[];
    for (final line in lines) {
      b.addAll(_alignCenter());
      b.addAll(_text('$line\r\n'));
    }
    b.addAll(_alignLeft());
    return b;
  }

  List<int> _wrapLeft(String s, {int? maxChars}) {
    final limit = maxChars ?? _paperChars;
    final lines = <String>[];
    final words = s.split(' ');
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ('$current $word'.length <= limit) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    final b = <int>[];
    for (final line in lines) {
      b.addAll(_text('$line\r\n'));
    }
    return b;
  }

  List<int> _twoCol(String left, String right) {
    final maxLeft = _paperChars - right.length;
    final l = left.length > maxLeft ? left.substring(0, maxLeft) : left;
    return _text('${l.padRight(maxLeft)}$right\r\n');
  }

  // ════════════════════════════════════════════════════
  //  RECEIPT BUILDER
  // ════════════════════════════════════════════════════

  List<int> _buildTestBytes() {
    final b = <int>[];
    b.addAll(_init());
    b.addAll(_setCodePage());
    b.addAll(_lineSpacing(10));
    b.addAll(_alignCenter());
    b.addAll(_boldOn());
    b.addAll(_doubleWidthHeight());
    b.addAll(_text('POS KRUPUK'));
    b.addAll(_normalText());
    b.addAll(_boldOff());
    b.addAll(_textLine('Printer Test'));
    b.addAll(_hr());
    b.addAll(_boldOn());
    b.addAll(_textLine('STRUK TEST'));
    b.addAll(_boldOff());
    b.addAll(_textLine('Berhasil terhubung!'));
    b.addAll(_hr());
    b.addAll(_feedLines(2));
    b.addAll(_cut());
    b.addAll(_alignLeft());
    return b;
  }

  Future<List<int>> _buildReceiptBytes({
    required String storeName,
    required List<ReceiptItem> items,
    required String totalText,
    required String paidText,
    required String changeText,
    String address = '',
    String phone = '',
    String slogan = 'Terima kasih!',
    String footer = '',
    String logoPath = '',
    String customerName = '',
    int paperWidth = 384,
  }) async {
    final b = <int>[];
    b.addAll(_init());
    b.addAll(_setCodePage());
    b.addAll(_lineSpacing(8));

    // ── LOGO ──
    if (logoPath.isNotEmpty) {
      try {
        final logoFile = File(logoPath);
        if (await logoFile.exists()) {
          final logoBytes = await _encodeLogoForPrinter(
            logoFile,
            paperWidth: paperWidth,
          );
          if (logoBytes != null) {
            b.addAll(_alignCenter());
            b.addAll(logoBytes);
            b.addAll(_feedLines(0));
          }
        }
      } catch (_) {}
    }

    // ── HEADER ──
    b.addAll(_alignCenter());
    b.addAll(_boldOn());
    b.addAll(_wrapCenter(storeName.toUpperCase(), maxChars: 16));
    b.addAll(_boldOff());

    if (address.isNotEmpty) {
      b.addAll(_wrapCenter(address));
    }
    if (phone.isNotEmpty) {
      b.addAll(_wrapCenter('Telp: $phone'));
    }

    b.addAll(_alignCenter());
    b.addAll(_textLine('================================'));

    // ── CUSTOMER NAME & DATE ──
    if (customerName.isNotEmpty) {
      final now = DateTime.now();
      final dateStr = '${now.day}/${now.month}/${now.year}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      b.addAll(_alignLeft());
      b.addAll(_wrapLeft('Nama            : $customerName'));
      b.addAll(_textLine('Tanggal cetak   : $dateStr $timeStr'));
      b.addAll(_alignCenter());
      b.addAll(_textLine('================================'));
    }

    // ── ITEMS ──
    b.addAll(_alignLeft());
    for (final item in items) {
      b.addAll(_boldOn());
      b.addAll(_twoCol(item.name, item.subtotal));
      b.addAll(_boldOff());

      if (item.detail.isNotEmpty) {
        b.addAll(_textLine('  ${item.detail}'));
      }
    }

    b.addAll(_textLine('================================'));

    // ── TOTALS ──
    b.addAll(_alignRight());
    b.addAll(_boldOn());
    b.addAll(_twoCol('TOTAL', totalText));
    b.addAll(_boldOff());

    b.addAll(_twoCol('BAYAR', paidText));
    b.addAll(_twoCol('KEMBALI', changeText));
    b.addAll(_textLine('================================'));

    // ── FOOTER ──
    b.addAll(_alignCenter());
    b.addAll(_boldOn());
    b.addAll(_wrapCenter(slogan.toUpperCase()));
    b.addAll(_boldOff());

    if (footer.isNotEmpty) {
      b.addAll(_wrapCenter(footer));
    }

    b.addAll(_feedLines(3));
    b.addAll(_cut());
    b.addAll(_alignLeft());
    return b;
  }

  // ════════════════════════════════════════════════════
  //  LOGO ENCODING (GS v 0 - Raster Bit Image)
  // ════════════════════════════════════════════════════

  Future<Uint8List?> _encodeLogoForPrinter(
    File logoFile, {
    int paperWidth = 384,
  }) async {
    try {
      final bytes = await logoFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // Limit size: max width = paper, max height = 200 dots
      final maxWidth = min(paperWidth, 384);
      final maxHeight = 200;
      final aspectRatio = image.width / image.height;
      var scaledWidth = min(image.width, maxWidth).toInt();
      var scaledHeight = (scaledWidth / aspectRatio).toInt();

      if (scaledHeight > maxHeight) {
        scaledHeight = maxHeight;
        scaledWidth = (scaledHeight * aspectRatio).toInt();
      }
      if (scaledWidth > maxWidth) scaledWidth = maxWidth;

      // Resize
      final resized = img.copyResize(
        image,
        width: scaledWidth,
        height: scaledHeight,
        interpolation: img.Interpolation.linear,
      );

      // Grayscale + threshold
      final grayscale = img.grayscale(resized);

      // Pack 8 pixels per byte
      final int bytesPerRow = (scaledWidth + 7) ~/ 8;
      final List<int> bitmap = [];

      for (int y = 0; y < scaledHeight; y++) {
        for (int x = 0; x < bytesPerRow; x++) {
          int byte = 0;
          for (int bit = 0; bit < 8; bit++) {
            final px = x * 8 + bit;
            if (px < scaledWidth) {
              final pixel = grayscale.getPixel(px, y);
              final luminance =
                  (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).toInt();
              if (luminance < 160) {
                byte |= (0x80 >> bit);
              }
            }
          }
          bitmap.add(byte);
        }
      }

      // GS v 0 m
      // m=0: normal, m=1: double width, m=2: double height, m=3: double both
      final List<int> escBytes = [];
      escBytes.addAll([0x1D, 0x76, 0x30, 0x00]); // GS v 0 m=0
      escBytes.add(bytesPerRow & 0xFF);
      escBytes.add((bytesPerRow >> 8) & 0xFF);
      escBytes.add(scaledHeight & 0xFF);
      escBytes.add((scaledHeight >> 8) & 0xFF);
      escBytes.addAll(bitmap);

      return Uint8List.fromList(escBytes);
    } catch (_) {
      return null;
    }
  }
}

class ReceiptItem {
  final String name;
  final String detail;
  final String subtotal;

  const ReceiptItem({required this.name, this.detail = '', this.subtotal = ''});
}
