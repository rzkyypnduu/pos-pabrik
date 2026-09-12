import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../constants/formatters.dart';

class TransactionProvider extends ChangeNotifier {
  final Map<int, double> _txQty = {};
  List<Sale> _daySales = [];
  List<SaleItem> _daySaleItems = [];
  List<Sale> _monthSales = [];
  List<SaleItem> _monthSaleItems = [];
  List<String> _customerNames = [];
  List<Sale> _searchResults = [];
  String _txName = '';
  String _txNote = '';
  String _txPaid = '';
  bool _txPaidTouched = false;
  int? _editingSaleId;
  bool _isPaymentFlow = false;

  List<Sale> get daySales => _daySales;
  List<SaleItem> get daySaleItems => _daySaleItems;
  List<Sale> get monthSales => _monthSales;
  List<SaleItem> get monthSaleItems => _monthSaleItems;
  List<String> get customerNames => _customerNames;
  List<Sale> get searchResults => _searchResults;
  Map<int, double> get txQty => _txQty;
  String get txName => _txName;
  String get txNote => _txNote;
  String get txPaid => _txPaid;
  bool get txPaidTouched => _txPaidTouched;
  int? get editingSaleId => _editingSaleId;
  bool get isPaymentFlow => _isPaymentFlow;

  int txRawTotal(List<Product> products) {
    int total = 0;
    for (final entry in _txQty.entries) {
      if (entry.value <= 0) continue;
      final product = products.where((p) => p.id == entry.key).firstOrNull;
      if (product != null) {
        total += (entry.value * product.price).round();
      }
    }
    return total;
  }

  int txRoundedTotal(List<Product> products) =>
      roundTotal(txRawTotal(products));

  int txDiff(List<Product> products) {
    final paid =
        int.tryParse(_txPaid.replaceAll('.', '').replaceAll(',', '')) ?? 0;
    return txRoundedTotal(products) - paid;
  }

  void setProductName(String name) {
    _txName = name;
    notifyListeners();
  }

  void setTxNote(String note) {
    _txNote = note;
    notifyListeners();
  }

  void setTxPaid(String paid) {
    _txPaid = paid;
    _txPaidTouched = true;
    notifyListeners();
  }

  void fillLunas(List<Product> products) {
    _txPaid = txRoundedTotal(products).toString();
    _txPaidTouched = true;
    notifyListeners();
  }

  void initQtyMap(List<Product> products) {
    for (final p in products) {
      if (!_txQty.containsKey(p.id)) {
        _txQty[p.id!] = 0;
      }
    }
    _txQty.removeWhere((key, _) => !products.any((p) => p.id == key));
    notifyListeners();
  }

  void incrementQty(int productId) {
    _txQty[productId] = (_txQty[productId] ?? 0) + 0.5;
    notifyListeners();
  }

  void decrementQty(int productId) {
    final current = _txQty[productId] ?? 0;
    _txQty[productId] = current > 0 ? current - 0.5 : 0;
    notifyListeners();
  }

  void setQty(int productId, double qty) {
    _txQty[productId] = qty;
    notifyListeners();
  }

  Future<void> loadDaySales(String date) async {
    _daySales = await DatabaseHelper.instance.getSalesByDate(date);
    _daySaleItems = await DatabaseHelper.instance.getSaleItemsByDate(date);
    notifyListeners();
  }

  Future<void> loadMonthSales(String startDate, String endDate) async {
    _monthSales = await DatabaseHelper.instance.getSalesByMonth(
      startDate,
      endDate,
    );
    _monthSaleItems = await DatabaseHelper.instance.getSaleItemsByMonth(
      startDate,
      endDate,
    );
    notifyListeners();
  }

  Future<void> loadCustomerNames() async {
    _customerNames = await DatabaseHelper.instance.getUniqueSaleNames();
    notifyListeners();
  }

  Future<void> searchSales(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
    } else {
      _searchResults = await DatabaseHelper.instance.searchSales(query);
    }
    notifyListeners();
  }

  List<SaleItem> getItemsForSale(int saleId) {
    return _daySaleItems.where((item) => item.saleId == saleId).toList();
  }

  Future<void> saveSale({
    required String date,
    required String name,
    required List<Product> products,
    required String note,
    required bool isEditing,
  }) async {
    final items = <Map<String, dynamic>>[];
    for (final entry in _txQty.entries) {
      if (entry.value > 0) {
        final product = products.where((p) => p.id == entry.key).firstOrNull;
        if (product != null) {
          items.add({'product': product, 'qty': entry.value});
        }
      }
    }

    if (name.isEmpty) return;

    final rawTotal = items.fold<int>(
      0,
      (sum, item) =>
          sum +
          ((item['qty'] as double) * (item['product'] as Product).price)
              .round(),
    );
    final paidStr = _txPaid.replaceAll('.', '').replaceAll(',', '');
    final paid = (_txPaidTouched && paidStr.isNotEmpty)
        ? (int.tryParse(paidStr) ?? 0)
        : 0;
    final hasItems = items.isNotEmpty;
    final roundedTotal = hasItems ? roundTotal(rawTotal) : paid;
    final diff = roundedTotal - paid;

    if (isEditing && _editingSaleId != null) {
      final existingSale = _daySales.firstWhere((s) => s.id == _editingSaleId);
      final sale = existingSale.copyWith(
        date: date,
        name: name,
        rawTotal: rawTotal,
        roundedTotal: roundedTotal,
        paid: paid,
        diff: diff,
        note: note.isNotEmpty ? note : null,
        isPaidBtnClicked: paid > 0,
        debtPaidAmount: 0,
      );
      await DatabaseHelper.instance.updateSale(sale);
      await DatabaseHelper.instance.deleteSaleItemsBySaleId(_editingSaleId!);

      for (final item in items) {
        final product = item['product'] as Product;
        await DatabaseHelper.instance.insertSaleItem(
          SaleItem(
            saleId: _editingSaleId!,
            productId: product.id,
            name: product.name,
            qty: item['qty'] as double,
            price: product.price,
          ),
        );
      }
    } else {
      final saleId = await DatabaseHelper.instance.insertSale(
        Sale(
          date: date,
          name: name,
          rawTotal: rawTotal,
          roundedTotal: roundedTotal,
          paid: paid,
          diff: diff,
          note: note.isNotEmpty ? note : null,
          isPaidBtnClicked: paid > 0,
        ),
      );

      for (final item in items) {
        final product = item['product'] as Product;
        await DatabaseHelper.instance.insertSaleItem(
          SaleItem(
            saleId: saleId,
            productId: product.id,
            name: product.name,
            qty: item['qty'] as double,
            price: product.price,
          ),
        );
      }
    }

    resetForm();
    await loadDaySales(date);
    await loadCustomerNames();
  }

  Future<void> payExact(int saleId, String date) async {
    final sale = _daySales.firstWhere((s) => s.id == saleId);
    final updated = sale.copyWith(
      paid: sale.roundedTotal,
      diff: 0,
      isPaidBtnClicked: true,
    );
    await DatabaseHelper.instance.updateSale(updated);

    await loadDaySales(date);
  }

  Future<void> payPartial(int saleId, int amount, String date) async {
    final sale = _daySales.firstWhere((s) => s.id == saleId);
    final newPaid = sale.paid + amount;
    final newDiff = sale.roundedTotal - newPaid;
    final updated = sale.copyWith(
      paid: newPaid,
      diff: newDiff,
      isPaidBtnClicked: true,
    );
    await DatabaseHelper.instance.updateSale(updated);

    await loadDaySales(date);
  }

  Future<void> payWithDebt(
    int saleId,
    int todayAmount,
    int prevAmount,
    String date,
  ) async {
    final sale = _daySales.firstWhere((s) => s.id == saleId);
    final newPaid = sale.paid + todayAmount + prevAmount;
    final newDebtAmount = sale.debtPaidAmount + prevAmount;
    final todayPaid = newPaid - newDebtAmount;
    final newDiff = sale.roundedTotal - todayPaid;
    final updated = sale.copyWith(
      paid: newPaid,
      diff: newDiff,
      debtPaidAmount: newDebtAmount,
      isPaidBtnClicked: true,
    );
    await DatabaseHelper.instance.updateSale(updated);

    await loadDaySales(date);
  }

  Future<void> toggleDebtPaid(int saleId, String date) async {
    final sale = _daySales.firstWhere((s) => s.id == saleId);
    await DatabaseHelper.instance.setSaleDebtPaid(saleId, !sale.debtPaid);
    await loadDaySales(date);
  }

  void loadSaleForPayment(Sale sale, List<Product> products) {
    _editingSaleId = sale.id;
    _isPaymentFlow = true;
    _txName = sale.name;
    _txNote = sale.note ?? '';
    _txPaid = '0';
    _txPaidTouched = true;

    for (final p in products) {
      _txQty[p.id!] = 0;
    }

    final saleItems = getItemsForSale(sale.id!);
    for (final item in saleItems) {
      if (item.productId != null) {
        _txQty[item.productId!] = item.qty;
      }
    }
    if (saleItems.isEmpty) {
      _txPaid = sale.paid.toString();
    }
    notifyListeners();
  }

  void resetForm() {
    _editingSaleId = null;
    _isPaymentFlow = false;
    _txName = '';
    _txNote = '';
    _txPaid = '';
    _txPaidTouched = false;
    final keys = List<int>.from(_txQty.keys);
    for (final key in keys) {
      _txQty[key] = 0;
    }
    notifyListeners();
  }

  Future<void> deleteSale(int saleId, String date) async {
    await DatabaseHelper.instance.deleteSale(saleId);
    await loadDaySales(date);
  }

  Map<String, double> recapPerProduct() {
    final recap = <String, double>{};
    for (final item in _daySaleItems) {
      recap[item.name] = (recap[item.name] ?? 0) + item.qty;
    }
    return recap;
  }

  Map<String, double> recapBulanPerProduct() {
    final recap = <String, double>{};
    for (final item in _monthSaleItems) {
      recap[item.name] = (recap[item.name] ?? 0) + item.qty;
    }
    final sortedKeys = recap.keys.toList()..sort();
    return {for (final k in sortedKeys) k: recap[k]!};
  }

  double recapTotalKg() =>
      _daySaleItems.fold<double>(0, (sum, item) => sum + item.qty);

  int recapTotalPaid() => _daySales.fold<int>(0, (sum, s) => sum + s.paid);

  double recapBulanTotalKg() =>
      _monthSaleItems.fold<double>(0, (sum, item) => sum + item.qty);

  int recapBulanTotalPaid() =>
      _monthSales.fold<int>(0, (sum, s) => sum + s.paid);
}
