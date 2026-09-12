import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../constants/formatters.dart';

class RingkasanProvider extends ChangeNotifier {
  int totalOil = 0;
  double totalOilKg = 0;
  int totalStockMgmt = 0;
  int totalRemain = 0;
  int totalHutangPel = 0;
  int totalHutangPri = 0;
  double totalSaldo = 0;
  int grand = 0;

  // Analytics data
  List<Map<String, dynamic>> topProducts = [];
  List<Map<String, dynamic>> topCustomers = [];
  List<Map<String, dynamic>> dailySales = [];
  int totalMonthlySales = 0;
  int totalMonthlyPaid = 0;
  int totalMonthlyTransactions = 0;

  String _topCustomersSortMode = 'paid';
  String _activeMonth = '';
  String get topCustomersSortMode => _topCustomersSortMode;

  Future<void> setTopCustomersSortMode(String mode) async {
    if (mode == _topCustomersSortMode) return;
    _topCustomersSortMode = mode;
    if (_activeMonth.isEmpty) {
      notifyListeners();
      return;
    }
    final range = monthRange(_activeMonth);
    topCustomers = await DatabaseHelper.instance.getTopCustomersByMonth(
      range[0],
      range[1],
      sortBy: mode,
    );
    notifyListeners();
  }

  Future<void> calculate({
    required String activeMonth,
    required String selectedDate,
    required Map<String, int> customerBalances,
  }) async {
    _activeMonth = activeMonth;
    final range = monthRange(activeMonth);

    final oils = await DatabaseHelper.instance
        .getOilStocksByMonth(range[0], range[1]);
    totalOil = oils.fold<int>(0, (sum, o) => sum + o.subtotal);
    totalOilKg = oils.fold<double>(0, (sum, o) => sum + o.qty);

    final stockMgmts = await DatabaseHelper.instance
        .getStockManagementsByMonth(range[0], range[1]);
    totalStockMgmt = stockMgmts.fold<int>(0, (sum, s) => sum + s.subtotal);

    final stockRemains = await DatabaseHelper.instance
        .getStockRemainingsByMonth(range[0], range[1]);
    totalRemain = stockRemains.fold<int>(0, (sum, s) => sum + s.subtotal);

    totalHutangPel = customerBalances.entries.fold<int>(
      0,
      (sum, e) => sum + (e.value > 0 ? e.value : 0),
    );

    final personalLedgers = await DatabaseHelper.instance
        .getPersonalLedgersByMonth(range[0], range[1]);
    totalHutangPri = personalLedgers.fold<int>(0, (sum, l) => sum + l.amount);

    final saldoLogs = await DatabaseHelper.instance
        .getSaldoDeductionsByMonth(range[0], range[1]);
    totalSaldo = saldoLogs.fold<double>(0, (sum, s) => sum + s.result);

    grand = totalOil + totalStockMgmt + totalRemain + totalHutangPel;

    // Analytics
    topProducts = await DatabaseHelper.instance.getTopProductsByMonth(
      range[0],
      range[1],
    );
    topCustomers = await DatabaseHelper.instance.getTopCustomersByMonth(
      range[0],
      range[1],
      sortBy: _topCustomersSortMode,
    );
    dailySales = await DatabaseHelper.instance.getDailySalesByMonth(
      range[0],
      range[1],
    );
    totalMonthlySales = dailySales.fold<int>(
      0,
      (sum, d) => sum + (d['totalSales'] as int? ?? 0),
    );
    totalMonthlyPaid = dailySales.fold<int>(
      0,
      (sum, d) => sum + (d['totalPaid'] as int? ?? 0),
    );
    totalMonthlyTransactions = dailySales.fold<int>(
      0,
      (sum, d) => sum + (d['transactionCount'] as int? ?? 0),
    );

    notifyListeners();
  }

  Future<void> resetMonth(String activeMonth) async {
    final range = monthRange(activeMonth);
    await DatabaseHelper.instance.resetMonth(range[0], range[1]);
    notifyListeners();
  }

  Future<void> resetAll() async {
    await DatabaseHelper.instance.resetAll();
    notifyListeners();
  }

  Future<void> clearOilAndSaldo() async {
    await DatabaseHelper.instance.clearOilAndSaldo();
    notifyListeners();
  }
}
