import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/customer_ledger.dart';

class CustomerLedgerProvider extends ChangeNotifier {
  List<CustomerLedger> _allLedgers = [];

  List<CustomerLedger> get allLedgers => _allLedgers;

  Map<String, int> _balances = {};
  Map<String, int> get balances => _balances;

  List<String> _namesWithDebt = [];
  List<String> get namesWithDebt => _namesWithDebt;

  String? _selectedName;
  String? get selectedName => _selectedName;

  void setSelectedName(String? name) {
    _selectedName = name;
    notifyListeners();
  }

  Future<void> loadAll() async {
    _allLedgers = await DatabaseHelper.instance.getAllCustomerLedgers();
    _balances = {};
    for (final entry in _allLedgers) {
      final current = _balances[entry.name] ?? 0;
      _balances[entry.name] = current + (entry.type == 'tambah' ? entry.amount : -entry.amount);
    }
    _namesWithDebt = _balances.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toList()
      ..sort();
    notifyListeners();
  }

  int balanceFor(String name) => _balances[name] ?? 0;

  List<CustomerLedger> ledgersForName(String name) {
    return _allLedgers.where((l) => l.name == name).toList();
  }

  List<String> allCustomerNames() {
    return _allLedgers.map((l) => l.name).toSet().toList()..sort();
  }

  // FIFO debt processing
  Map<String, dynamic> processCustomerDebts(String name) {
    final entries = _allLedgers.where((l) => l.name == name).toList()
      ..sort((a, b) {
        final dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
        return (a.id ?? 0).compareTo(b.id ?? 0);
      });

    final debts = <Map<String, dynamic>>[];
    double deposit = 0;

    for (final l in entries) {
      if (l.type == 'tambah') {
        debts.add({
          'id': l.id,
          'amount': l.amount.toDouble(),
          'remaining': l.amount.toDouble(),
          'date': l.date,
        });
      } else {
        double payment = l.amount.toDouble();
        for (int i = 0; i < debts.length && payment > 0; i++) {
          final remaining = debts[i]['remaining'] as double;
          final cut = payment < remaining ? payment : remaining;
          debts[i]['remaining'] = remaining - cut;
          payment -= cut;
        }
        if (payment > 0) {
          deposit += payment;
        }
      }
    }

    final activeDebts = debts.where((d) => (d['remaining'] as double) > 0).toList();
    final totalSisa = activeDebts.fold<double>(0, (sum, d) => sum + (d['remaining'] as double));

    return {
      'activeDebts': activeDebts,
      'totalSisa': totalSisa.round(),
      'deposit': deposit.round(),
    };
  }

  Map<String, dynamic> debtDetailWithRunningBalance(String name) {
    final entries = ledgersForName(name);
    int running = 0;
    final result = <Map<String, dynamic>>[];

    for (final l in entries) {
      running += l.type == 'tambah' ? l.amount : -l.amount;
      result.add({
        'id': l.id,
        'date': l.date,
        'type': l.type,
        'amount': l.amount,
        'running': running,
        'note': l.note,
        'saleId': l.saleId,
      });
    }

    return {'entries': result, 'finalBalance': running};
  }

  Future<void> addDebt(String date, String name, int amount, String note) async {
    await DatabaseHelper.instance.insertCustomerLedger(CustomerLedger(
      date: date,
      name: name,
      amount: amount,
      type: 'tambah',
      note: note.isNotEmpty ? note : 'Tambah hutang manual',
    ));
    await loadAll();
  }

  Future<void> adjustDebtCell(int debtId, int newRemaining) async {
    final entry = _allLedgers.firstWhere((l) => l.id == debtId);
    await DatabaseHelper.instance.updateCustomerLedger(
      entry.copyWith(amount: newRemaining.clamp(0, 999999999)),
    );
    await loadAll();
  }

  Future<void> adjustTotalDebt(String name, int newTotal) async {
    final current = balanceFor(name);
    final diff = newTotal - current;
    if (diff != 0) {
      await DatabaseHelper.instance.insertCustomerLedger(CustomerLedger(
        date: DateTime.now().toIso8601String().substring(0, 10),
        name: name,
        amount: diff.abs(),
        type: diff > 0 ? 'tambah' : 'bayar',
        note: 'Penyesuaian manual saldo hutang',
      ));
    }
    await loadAll();
  }

  Future<void> deleteLedgerEntry(int id) async {
    await DatabaseHelper.instance.deleteCustomerLedger(id);
    await loadAll();
  }

  Future<void> deleteCustomerLedger(String name) async {
    await DatabaseHelper.instance.deleteCustomerLedgerByName(name);
    await loadAll();
  }
}
