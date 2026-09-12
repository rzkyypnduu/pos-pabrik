import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/stock_remaining.dart';
import '../models/product.dart';
import '../constants/formatters.dart';

class StockRemainingProvider extends ChangeNotifier {
List<StockRemaining> _monthStocks = [];
  List<StockRemaining> _dayStocks = [];
  List<StockRemaining> _currentDateStocks = [];
  List<StockRemaining> _monthTotalRecords = [];
  bool _isCarryForward = false;
  String _activeMonth = '';

  List<StockRemaining> get monthStocks => _monthStocks;
  List<StockRemaining> get dayStocks => _dayStocks;
  List<StockRemaining> get currentDateStocks => _currentDateStocks;
  bool get isCarryForward => _isCarryForward;

  int get monthTotal =>
      _monthTotalRecords.fold<int>(0, (sum, s) => sum + s.subtotal);
  int get dayTotal => _dayStocks.fold<int>(0, (sum, s) => sum + s.subtotal);

  Future<void> loadMonthStocks(String activeMonth) async {
    _activeMonth = activeMonth;
    final range = monthRange(activeMonth);
    _monthStocks = await DatabaseHelper.instance.getStockRemainingsByMonth(range[0], range[1]);
    _monthTotalRecords = await DatabaseHelper.instance
        .getLatestStockRemainingsByMonth(range[0], range[1]);
    notifyListeners();
  }

  Future<void> loadDayStocks(String date) async {
    _dayStocks = await DatabaseHelper.instance.getStockRemainingsByDate(date);
    notifyListeners();
  }

  Future<void> loadForDate(String date) async {
    _currentDateStocks =
        await DatabaseHelper.instance.materializeStockRemainings(date);
    _isCarryForward = false;
    await _reloadMonth();
    notifyListeners();
  }

  Future<void> _reloadMonth() async {
    if (_activeMonth.isNotEmpty) {
      await loadMonthStocks(_activeMonth);
    } else {
      notifyListeners();
    }
  }

  Future<void> addRemain(String date, Product product, double qty, int price) async {
    await DatabaseHelper.instance.insertStockRemaining(StockRemaining(
      date: date,
      name: product.name,
      qty: qty,
      price: price,
    ));
    await _reloadMonth();
    await loadForDate(date);
  }

  Future<void> deleteRemain(int id) async {
    await DatabaseHelper.instance.deleteStockRemaining(id);
    await _reloadMonth();
  }

  Future<void> updateRemain(int id, double qty, int price, String date) async {
    final existing = _monthStocks.firstWhere((s) => s.id == id);
    await DatabaseHelper.instance.updateStockRemaining(StockRemaining(
      id: id,
      date: date,
      name: existing.name,
      qty: qty,
      price: price,
    ));
    await _reloadMonth();
    await loadForDate(date);
  }
}
