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

  Map<String, dynamic>? daily;

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

    // Monthly totals — nilai TERAKHIR per slot (copy & putus: tiap hari punya
    // salinan sendiri, jadi total memakai posisi terakhir agar tidak dobel).
    final latestOil = await DatabaseHelper.instance
        .getLatestOilStockByMonth(range[0], range[1]);
    totalOil = latestOil?.subtotal ?? 0;
    totalOilKg = latestOil?.qty ?? 0;

    final stockMgmts = await DatabaseHelper.instance
        .getLatestStockManagementsByMonth(range[0], range[1]);
    totalStockMgmt = stockMgmts.fold<int>(0, (sum, s) => sum + s.subtotal);

    final stockRemains = await DatabaseHelper.instance
        .getLatestStockRemainingsByMonth(range[0], range[1]);
    totalRemain = stockRemains.fold<int>(0, (sum, s) => sum + s.subtotal);

    final customerDailyMonth = await DatabaseHelper.instance
        .getLatestCustomerDailyBalancesByMonth(range[0], range[1]);
    final hasDailyDebt =
        customerDailyMonth.every((b) => b.amount == 0) &&
            customerDailyMonth.isNotEmpty;
    if (hasDailyDebt || customerDailyMonth.isEmpty) {
      totalHutangPel = customerBalances.entries.fold<int>(
        0,
        (sum, e) => sum + (e.value > 0 ? e.value : 0),
      );
    } else {
      totalHutangPel =
          customerDailyMonth.fold<int>(0, (sum, b) => sum + b.amount);
    }

    final personalLedgers = await DatabaseHelper.instance
        .getLatestPersonalLedgersByMonth(range[0], range[1]);
    totalHutangPri = personalLedgers.fold<int>(0, (sum, l) => sum + l.amount);

    final saldoLog = await DatabaseHelper.instance
        .getLatestSaldoDeductionByMonth(range[0], range[1]);
    totalSaldo = saldoLog?.result ?? 0;

    grand = totalOil + totalStockMgmt + totalRemain + totalHutangPel;

    // Daily totals — cumulative from start of month up to selectedDate
    if (selectedDate.startsWith(activeMonth)) {
      final dayOil = await DatabaseHelper.instance
          .getLatestOilStockByMonth(range[0], selectedDate);
      final dayStockMgmt = await DatabaseHelper.instance
          .getLatestStockManagementsByMonth(range[0], selectedDate);
      final dayRemain = await DatabaseHelper.instance
          .getLatestStockRemainingsByMonth(range[0], selectedDate);
      final dayLedger = await DatabaseHelper.instance.getCustomerLedgersByMonth(
        range[0],
        selectedDate,
      );
      final dayCustomerDaily = await DatabaseHelper.instance
          .getLatestCustomerDailyBalancesByMonth(range[0], selectedDate);
      final hasDayDaily = dayCustomerDaily.any((b) => b.amount > 0);
      final dHutangPel = hasDayDaily
          ? dayCustomerDaily.fold<int>(0, (sum, b) => sum + b.amount)
          : dayLedger.fold<int>(
              0,
              (sum, l) => sum + (l.type == 'tambah' ? l.amount : -l.amount),
            );
      final dayPersonal = await DatabaseHelper.instance
          .getLatestPersonalLedgersByMonth(range[0], selectedDate);
      final daySaldo = await DatabaseHelper.instance
          .getLatestSaldoDeductionByMonth(range[0], selectedDate);

      daily = {
        'oil': dayOil?.subtotal ?? 0,
        'stockMgmt': dayStockMgmt.fold<int>(0, (sum, s) => sum + s.subtotal),
        'remain': dayRemain.fold<int>(0, (sum, s) => sum + s.subtotal),
        'hutangPel': dHutangPel,
        'hutangPri': dayPersonal.fold<int>(0, (sum, l) => sum + l.amount),
        'saldo': daySaldo?.result ?? 0,
      };
    } else {
      daily = null;
    }

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
