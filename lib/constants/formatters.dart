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

/// Adds thousand separators (dots) to input as user types.
/// When [allowDecimal] is true, one comma is allowed as decimal separator.
class RupiahInputFormatter extends TextInputFormatter {
  final bool allowDecimal;
  final int maxDecimals;
  RupiahInputFormatter({this.allowDecimal = false, this.maxDecimals = 1});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    if (!allowDecimal) {
      final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return const TextEditingValue();
      final formatted = _addDots(digits);
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    final text = newValue.text;
    final hasComma = text.contains(',');
    String integerPart;
    String decimalPart = '';

    if (hasComma) {
      final parts = text.split(',');
      integerPart = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
      if (parts.length > 1) {
        final rawDecimal = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
        decimalPart = rawDecimal.length > maxDecimals
            ? rawDecimal.substring(0, maxDecimals)
            : rawDecimal;
      }
    } else {
      integerPart = text.replaceAll(RegExp(r'[^0-9]'), '');
    }

    if (integerPart.isEmpty && !hasComma) return const TextEditingValue();
    if (integerPart.isEmpty) integerPart = '0';

    final formatted = hasComma
        ? '${_addDots(integerPart)},$decimalPart'
        : _addDots(integerPart);

    final oldText = oldValue.text;
    final oldCursor = newValue.selection.end;
    int newCursor = formatted.length;

    if (oldText.isNotEmpty && oldCursor > 0) {
      final textBeforeCursor = oldText.substring(0, oldCursor.clamp(0, oldText.length));
      final digitsBeforeCursor = textBeforeCursor.replaceAll(RegExp(r'[^0-9]'), '');
      int count = 0;
      for (int i = 0; i < formatted.length; i++) {
        if (RegExp(r'[0-9]').hasMatch(formatted[i])) count++;
        if (count == digitsBeforeCursor.length + 1) {
          newCursor = i + 1;
          break;
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor.clamp(0, formatted.length)),
    );
  }
}

String _addDots(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Extracts the integer value from a dot-formatted Rupiah string.
int parseRupiah(String text) {
  return int.tryParse(text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
}

/// Parses text produced by [RupiahInputFormatter] (dots as thousand
/// separators, comma as decimal separator) into a [double].
double parseNumInput(String text) {
  return double.tryParse(
        text.replaceAll('.', '').replaceAll(',', '.'),
      ) ??
      0;
}

/// Formats [value] the same way [RupiahInputFormatter] would, so a value
/// like `18000.5` is shown as `18.000,5`.
String rupiahInputText(num value, {int decimals = 1}) {
  final rounded = value.round();
  if (value == rounded) {
    return _addDots(rounded.toString());
  }
  final whole = value.floor();
  final factor = 10 * decimals;
  final dec = ((value - whole) * factor).round();
  return '${_addDots(whole.toString())},$dec';
}

/// Rupiah formatter that keeps one decimal digit when [amount] is not a
/// whole number.
String rupiahD(num? amount) {
  final val = amount ?? 0;
  if (val == val.roundToDouble()) {
    return rupiah(val.toInt());
  }
  final formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 1,
  );
  return formatter.format(val);
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
