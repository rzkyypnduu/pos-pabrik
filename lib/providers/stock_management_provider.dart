import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/stock_management.dart';
import '../constants/formatters.dart';

class StockManagementProvider extends ChangeNotifier {
  List<StockManagement> _monthStocks = [];
  List<StockManagement> _dayStocks = [];
  List<StockManagement> _currentDateStocks = [];
  List<StockManagement> _monthTotalRecords = [];
  bool _isCarryForward = false;
  String _activeMonth = '';

  List<StockManagement> get monthStocks => _monthStocks;
  List<StockManagement> get dayStocks => _dayStocks;
  List<StockManagement> get currentDateStocks => _currentDateStocks;
  bool get isCarryForward => _isCarryForward;

  int get monthTotal =>
      _monthTotalRecords.fold<int>(0, (sum, s) => sum + s.subtotal);
  int get dayTotal =>
      _currentDateStocks.fold<int>(0, (sum, s) => sum + s.subtotal);

  List<String> get holderNames {
    return _currentDateStocks.map((s) => s.name).toSet().toList()..sort();
  }

  Future<void> loadMonthStocks(String activeMonth) async {
    _activeMonth = activeMonth;
    final range = monthRange(activeMonth);
    _monthStocks = await DatabaseHelper.instance.getStockManagementsByMonth(range[0], range[1]);
    _monthTotalRecords = await DatabaseHelper.instance
        .getLatestStockManagementsByMonth(range[0], range[1]);
    await _healDuplicateBatchIds(_monthStocks);
    notifyListeners();
  }

  Future<void> loadDayStocks(String date) async {
    _dayStocks = await DatabaseHelper.instance.getStockManagementsByDate(date);
    await _healDuplicateBatchIds(_dayStocks);
    notifyListeners();
  }

  Future<void> loadForDate(String date) async {
    _currentDateStocks =
        await DatabaseHelper.instance.materializeStockManagements(date);
    _isCarryForward = false;
    await _reloadMonth();
    await _healDuplicateBatchIds(_currentDateStocks);
    notifyListeners();
  }

  Future<void> _healDuplicateBatchIds(List<StockManagement> items) async {
    var healed = false;
    for (final item in items) {
      final batches = item.batches ?? [];
      final seen = <String>{};
      var changed = false;
      for (final b in batches) {
        final id = (b['id'] as String?) ?? '';
        if (id.isEmpty || seen.contains(id)) {
          b['id'] = '${DateTime.now().microsecondsSinceEpoch}_${batches.indexOf(b)}';
          changed = true;
        } else {
          seen.add(id);
        }
      }
      if (changed) {
        final updated = StockManagement(
          id: item.id,
          date: item.date,
          name: item.name,
          qty: item.totalQty,
          price: item.price,
          batches: batches,
        );
        await DatabaseHelper.instance.updateStockManagement(updated);
        healed = true;
      }
    }
    if (healed) {
      final activeMonth = _activeMonth;
      if (activeMonth.isNotEmpty) {
        _monthStocks = await DatabaseHelper.instance.getStockManagementsByMonth(monthRange(activeMonth)[0], monthRange(activeMonth)[1]);
      }
    }
  }

  Future<void> _reloadMonth() async {
    if (_activeMonth.isNotEmpty) {
      await loadMonthStocks(_activeMonth);
    } else {
      notifyListeners();
    }
  }

  Future<void> addStockMgmt(String date, String name, int price, List<double> sacks) async {
    StockManagement? existing;
    for (final s in _monthStocks) {
      if (s.name.toLowerCase() == name.toLowerCase() && s.date == date) {
        existing = s;
        break;
      }
    }

    final newBatches = <Map<String, dynamic>>[
      for (int i = 0; i < sacks.length; i++)
        {
          'id': '${DateTime.now().microsecondsSinceEpoch}_$i',
          'date': date,
          'price': price,
          'sacks': [sacks[i]],
        }
    ];

    if (existing != null) {
      final batches = List<Map<String, dynamic>>.from(existing.batches ?? []);
      batches.addAll(newBatches);
      final updated = StockManagement(
        id: existing.id,
        date: date,
        name: existing.name,
        qty: existing.totalQty,
        price: price > 0 ? price : existing.price,
        batches: batches,
      );
      await DatabaseHelper.instance.updateStockManagement(updated);
    } else {
      final qty = sacks.fold<double>(0, (a, b) => a + b);
      await DatabaseHelper.instance.insertStockManagement(StockManagement(
        date: date,
        name: name,
        qty: qty,
        price: price,
        batches: newBatches,
      ));
    }
    await _reloadMonth();
    await loadForDate(date);
  }

  Future<void> deleteStockMgmt(int id) async {
    String? day;
    for (final s in _monthStocks) {
      if (s.id == id) {
        day = s.date;
        break;
      }
    }
    await DatabaseHelper.instance.deleteStockManagement(id);
    if (day == null || day.isEmpty) {
      await _reloadMonth();
    } else {
      await loadForDate(day);
    }
  }

  Future<void> deleteStockBatch(int itemId, String batchId) async {
    final item = _monthStocks.firstWhere((s) => s.id == itemId);
    final batches = (item.batches ?? [])
        .where((b) => b['id'] != batchId)
        .toList();
    if (batches.isEmpty) {
      await DatabaseHelper.instance.deleteStockManagement(itemId);
    } else {
      final updated = StockManagement(
        id: item.id,
        date: item.date,
        name: item.name,
        qty: item.totalQty,
        price: item.price,
        batches: batches,
      );
      await DatabaseHelper.instance.updateStockManagement(updated);
    }
    final day = item.date;
    if (day == null || day.isEmpty) {
      await _reloadMonth();
    } else {
      await loadForDate(day);
    }
  }

  Future<void> updateBatchSacks(int itemId, String batchId, List<double> newSacks) async {
    final item = _monthStocks.firstWhere((s) => s.id == itemId);
    final batches = List<Map<String, dynamic>>.from(item.batches ?? []);
    final batchIndex = batches.indexWhere((b) => b['id'] == batchId);
    if (batchIndex == -1) return;
    batches[batchIndex]['sacks'] = newSacks;
    final updated = StockManagement(
      id: item.id,
      date: item.date,
      name: item.name,
      qty: item.totalQty,
      price: item.price,
      batches: batches,
    );
    await DatabaseHelper.instance.updateStockManagement(updated);
    final day = item.date;
    if (day == null || day.isEmpty) {
      await _reloadMonth();
    } else {
      await loadForDate(day);
    }
  }

  Future<void> updateBatchPrice(int itemId, String batchId, int newPrice) async {
    final item = _monthStocks.firstWhere((s) => s.id == itemId);
    final batches = List<Map<String, dynamic>>.from(item.batches ?? []);
    final batchIndex = batches.indexWhere((b) => b['id'] == batchId);
    if (batchIndex == -1) return;
    batches[batchIndex]['price'] = newPrice;
    final updated = StockManagement(
      id: item.id,
      date: item.date,
      name: item.name,
      qty: item.totalQty,
      price: item.price,
      batches: batches,
    );
    await DatabaseHelper.instance.updateStockManagement(updated);
    final day = item.date;
    if (day == null || day.isEmpty) {
      await _reloadMonth();
    } else {
      await loadForDate(day);
    }
  }
}
