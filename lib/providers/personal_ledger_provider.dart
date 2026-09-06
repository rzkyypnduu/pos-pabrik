import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/personal_ledger.dart';
import '../constants/formatters.dart';

class PersonalLedgerProvider extends ChangeNotifier {
  List<PersonalLedger> _monthLedgers = [];
  List<PersonalLedger> _currentDateLedgers = [];
  bool _isCarryForward = false;
  String _activeMonth = '';

  List<PersonalLedger> get monthLedgers => _monthLedgers;
  List<PersonalLedger> get currentDateLedgers => _currentDateLedgers;
  bool get isCarryForward => _isCarryForward;

  int get monthTotal => _monthLedgers.fold<int>(0, (sum, l) => sum + l.amount);

  Future<void> loadMonth(String activeMonth) async {
    _activeMonth = activeMonth;
    final range = monthRange(activeMonth);
    _monthLedgers = await DatabaseHelper.instance.getPersonalLedgersByMonth(range[0], range[1]);
    notifyListeners();
  }

  Future<void> loadForDate(String date) async {
    final dayLedgers = await DatabaseHelper.instance.getPersonalLedgersByDate(date);
    if (dayLedgers.isNotEmpty) {
      _currentDateLedgers = dayLedgers;
      _isCarryForward = false;
    } else {
      final latest = await DatabaseHelper.instance.getLatestPersonalLedgers(date);
      _currentDateLedgers = latest;
      _isCarryForward = latest.isNotEmpty;
    }
    notifyListeners();
  }

  Future<void> addHutangPribadi(String date, String name, int amount, String note) async {
    await DatabaseHelper.instance.insertPersonalLedger(PersonalLedger(
      date: date,
      name: name,
      amount: amount,
      note: note.isNotEmpty ? note : null,
    ));
    await loadForDate(date);
  }

  Future<void> deleteEntry(int id) async {
    await DatabaseHelper.instance.deletePersonalLedger(id);
    await loadMonth(_activeMonth);
    notifyListeners();
  }

  Future<void> updateEntry(int id, String name, int amount, String note) async {
    await DatabaseHelper.instance.updatePersonalLedger(PersonalLedger(
      id: id,
      date: '',
      name: name,
      amount: amount,
      note: note.isNotEmpty ? note : null,
    ));
    await loadMonth(_activeMonth);
    notifyListeners();
  }
}
