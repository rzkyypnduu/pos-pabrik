import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/saldo_deduction.dart';
import '../constants/formatters.dart';

class SaldoDeductionProvider extends ChangeNotifier {
  List<SaldoDeduction> _monthLogs = [];
  SaldoDeduction? _currentDateLog;
  bool _isCarryForward = false;

  List<SaldoDeduction> get monthLogs => _monthLogs;
  SaldoDeduction? get currentDateLog => _currentDateLog;
  bool get isCarryForward => _isCarryForward;

  double get monthTotal => _monthLogs.fold<double>(0, (sum, s) => sum + s.result);

  Future<void> loadMonth(String activeMonth) async {
    final range = monthRange(activeMonth);
    _monthLogs = await DatabaseHelper.instance.getSaldoDeductionsByMonth(range[0], range[1]);
    notifyListeners();
  }

  Future<void> loadForDate(String date) async {
    final dayLogs = await DatabaseHelper.instance.getSaldoDeductionsByDate(date);
    if (dayLogs.isNotEmpty) {
      _currentDateLog = dayLogs.first;
      _isCarryForward = false;
    } else {
      _currentDateLog = await DatabaseHelper.instance.getLatestSaldoDeduction(date);
      _isCarryForward = _currentDateLog != null;
    }
    notifyListeners();
  }

  Future<void> addSaldo(String date, double a, double b, String note) async {
    final existing = _currentDateLog;
    if (existing != null && existing.date == date && !_isCarryForward) {
      await DatabaseHelper.instance.updateSaldoDeduction(SaldoDeduction(
        id: existing.id,
        date: date,
        a: a,
        b: b,
        note: note.isNotEmpty ? note : existing.note,
      ));
    } else {
      await DatabaseHelper.instance.insertSaldoDeduction(SaldoDeduction(
        date: date,
        a: a,
        b: b,
        note: note.isNotEmpty ? note : null,
      ));
    }
    await loadForDate(date);
  }

  Future<void> deleteEntry(int id) async {
    await DatabaseHelper.instance.deleteSaldoDeduction(id);
    notifyListeners();
  }
}
