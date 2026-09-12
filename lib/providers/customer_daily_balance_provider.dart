import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/customer_daily_balance.dart';
import '../constants/formatters.dart';

class CustomerDailyBalanceProvider extends ChangeNotifier {
  List<CustomerDailyBalance> _monthBalances = [];
  List<CustomerDailyBalance> _currentDateBalances = [];
  List<CustomerDailyBalance> _monthTotalBalances = [];
  bool _isCarryForward = false;
  String _activeMonth = '';

  List<CustomerDailyBalance> get monthBalances => _monthBalances;
  List<CustomerDailyBalance> get currentDateBalances => _currentDateBalances;
  bool get isCarryForward => _isCarryForward;

  int get monthTotal =>
      _monthTotalBalances.fold<int>(0, (sum, b) => sum + b.amount);
  int get dayTotal =>
      _currentDateBalances.fold<int>(0, (sum, b) => sum + b.amount);

  Future<void> loadMonth(String activeMonth) async {
    _activeMonth = activeMonth;
    final range = monthRange(activeMonth);
    _monthBalances = await DatabaseHelper.instance
        .getCustomerDailyBalancesByMonth(range[0], range[1]);
    _monthTotalBalances = await DatabaseHelper.instance
        .getLatestCustomerDailyBalancesByMonth(range[0], range[1]);
    notifyListeners();
  }

  Future<void> loadForDate(String date) async {
    _currentDateBalances = await DatabaseHelper.instance
        .materializeCustomerDailyBalances(date);
    _isCarryForward = false;
    await loadMonth(_activeMonth);
    notifyListeners();
  }

  /// Tambah hutang hari ini: jika nama sudah punya catatan di hari yang sama,
  /// jumlahnya ditambahkan (bukan menimpa).
  Future<void> addCustomDebt(String date, String name, int amount) async {
    if (amount <= 0) return;
    final today = await DatabaseHelper.instance
        .getCustomerDailyBalancesByDate(date);
    final existing = today.where((b) => b.name == name).toList();
    if (existing.isNotEmpty) {
      await DatabaseHelper.instance.updateCustomerDailyBalance(
        CustomerDailyBalance(
          id: existing.first.id,
          date: date,
          name: name,
          amount: existing.first.amount + amount,
        ),
      );
    } else {
      await DatabaseHelper.instance.insertCustomerDailyBalance(
        CustomerDailyBalance(date: date, name: name, amount: amount),
      );
    }
    await loadForDate(date);
  }

  Future<void> deleteEntry(int id) async {
    String? day;
    for (final b in _monthBalances) {
      if (b.id == id) {
        day = b.date;
        break;
      }
    }
    await DatabaseHelper.instance.deleteCustomerDailyBalance(id);
    if (day == null || day.isEmpty) {
      await loadMonth(_activeMonth);
      notifyListeners();
    } else {
      await loadForDate(day);
    }
  }

  Future<void> updateEntry(int id, {int? amount, String? name}) async {
    String? day;
    for (final b in _monthBalances) {
      if (b.id == id) {
        day = b.date;
        break;
      }
    }
    final cur = _monthBalances
        .where((b) => b.id == id)
        .toList()
        .fold<CustomerDailyBalance?>(
      null,
      (prev, b) => b,
    );
    await DatabaseHelper.instance.updateCustomerDailyBalance(
      CustomerDailyBalance(
        id: id,
        date: '',
        name: name ?? cur?.name ?? '',
        amount: amount ?? cur?.amount ?? 0,
      ),
    );
    if (day == null || day.isEmpty) {
      await loadMonth(_activeMonth);
      notifyListeners();
    } else {
      await loadForDate(day);
    }
  }
}