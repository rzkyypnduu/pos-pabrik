import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

String rupiah(int? amount) {
  final val = amount ?? 0;
  final formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );
  return formatter.format(val);
}

String rupiahPlain(int? amount) {
  final val = amount ?? 0;
  final formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: '',
    decimalDigits: 0,
  );
  return formatter.format(val).trim();
}

/// Adds thousand separators (dots) to integer input as user types.
/// Strips non-digits on commit.
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue();
    }
    final formatted = _addDots(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _addDots(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}

/// Extracts the integer value from a dot-formatted Rupiah string.
int parseRupiah(String text) {
  return int.tryParse(text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
}

String fmtKg(double? qty) {
  final val = qty ?? 0;
  if (val == val.toInt().toDouble()) {
    return val.toInt().toString();
  }
  final formatted = val.toStringAsFixed(1);
  return formatted.replaceAll('.', ',').replaceAll(RegExp(r',0$'), '');
}

String fmtDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '-';
  try {
    final date = DateTime.parse(dateStr);
    return DateFormat('d MMMM yyyy', 'id_ID').format(date);
  } catch (_) {
    return dateStr;
  }
}

String fmtDateLong(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '-';
  try {
    final date = DateTime.parse(dateStr);
    return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
  } catch (_) {
    return dateStr;
  }
}

String fmtDateShort(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '-';
  try {
    final date = DateTime.parse(dateStr);
    return DateFormat('yyyy-MM-dd').format(date);
  } catch (_) {
    return dateStr;
  }
}

int roundTotal(int total) {
  final thousands = total ~/ 1000 * 1000;
  final remainder = total - thousands;
  return remainder < 500 ? thousands : thousands + 1000;
}

String todayString() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String activeMonthString() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}

String monthLabel(String activeMonth) {
  const names = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  try {
    final parts = activeMonth.split('-');
    final monthIndex = int.parse(parts[1]) - 1;
    return '${names[monthIndex]} ${parts[0]}';
  } catch (_) {
    return activeMonth;
  }
}

List<String> monthRange(String activeMonth) {
  final start = '$activeMonth-01';
  final dt = DateTime.parse('$start 00:00:00');
  final lastDay = DateTime(dt.year, dt.month + 1, 0).day;
  final end = '$activeMonth-${lastDay.toString().padLeft(2, '0')}';
  return [start, end];
}

String prevMonth(String activeMonth) {
  final dt = DateTime.parse('$activeMonth-01 00:00:00');
  final prev = DateTime(dt.year, dt.month - 1, 1);
  return '${prev.year.toString().padLeft(4, '0')}-${prev.month.toString().padLeft(2, '0')}';
}

String nextMonth(String activeMonth) {
  final dt = DateTime.parse('$activeMonth-01 00:00:00');
  final nxt = DateTime(dt.year, dt.month + 1, 1);
  return '${nxt.year.toString().padLeft(4, '0')}-${nxt.month.toString().padLeft(2, '0')}';
}

List<String> recentDateStrings({int days = 7}) {
  final now = DateTime.now();
  return List.generate(days, (i) {
    final d = now.subtract(Duration(days: i));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  });
}
