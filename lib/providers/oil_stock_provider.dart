import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/oil_stock.dart';
import '../constants/formatters.dart';

class OilStockProvider extends ChangeNotifier {
  List<OilStock> _monthStocks = [];
  List<OilStock> _dayStocks = [];
  OilStock? _currentDateStock;
  OilStock? _monthTotalStocks;
  bool _isCarryForward = false;
  String _activeMonth = '';

  List<OilStock> get monthStocks => _monthStocks;
  List<OilStock> get dayStocks => _dayStocks;
  OilStock? get currentDateStock => _currentDateStock;
  bool get isCarryForward => _isCarryForward;

  int get monthTotal =>
      _monthTotalStocks?.subtotal ?? _monthStocks.fold<int>(0, (sum, o) => sum + o.subtotal);
  int get dayTotal => _dayStocks.fold<int>(0, (sum, o) => sum + o.subtotal);

  Future<void> loadMonthStocks(String activeMonth) async {
    _activeMonth = activeMonth;
    final range = monthRange(activeMonth);
    _monthStocks = await DatabaseHelper.instance.getOilStocksByMonth(range[0], range[1]);
    final latest = await DatabaseHelper.instance
        .getLatestOilStockByMonth(range[0], range[1]);
    _monthTotalStocks = latest;
    notifyListeners();
  }

  Future<void> loadDayStocks(String date) async {
    _dayStocks = await DatabaseHelper.instance.getOilStocksByDate(date);
    notifyListeners();
  }

  Future<void> loadForDate(String date) async {
    _currentDateStock =
        await DatabaseHelper.instance.materializeOilStock(date);
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

  Future<void> addOil(String date, double qty, double price) async {
    final existing = _currentDateStock;
    if (existing != null && existing.date == date && !_isCarryForward) {
      await DatabaseHelper.instance.updateOilStock(OilStock(
        id: existing.id,
        date: date,
        qty: qty,
        price: price,
      ));
    } else {
      await DatabaseHelper.instance.insertOilStock(OilStock(
        date: date,
        qty: qty,
        price: price,
      ));
    }
    await _reloadMonth();
    await loadForDate(date);
  }

  Future<void> deleteOil(int id) async {
    await DatabaseHelper.instance.deleteOilStock(id);
    await _reloadMonth();
  }
}
