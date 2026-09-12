import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../constants/formatters.dart';
import '../database/database_helper.dart';
import '../models/sale.dart';
import '../providers/tab_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/product_provider.dart';
import '../providers/customer_ledger_provider.dart';
import '../providers/printer_provider.dart';
import '../services/printer_service.dart';
import '../widgets/recap_panel.dart';
import '../widgets/confirmation_dialog.dart';
import 'transaksi_form_screen.dart';

class TransaksiTab extends StatefulWidget {
  const TransaksiTab({super.key});

  @override
  State<TransaksiTab> createState() => _TransaksiTabState();
}

class _TransaksiTabState extends State<TransaksiTab> {
  final _expenseAmountController = TextEditingController();
  final _expenseNoteController = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _expenseAmountController.dispose();
    _expenseNoteController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadData() {
    final tabProv = context.read<TabProvider>();
    final txProv = context.read<TransactionProvider>();
    final expProv = context.read<ExpenseProvider>();
    final prodProv = context.read<ProductProvider>();
    context.read<CustomerLedgerProvider>().loadAll();

    txProv.loadDaySales(tabProv.selectedDate);
    txProv.initQtyMap(prodProv.products);
    expProv.loadDayExpenses(tabProv.selectedDate);
    _loadMonth(txProv, expProv, tabProv.selectedDate);
  }

  void _loadDate(String date) {
    final tabProv = context.read<TabProvider>();
    tabProv.setSelectedDate(date);
    final txProv = context.read<TransactionProvider>();
    final expProv = context.read<ExpenseProvider>();
    txProv.loadDaySales(date);
    expProv.loadDayExpenses(date);
    _loadMonth(txProv, expProv, date);
  }

  void _loadMonth(
    TransactionProvider txProv,
    ExpenseProvider expProv,
    String date,
  ) {
    final month = date.length >= 7 ? date.substring(0, 7) : date;
    final range = monthRange(month);
    txProv.loadMonthSales(range[0], range[1]);
    expProv.loadMonthExpenses(range[0], range[1]);
  }

  Widget _buildSearchCard(BuildContext context) {
    final txProv = context.watch<TransactionProvider>();
    final tabProv = context.read<TabProvider>();
    final prodProv = context.read<ProductProvider>();
    final results = txProv.searchResults;
    final q = _searchQuery.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cari Transaksi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                setState(() => _searchQuery = v);
                txProv.searchSales(v);
              },
              decoration: InputDecoration(
                hintText: 'Ketik nama pelanggan...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (q.isNotEmpty) ...[
              const SizedBox(height: 4),
              results.isEmpty
                  ? const Text(
                      'Tidak ada transaksi ditemukan.',
                      style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                    )
                  : Column(
                      children: [
                        for (final sale in results)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                txProv.loadSaleForPayment(
                                  sale,
                                  prodProv.products,
                                );
                                final result = await Navigator.of(context).push<
                                    bool>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ChangeNotifierProvider.value(
                                      value: txProv,
                                      child: TransaksiFormScreen(
                                        selectedDate:
                                            tabProv.selectedDate,
                                      ),
                                    ),
                                  ),
                                );
                                if (result == true) _loadData();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.receipt_long,
                                      size: 18,
                                      color: AppTheme.accent,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sale.name,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            sale.date,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.inkSoft,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      rupiah(sale.rawTotal),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final tabProv = context.watch<TabProvider>();
    final txProv = context.watch<TransactionProvider>();
    final expProv = context.watch<ExpenseProvider>();
    final prodProv = context.watch<ProductProvider>();
    final isToday = tabProv.selectedDate == todayString();
    final isMobile = AppTheme.isMobile(context);

    final recapPerProduct = txProv.recapPerProduct();
    final totalKg = txProv.recapTotalKg();
    final totalPaid = txProv.recapTotalPaid();
    final expenseTotal = expProv.dayExpenseTotal;
    final kasBersih = totalPaid - expenseTotal;

    return Column(
      children: [
        // Date selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Builder(
            builder: (context) {
              final datePill = InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.parse(tabProv.selectedDate),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    final dateStr =
                        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    _loadDate(dateStr);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          fmtDateLong(tabProv.selectedDate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: AppTheme.accent,
                      ),
                    ],
                  ),
                ),
              );
              final title = Text(
                isToday ? 'Transaksi Hari Ini' : 'Transaksi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              );
              final newTxButton = ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: txProv,
                        child: TransaksiFormScreen(
                          selectedDate: tabProv.selectedDate,
                        ),
                      ),
                    ),
                  );
                  if (result == true) _loadData();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Transaksi Baru'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(fontSize: 14),
                ),
              );

              if (AppTheme.isCompact(context)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(child: title),
                        const SizedBox(width: 12),
                        Flexible(child: datePill),
                      ],
                    ),
                    const SizedBox(height: 10),
                    newTxButton,
                  ],
                );
              }
              return Row(
                children: [
                  title,
                  const SizedBox(width: 12),
                  datePill,
                  const Spacer(),
                  newTxButton,
                ],
              );
            },
          ),
        ),

        // Content
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Transaction Table
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: txProv.daySales.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text(
                              'Belum ada transaksi ${isToday ? "hari ini" : "tanggal ${fmtDate(tabProv.selectedDate)}"}.',
                              style: const TextStyle(
                                color: AppTheme.inkSoft,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : isMobile
                      ? Column(
                          children: [
                            ...txProv.daySales.map((sale) {
                              final items = txProv.getItemsForSale(sale.id!);
                              return _buildMobileSaleCard(sale, items, tabProv);
                            }),
                          ],
                        )
                      : Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.ink.withValues(alpha: 0.05),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Nama',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Produk',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      'Kg',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Tagihan',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Dibayar',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Sisa',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Text(
                                      'Aksi',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...txProv.daySales.map((sale) {
                              final items = txProv.getItemsForSale(sale.id!);
                              final statusBadge = _buildStatusBadge(
                                sale,
                                noItems: items.isEmpty,
                              );
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppTheme.line,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        sale.name,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: items
                                            .map(
                                              (item) => Text(
                                                '${item.name}: ${fmtKg(item.qty)} kg',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  height: 1.2,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        fmtKg(
                                          items.fold<double>(
                                            0,
                                            (s, i) => s + i.qty,
                                          ),
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        rupiah(sale.roundedTotal),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        rupiah(sale.paid),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Center(child: statusBadge),
                                    ),
                                    Expanded(
                                      flex: 5,
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        alignment: WrapAlignment.center,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          _filledBtn(
                                            'Bayar',
                                            sale.diff > 0 &&
                                                !sale.isPaidBtnClicked,
                                            () => _showPayDialog(sale),
                                          ),
                                          _toggleBtn(
                                            'Kemarin',
                                            sale.debtPaid,
                                            () => txProv.toggleDebtPaid(
                                              sale.id!,
                                              tabProv.selectedDate,
                                            ),
                                          ),
                                          _actionBtn(
                                            'Edit',
                                            AppTheme.accent,
                                            () async {
                                              txProv.loadSaleForPayment(
                                                sale,
                                                prodProv.products,
                                              );
                                              final result =
                                                  await Navigator.of(
                                                    context,
                                                  ).push<bool>(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          ChangeNotifierProvider.value(
                                                            value: txProv,
                                                            child: TransaksiFormScreen(
                                                              selectedDate: tabProv
                                                                  .selectedDate,
                                                            ),
                                                          ),
                                                    ),
                                                  );
                                              if (result == true) _loadData();
                                            },
                                          ),
                                          _actionBtn(
                                            'Hapus',
                                            AppTheme.debt,
                                            () => ConfirmationDialog.show(
                                              context: context,
                                              title: 'Hapus Transaksi',
                                              message:
                                                  'Hapus transaksi ${sale.name}?',
                                              isDestructive: true,
                                              onConfirm: () =>
                                                  txProv.deleteSale(
                                                    sale.id!,
                                                    tabProv.selectedDate,
                                                  ),
                                            ),
                                          ),
                                          _actionBtn(
                                            'Print',
                                            AppTheme.paid,
                                            () => _printSaleReceipt(
                                              context,
                                              sale,
                                              items,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                if (isMobile) ...[
                  const SizedBox(height: 16),
                  _buildSearchCard(context),
                ],

                // Expense
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pengeluaran Laci',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (isMobile)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _expenseAmountController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [RupiahInputFormatter()],
                                decoration: const InputDecoration(
                                  labelText: 'Jumlah (Rp)',
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _expenseNoteController,
                                decoration: const InputDecoration(
                                  labelText: 'Keperluan',
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () async {
                                  final amountStr = _expenseAmountController
                                      .text
                                      .replaceAll('.', '')
                                      .replaceAll(',', '');
                                  final amount = int.tryParse(amountStr) ?? 0;
                                  if (amount > 0) {
                                    await expProv.addExpense(
                                      tabProv.selectedDate,
                                      amount,
                                      _expenseNoteController.text,
                                    );
                                    _expenseAmountController.clear();
                                    _expenseNoteController.clear();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text(
                                  'Simpan',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _expenseAmountController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [RupiahInputFormatter()],
                                  decoration: const InputDecoration(
                                    labelText: 'Jumlah (Rp)',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _expenseNoteController,
                                  decoration: const InputDecoration(
                                    labelText: 'Keperluan',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () async {
                                  final amountStr = _expenseAmountController
                                      .text
                                      .replaceAll('.', '')
                                      .replaceAll(',', '');
                                  final amount = int.tryParse(amountStr) ?? 0;
                                  if (amount > 0) {
                                    await expProv.addExpense(
                                      tabProv.selectedDate,
                                      amount,
                                      _expenseNoteController.text,
                                    );
                                    _expenseAmountController.clear();
                                    _expenseNoteController.clear();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text(
                                  'Simpan',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        if (expProv.dayExpenses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              'Belum ada pengeluaran.',
                              style: TextStyle(
                                color: AppTheme.inkSoft,
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          ...expProv.dayExpenses.map(
                            (e) => Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: AppTheme.line,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: ListTile(
                                title: Text(
                                  e.note ?? '-',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      rupiah(e.amount),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: AppTheme.debt,
                                      ),
                                      onPressed: () => expProv.deleteExpense(
                                        e.id!,
                                        tabProv.selectedDate,
                                      ),
                                    ),
                                  ],
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Rekap Hari Ini
                RecapPanel(
                  title: isToday
                      ? 'Rekap Hari Ini'
                      : 'Rekap ${fmtDate(tabProv.selectedDate)}',
                  initiallyExpanded: true,
                  child: Column(
                    children: [
                      if (recapPerProduct.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: Text(
                            'Belum ada penjualan.',
                            style: TextStyle(color: AppTheme.inkSoft),
                          ),
                        )
                      else
                        ...recapPerProduct.entries.map(
                          (e) => _recapRow(e.key, '${fmtKg(e.value)} kg'),
                        ),
                      const Divider(height: 24),
                      _recapRow('Total', '${fmtKg(totalKg)} kg', bold: true),
                      const SizedBox(height: 6),
                      _recapRow(
                        'Diterima',
                        rupiah(totalPaid),
                        bold: true,
                        valueColor: AppTheme.paid,
                      ),
                      _recapRow(
                        'Pengeluaran',
                        '-${rupiah(expenseTotal)}',
                        bold: true,
                        valueColor: AppTheme.debt,
                      ),
                      _recapRow(
                        'Kas bersih',
                        rupiah(kasBersih),
                        bold: true,
                        valueColor: AppTheme.paid,
                      ),
                    ],
                  ),
                ),

                // Rekap Bulan
                RecapPanel(
                  title:
                      'Rekap ${monthLabel(tabProv.selectedDate.substring(0, 7))}',
                  initiallyExpanded: true,
                  child: Column(
                    children: [
                      ...txProv.recapBulanPerProduct().entries.map(
                        (e) => _recapRow(e.key, '${fmtKg(e.value)} kg'),
                      ),
                      const Divider(height: 24),
                      _recapRow(
                        'Total',
                        '${fmtKg(txProv.recapBulanTotalKg())} kg',
                        bold: true,
                      ),
                      const SizedBox(height: 6),
                      _recapRow(
                        'Diterima',
                        rupiah(txProv.recapBulanTotalPaid()),
                        bold: true,
                        valueColor: AppTheme.paid,
                      ),
                      _recapRow(
                        'Pengeluaran',
                        '-${rupiah(expProv.monthExpenseTotal)}',
                        bold: true,
                        valueColor: AppTheme.debt,
                      ),
                      _recapRow(
                        'Kas bersih',
                        rupiah(
                          txProv.recapBulanTotalPaid() -
                              expProv.monthExpenseTotal,
                        ),
                        bold: true,
                        valueColor: AppTheme.paid,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showPayDialog(Sale sale) {
    showDialog(
      context: context,
      builder: (ctx) => _PayDialog(
        sale: sale,
        selectedDate: context.read<TabProvider>().selectedDate,
        onPaid: () {
          Navigator.of(ctx).pop();
          _loadData();
        },
      ),
    );
  }

  Future<void> _printSaleReceipt(
    BuildContext context,
    Sale sale,
    List<dynamic> items,
  ) async {
    final printerProv = context.read<PrinterProvider>();
    if (!printerProv.isConnected) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Printer belum terhubung. Silakan hubungkan di Pengaturan.',
          ),
          backgroundColor: AppTheme.debt,
        ),
      );
      return;
    }
    final receiptItems = items
        .map(
          (item) => ReceiptItem(
            name: item.name,
            detail:
                '${fmtKg(item.qty)} kg x ${rupiahPlain(item.price.toInt())}',
            subtotal: rupiahPlain(item.subtotal.toInt()),
          ),
        )
        .toList();
    final isCashOnly = items.isEmpty;
    final isOverpaid = sale.diff < 0;
    final result = await printerProv.printReceipt(
      items: receiptItems,
      totalText: isCashOnly ? rupiahPlain(0) : rupiahPlain(sale.roundedTotal),
      paidText: rupiahPlain(sale.paid),
      changeText: isCashOnly
          ? rupiahPlain(sale.paid)
          : sale.diff > 0
          ? 'Kurang ${rupiahPlain(sale.diff)}'
          : rupiahPlain(-sale.diff),
      changeLabel: (isCashOnly || isOverpaid) ? 'BAYAR HUTANG' : 'KEMBALI',
      customerName: sale.name,
      timestamp:
          DateTime.tryParse(sale.createdAt ?? '') ??
          DateTime.tryParse(sale.date),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result ? 'Struk ${sale.name} tercetak' : 'Gagal cetak struk',
        ),
        backgroundColor: result ? AppTheme.paid : AppTheme.debt,
      ),
    );
  }

  Widget _buildStatusBadge(Sale sale, {bool noItems = false}) {
    final diff = sale.diff;
    Color bgColor, textColor;
    String text;

    if (noItems) {
      bgColor = AppTheme.paidBg;
      textColor = AppTheme.paid;
      text = 'Lebih ${rupiah(sale.paid)}';
    } else if (diff > 0) {
      bgColor = AppTheme.debtBg;
      textColor = AppTheme.debt;
      text = 'Kurang ${rupiah(diff)}';
    } else if (diff < 0) {
      bgColor = AppTheme.paidBg;
      textColor = AppTheme.paid;
      text = 'Lebih ${rupiah(-diff)}';
    } else {
      bgColor = AppTheme.lunasBg;
      textColor = AppTheme.lunas;
      text = 'Lunas';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        if (sale.debtPaid) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.paidBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 12, color: AppTheme.paid),
                const SizedBox(width: 3),
                Text(
                  'Bayar Kemarin',
                  style: TextStyle(
                    color: AppTheme.paid,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _filledBtn(String label, bool enabled, VoidCallback onPressed) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.paid,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onPressed) {
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: active ? AppTheme.paid : AppTheme.inkSoft,
          backgroundColor: active ? AppTheme.paidBg : null,
          side: BorderSide(
            color: active
                ? AppTheme.paid
                : AppTheme.inkSoft.withValues(alpha: 0.3),
            width: 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        icon: Icon(
          active ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 13,
        ),
        label: Text(label),
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4), width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildMobileSaleCard(
    Sale sale,
    List<dynamic> items,
    TabProvider tabProv,
  ) {
    final statusBadge = _buildStatusBadge(sale, noItems: items.isEmpty);
    final totalKg = items.fold<double>(0, (s, i) => s + i.qty);
    final txProv = context.read<TransactionProvider>();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.line, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  sale.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: statusBadge),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• ${item.name}: ${fmtKg(item.qty)} kg',
                style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _mobileInfoBox('KG', '${fmtKg(totalKg)} kg')),
              const SizedBox(width: 8),
              Expanded(
                child: _mobileInfoBox('TAGIHAN', rupiah(sale.roundedTotal)),
              ),
              const SizedBox(width: 8),
              Expanded(child: _mobileInfoBox('DIBAYAR', rupiah(sale.paid))),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filledBtn(
                'Bayar',
                sale.diff > 0 && !sale.isPaidBtnClicked,
                () => _showPayDialog(sale),
              ),
              _toggleBtn(
                'Kemarin',
                sale.debtPaid,
                () => txProv.toggleDebtPaid(sale.id!, tabProv.selectedDate),
              ),
              _actionBtn('Edit', AppTheme.accent, () async {
                txProv.loadSaleForPayment(
                  sale,
                  context.read<ProductProvider>().products,
                );
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: txProv,
                      child: TransaksiFormScreen(
                        selectedDate: tabProv.selectedDate,
                      ),
                    ),
                  ),
                );
                if (result == true) _loadData();
              }),
              _actionBtn(
                'Print',
                AppTheme.paid,
                () => _printSaleReceipt(context, sale, items),
              ),
              _actionBtn(
                'Hapus',
                AppTheme.debt,
                () => ConfirmationDialog.show(
                  context: context,
                  title: 'Hapus Transaksi',
                  message: 'Hapus transaksi ${sale.name}?',
                  isDestructive: true,
                  onConfirm: () =>
                      txProv.deleteSale(sale.id!, tabProv.selectedDate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mobileInfoBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkSoft,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recapRow(
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'monospace',
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayDialog extends StatefulWidget {
  final Sale sale;
  final String selectedDate;
  final VoidCallback onPaid;

  const _PayDialog({
    required this.sale,
    required this.selectedDate,
    required this.onPaid,
  });

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late TextEditingController _controller;
  int _enteredAmount = 0;
  late TextEditingController _controllerPrev;
  int _enteredAmountPrev = 0;
  late TextEditingController _controllerSecond;
  int _enteredAmountSecond = 0;
  bool _showSecond = false;
  Sale? _prevSale;

  bool get _showDual => widget.sale.debtPaid;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.sale.paid.toString());
    _enteredAmount = widget.sale.paid;
    _controllerPrev = TextEditingController();
    _controllerSecond = TextEditingController();
    if (widget.sale.debtPaid) {
      _loadPrevSale();
    }
  }

  Future<void> _loadPrevSale() async {
    final prev = await DatabaseHelper.instance.getPreviousUnpaidSale(
      widget.sale.name,
      widget.sale.date,
    );
    if (mounted) {
      setState(() {
        _prevSale = prev;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _controllerPrev.dispose();
    _controllerSecond.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final remaining = sale.diff;
    final showDual = _showDual;
    final todayPaid = sale.paid - sale.debtPaidAmount;
    final todayRemaining = sale.roundedTotal - todayPaid - _enteredAmount;

    return AlertDialog(
      title: Text('Bayar: ${sale.name}'),
      insetPadding: const EdgeInsets.all(24),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tagihan hari ini: ${rupiah(sale.roundedTotal)}',
                style: const TextStyle(fontSize: 15),
              ),
              if (showDual) ...[
                const SizedBox(height: 12),
                if (_prevSale == null)
                  const Text(
                    'Tidak ada transaksi sebelumnya.',
                    style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                  )
                else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.debtBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transaksi sebelumnya (${_prevSale!.date}): '
                          '${rupiah(_prevSale!.roundedTotal)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sisa kurang: ${rupiah(_prevSale!.diff)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.debt,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Bayar Transaksi Sebelumnya (Rp):',
                  style: const TextStyle(fontSize: 14),
                ),
                TextField(
                  controller: _controllerPrev,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(hintText: '0'),
                  onChanged: (val) {
                    final parsed = parseRupiah(val);
                    setState(() => _enteredAmountPrev = parsed);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Bayar Hari Ini (Rp):',
                  style: const TextStyle(fontSize: 14),
                ),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(hintText: '0'),
                  onChanged: (val) {
                    final parsed = parseRupiah(val);
                    setState(() => _enteredAmount = parsed);
                  },
                ),
              ] else if (remaining > 0) ...[
                Text(
                  'Sisa kurang: ${rupiah(remaining)}',
                  style: const TextStyle(fontSize: 14, color: AppTheme.debt),
                ),
                const SizedBox(height: 16),
              ] else if (remaining < 0) ...[
                Text(
                  'Lebih bayar: ${rupiah(-remaining)}',
                  style: const TextStyle(fontSize: 14, color: AppTheme.paid),
                ),
                const SizedBox(height: 16),
              ] else ...[
                const SizedBox(height: 16),
              ],
              if (!showDual) ...[
                Text(
                  'Jumlah Bayar (Rp):',
                  style: const TextStyle(fontSize: 14),
                ),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(hintText: '0'),
                  onChanged: (val) {
                    final parsed = parseRupiah(val);
                    setState(() => _enteredAmount = parsed);
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showSecond = !_showSecond),
                    icon: Icon(
                      _showSecond
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      size: 18,
                    ),
                    label: Text(
                      _showSecond ? 'Hapus Bayar Ke-2' : 'Tambah Bayar Ke-2',
                    ),
                  ),
                ),
                if (_showSecond) ...[
                  Text(
                    'Bayar Ke-2 (Rp):',
                    style: const TextStyle(fontSize: 14),
                  ),
                  TextField(
                    controller: _controllerSecond,
                    keyboardType: TextInputType.number,
                    inputFormatters: [RupiahInputFormatter()],
                    decoration: const InputDecoration(hintText: '0'),
                    onChanged: (val) {
                      final parsed = parseRupiah(val);
                      setState(() => _enteredAmountSecond = parsed);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _buildSummaryText(
                      sale.roundedTotal,
                      _enteredAmount + _enteredAmountSecond,
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _summaryColor(
                        sale.roundedTotal,
                        _enteredAmount + _enteredAmountSecond,
                      ),
                    ),
                  ),
                ],
              ],
              if (showDual) ...[
                const SizedBox(height: 8),
                if (todayRemaining > 0)
                  Text(
                    'Sisa hari ini: ${rupiah(todayRemaining)}',
                    style: const TextStyle(fontSize: 14, color: AppTheme.debt),
                  ),
                if (todayRemaining < 0)
                  Text(
                    'Lebih hari ini: ${rupiah(-todayRemaining)}',
                    style: const TextStyle(fontSize: 14, color: AppTheme.paid),
                  ),
                if (todayRemaining == 0)
                  Text(
                    'Lunas',
                    style: const TextStyle(fontSize: 14, color: AppTheme.paid),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        OutlinedButton(
          onPressed: () async {
            final txProvider = context.read<TransactionProvider>();
            if (showDual) {
              final todayPay =
                  sale.roundedTotal - (sale.paid - sale.debtPaidAmount);
              await txProvider.payWithDebt(
                sale.id!,
                todayPay,
                _enteredAmountPrev,
                widget.selectedDate,
              );
            } else {
              await txProvider.payExact(sale.id!, widget.selectedDate);
            }
            widget.onPaid();
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: AppTheme.paid,
            foregroundColor: Colors.white,
            side: const BorderSide(color: AppTheme.paid, width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Text(
            'Lunas',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            final txProvider = context.read<TransactionProvider>();
            if (showDual) {
              await txProvider.payWithDebt(
                sale.id!,
                _enteredAmount,
                _enteredAmountPrev,
                widget.selectedDate,
              );
            } else {
              final totalPay = _enteredAmount + _enteredAmountSecond;
              final delta = totalPay - sale.paid;
              await txProvider.payPartial(sale.id!, delta, widget.selectedDate);
            }
            widget.onPaid();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.paid,
            foregroundColor: Colors.white,
          ),
          child: const Text('Bayar'),
        ),
      ],
    );
  }

  String _buildSummaryText(int roundedTotal, int totalPay) {
    final selisih = roundedTotal - totalPay;
    if (selisih > 0) return 'Sisa kurang: ${rupiah(selisih)}';
    if (selisih < 0) return 'Lebih bayar: ${rupiah(-selisih)}';
    return 'Lunas';
  }

  Color _summaryColor(int roundedTotal, int totalPay) {
    final selisih = roundedTotal - totalPay;
    if (selisih > 0) return AppTheme.debt;
    if (selisih < 0) return AppTheme.paid;
    return AppTheme.paid;
  }
}
