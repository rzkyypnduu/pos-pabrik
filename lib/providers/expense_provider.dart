import 'package:flutter/material.dart';
import '../constants/formatters.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';

class ExpenseProvider extends ChangeNotifier {
  List<Expense> _dayExpenses = [];
  List<Expense> _monthExpenses = [];

  List<Expense> get dayExpenses => _dayExpenses;
  List<Expense> get monthExpenses => _monthExpenses;

  int get dayExpenseTotal =>
      _dayExpenses.fold<int>(0, (sum, e) => sum + e.amount);
  int get monthExpenseTotal =>
      _monthExpenses.fold<int>(0, (sum, e) => sum + e.amount);

  Future<void> loadDayExpenses(String date) async {
    _dayExpenses = await DatabaseHelper.instance.getExpensesByDate(date);
    notifyListeners();
  }

  Future<void> loadMonthExpenses(String startDate, String endDate) async {
    _monthExpenses = await DatabaseHelper.instance.getExpensesByMonth(
      startDate,
      endDate,
    );
    notifyListeners();
  }

  Future<void> addExpense(String date, int amount, String note) async {
    await DatabaseHelper.instance.insertExpense(
      Expense(date: date, amount: amount, note: note.isNotEmpty ? note : null),
    );
    await loadDayExpenses(date);
    await _reloadMonthFor(date);
  }

  Future<void> deleteExpense(int id, String date) async {
    await DatabaseHelper.instance.deleteExpense(id);
    await loadDayExpenses(date);
    await _reloadMonthFor(date);
  }

  Future<void> _reloadMonthFor(String date) async {
    final month = date.length >= 7 ? date.substring(0, 7) : date;
    final range = monthRange(month);
    await loadMonthExpenses(range[0], range[1]);
  }
}
