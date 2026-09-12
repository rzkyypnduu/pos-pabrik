import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../constants/formatters.dart';
import '../providers/tab_provider.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import '../providers/customer_ledger_provider.dart';
import '../providers/oil_stock_provider.dart';
import '../providers/ringkasan_provider.dart';
import '../providers/stock_management_provider.dart';
import '../models/stock_management.dart';
import '../providers/stock_remaining_provider.dart';
import '../models/stock_remaining.dart';
import '../providers/personal_ledger_provider.dart';
import '../models/personal_ledger.dart';
import '../providers/saldo_deduction_provider.dart';
import '../providers/customer_daily_balance_provider.dart';
import '../models/customer_daily_balance.dart';
import '../providers/printer_provider.dart';
import '../services/printer_service.dart';
import '../widgets/confirmation_dialog.dart';

class HasilTab extends StatefulWidget {
  const HasilTab({super.key});

  @override
  State<HasilTab> createState() => _HasilTabState();
}

class _HasilTabState extends State<HasilTab> {
  bool _loaded = false;
  bool _isLoading = false;
  String _lastLoadedDate = '';
  int _lastTab = -1;

  // Shared controllers for live form values
  final oilQtyController = TextEditingController();
  final oilPriceController = TextEditingController();
  final saldoAController = TextEditingController();
  final saldoBController = TextEditingController();

  // Track which controller has focus to avoid overwriting user input
  final _oilQtyFocusNode = FocusNode();
  final _oilPriceFocusNode = FocusNode();
  final _saldoAFocusNode = FocusNode();
  final _saldoBFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _oilQtyFocusNode.addListener(() => setState(() {}));
    _oilPriceFocusNode.addListener(() => setState(() {}));
    _saldoAFocusNode.addListener(() => setState(() {}));
    _saldoBFocusNode.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabProv = context.read<TabProvider>();
    if (tabProv.currentTab == 2 && _lastTab != 2) {
      _lastTab = 2;
      _lastLoadedDate = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
    } else {
      _lastTab = tabProv.currentTab;
    }
    if (!_loaded) {
      _loaded = true;
    }
  }

  @override
  void dispose() {
    _oilQtyFocusNode.dispose();
    _oilPriceFocusNode.dispose();
    _saldoAFocusNode.dispose();
    _saldoBFocusNode.dispose();
    oilQtyController.dispose();
    oilPriceController.dispose();
    saldoAController.dispose();
    saldoBController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted || _isLoading) return;
    final tabProv = context.read<TabProvider>();
    if (_lastLoadedDate == tabProv.selectedDate) return;
    _isLoading = true;
    _lastLoadedDate = tabProv.selectedDate;

    final ledgerProv = context.read<CustomerLedgerProvider>();
    final oilProv = context.read<OilStockProvider>();
    final smProv = context.read<StockManagementProvider>();
    final srProv = context.read<StockRemainingProvider>();
    final plProv = context.read<PersonalLedgerProvider>();
    final sdProv = context.read<SaldoDeductionProvider>();
    final cdbProv = context.read<CustomerDailyBalanceProvider>();
    final ringProv = context.read<RingkasanProvider>();

    await ledgerProv.loadAll();
    if (!mounted) return;

    await Future.wait([
      oilProv.loadMonthStocks(tabProv.activeMonth),
      smProv.loadMonthStocks(tabProv.activeMonth),
      srProv.loadMonthStocks(tabProv.activeMonth),
      plProv.loadMonth(tabProv.activeMonth),
      sdProv.loadMonth(tabProv.activeMonth),
      cdbProv.loadMonth(tabProv.activeMonth),
    ]);
    if (!mounted) return;

    await Future.wait([
      oilProv.loadForDate(tabProv.selectedDate),
      smProv.loadForDate(tabProv.selectedDate),
      srProv.loadForDate(tabProv.selectedDate),
      plProv.loadForDate(tabProv.selectedDate),
      sdProv.loadForDate(tabProv.selectedDate),
      cdbProv.loadForDate(tabProv.selectedDate),
    ]);
    if (!mounted) return;

    if (oilProv.currentDateStock != null) {
      if (!_oilQtyFocusNode.hasFocus) {
        oilQtyController.text = oilProv.currentDateStock!.qty > 0
            ? rupiahInputText(oilProv.currentDateStock!.qty)
            : '';
      }
      if (!_oilPriceFocusNode.hasFocus) {
        oilPriceController.text = oilProv.currentDateStock!.price > 0
            ? rupiahInputText(oilProv.currentDateStock!.price)
            : '';
      }
    } else {
      if (!_oilQtyFocusNode.hasFocus) oilQtyController.clear();
      if (!_oilPriceFocusNode.hasFocus) oilPriceController.clear();
    }

    if (sdProv.currentDateLog != null) {
      if (!_saldoAFocusNode.hasFocus) {
        saldoAController.text = sdProv.currentDateLog!.a > 0
            ? rupiahInputText(sdProv.currentDateLog!.a)
            : '';
      }
      if (!_saldoBFocusNode.hasFocus) {
        saldoBController.text = sdProv.currentDateLog!.b > 0
            ? rupiahInputText(sdProv.currentDateLog!.b)
            : '';
      }
    } else {
      if (!_saldoAFocusNode.hasFocus) saldoAController.clear();
      if (!_saldoBFocusNode.hasFocus) saldoBController.clear();
    }

    await ringProv.calculate(
      activeMonth: tabProv.activeMonth,
      selectedDate: tabProv.selectedDate,
      customerBalances: ledgerProv.balances,
    );
    _isLoading = false;
    if (mounted) setState(() {});
  }

  void _loadDate(String date) {
    final tabProv = context.read<TabProvider>();
    tabProv.setSelectedDate(date);
    _lastLoadedDate = '';
    _loadData();
  }

  void _refreshData() {
    _lastLoadedDate = '';
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final tabProv = context.watch<TabProvider>();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Text(
                'Hasil',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              InkWell(
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
                    horizontal: 12,
                    vertical: 8,
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
                      Text(
                        fmtDateLong(tabProv.selectedDate),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
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
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppTheme.isMobile(context) ? 8 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  '1. Rekap Hutang Pelanggan', ''
                ),
                _HutangPelangganSection(onSaved: _refreshData),
                const SizedBox(height: 16),

                _sectionHeader('2. Stok Barang', ''),
                _StokMinyakSection(
                  qtyController: oilQtyController,
                  priceController: oilPriceController,
                  onSaved: _refreshData,
                  qtyFocusNode: _oilQtyFocusNode,
                  priceFocusNode: _oilPriceFocusNode,
                ),
                const SizedBox(height: 10),
                _ManajemenStokSection(onSaved: _refreshData),
                const SizedBox(height: 10),
                _SisaBarangSection(onSaved: _refreshData),
                const SizedBox(height: 16),

                _sectionHeader('3. Hutang Pribadi', ''),
                _HutangPribadiSection(onSaved: _refreshData),
                const SizedBox(height: 16),

                _sectionHeader('4. Pengurangan Saldo', ''),
                _SaldoDeductionSection(
                  aController: saldoAController,
                  bController: saldoBController,
                  onSaved: _refreshData,
                  aFocusNode: _saldoAFocusNode,
                  bFocusNode: _saldoBFocusNode,
                ),
                const SizedBox(height: 16),

                _sectionHeader(
                  '5. Rincian Harian',
                  '',
                ),
                _RincianHarianSection(
                  oilQtyController: oilQtyController,
                  oilPriceController: oilPriceController,
                  saldoAController: saldoAController,
                  saldoBController: saldoBController,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.ink, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
            ),
        ],
      ),
    );
  }
}

class _HutangPelangganSection extends StatefulWidget {
  final VoidCallback? onSaved;
  const _HutangPelangganSection({this.onSaved});
  @override
  State<_HutangPelangganSection> createState() =>
      _HutangPelangganSectionState();
}

class _HutangPelangganSectionState extends State<_HutangPelangganSection> {
  final _addNameController = TextEditingController();
  final _addAmountController = TextEditingController();
  final Map<String, TextEditingController> _editingControllers = {};
  int? _editingId;
  String? _editingField;

  @override
  void dispose() {
    _addNameController.dispose();
    _addAmountController.dispose();
    for (final c in _editingControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    return Consumer<CustomerDailyBalanceProvider>(
      builder: (context, cdbProv, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Hutang per Pelanggan',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Total: ${rupiahD(cdbProv.dayTotal)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (cdbProv.currentDateBalances.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => ConfirmationDialog.show(
                        context: context,
                        title: 'Hapus Semua Hutang',
                        message:
                            'Hapus semua catatan hutang untuk hari ini?',
                        isDestructive: true,
                        onConfirm: () async {
                          for (final b in cdbProv.currentDateBalances.toList()) {
                            await cdbProv.deleteEntry(b.id!);
                          }
                          widget.onSaved?.call();
                        },
                      ),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Hapus Semua'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.debt,
                        side: const BorderSide(color: AppTheme.debt),
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (isMobile)
                  Column(
                    children: [
                      TextField(
                        controller: _addNameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nama Pelanggan',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _addAmountController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [RupiahInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Jumlah (Rp)',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Tambah Hutang'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Nama Pelanggan',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _addAmountController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [RupiahInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Jumlah (Rp)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Tambah Hutang'),
                      ),
                    ],
                  ),
                if (cdbProv.currentDateBalances.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildList(cdbProv),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _save() async {
    final name = _addNameController.text.trim();
    final amount =
        int.tryParse(_addAmountController.text.split(',').first.replaceAll('.', '')) ?? 0;
    if (name.isEmpty || amount <= 0) return;
    final selectedDate = context.read<TabProvider>().selectedDate;
    await context.read<CustomerDailyBalanceProvider>().addCustomDebt(
          selectedDate,
          name,
          amount,
        );
    widget.onSaved?.call();
    _addNameController.clear();
    _addAmountController.clear();
  }

  void _startEdit(CustomerDailyBalance bal, String field, String initialValue) {
    setState(() {
      _editingId = bal.id;
      _editingField = field;
      _editingControllers[field] = TextEditingController(text: initialValue);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingControllers.clear();
      _editingId = null;
      _editingField = null;
    });
  }

  Future<void> _saveInlineEdit(
    CustomerDailyBalance bal,
    String field,
    CustomerDailyBalanceProvider cdbProv,
  ) async {
    final controller = _editingControllers[field];
    if (controller == null) return;
    final name = field == 'name' ? controller.text.trim() : bal.name;
    final amount = field == 'amount'
        ? int.tryParse(controller.text.split(',').first.replaceAll('.', '')) ?? 0
        : bal.amount;
    if (name.isEmpty || amount <= 0) {
      _cancelEdit();
      return;
    }
    final selectedDate = context.read<TabProvider>().selectedDate;
    if (bal.date == selectedDate) {
      await cdbProv.updateEntry(bal.id!, amount: amount, name: name);
    } else {
      await cdbProv.addCustomDebt(selectedDate, name, amount);
    }
    widget.onSaved?.call();
    if (mounted) {
      setState(() {
        _editingControllers.clear();
        _editingId = null;
        _editingField = null;
      });
    }
  }

  Widget _editableCell(
    CustomerDailyBalance bal,
    String field,
    String display,
    CustomerDailyBalanceProvider cdbProv, {
    required String editValue,
    bool bold = false,
    TextStyle? style,
    TextAlign textAlign = TextAlign.left,
  }) {
    if (_editingId == bal.id && _editingField == field) {
      final controller = _editingControllers[field]!;
      final isAmount = field == 'amount';
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: isAmount
                  ? TextInputType.number
                  : TextInputType.text,
              inputFormatters: isAmount ? [RupiahInputFormatter()] : null,
              textAlign: TextAlign.left,
              style: style ?? const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              ),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onSubmitted: (_) => _saveInlineEdit(bal, field, cdbProv),
            ),
          ),
          SizedBox(
            width: 28,
            child: IconButton(
              icon: const Icon(Icons.check, size: 18, color: AppTheme.paid),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: () => _saveInlineEdit(bal, field, cdbProv),
            ),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: () => _startEdit(bal, field, editValue),
      child: Text(
        display,
        style: style ??
            TextStyle(
              fontSize: 11,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: AppTheme.accent,
            ),
        textAlign: textAlign,
        softWrap: true,
        maxLines: null,
      ),
    );
  }

  Widget _buildList(CustomerDailyBalanceProvider cdbProv) {
    final isMobile = AppTheme.isMobile(context);
    const double cDate = 90;
    final double cName = isMobile ? 110 : 130;
    final double cAmt = isMobile ? 110 : 130;
    final double cPrint = isMobile ? 30 : 40;
    final double cDel = isMobile ? 28 : 40;
    final double tableW = isMobile
        ? cName + cAmt + cPrint + cDel + 24
        : cDate + cName + cAmt + cPrint + cDel + 24;

    final headerRow = Container(
      color: AppTheme.ink.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (!isMobile)
            SizedBox(
              width: cDate,
              child: const Text(
                'TANGGAL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
          SizedBox(
            width: cName,
            child: const Text(
              'NAMA',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: cAmt,
            child: const Text(
              'JUMLAH',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(width: cPrint),
          SizedBox(width: cDel),
        ],
      ),
    );

    final dataRows = cdbProv.currentDateBalances.asMap().entries.map((entry) {
      final bal = entry.value;
      return Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.line, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (!isMobile)
              SizedBox(
                width: cDate,
                child: Text(
                  fmtDate(bal.date),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            SizedBox(
              width: cName,
              child: _editableCell(
                bal,
                'name',
                bal.name,
                cdbProv,
                editValue: bal.name,
              ),
            ),
            SizedBox(
              width: cAmt,
              child: _editableCell(
                bal,
                'amount',
                rupiahD(bal.amount),
                cdbProv,
                editValue: bal.amount.toString(),
                bold: true,
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(
              width: cPrint,
              child: GestureDetector(
                onTap: () =>
                    _printDebtReceipt(context, bal.name, bal.amount),
                child: const Icon(
                  Icons.print,
                  size: 16,
                  color: AppTheme.accent,
                ),
              ),
            ),
            SizedBox(
              width: cDel,
              child: IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: AppTheme.debt,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => ConfirmationDialog.show(
                  context: context,
                  title: 'Hapus Hutang',
                  message:
                      'Hapus catatan hutang ${bal.name} untuk hari ini?',
                  isDestructive: true,
                  onConfirm: () async {
                    await cdbProv.deleteEntry(bal.id!);
                    widget.onSaved?.call();
                  },
                ),
              ),
            ),
          ],
        ),
      );
    });

    final tableContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [headerRow, ...dataRows],
    );

    if (isMobile) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: tableW, child: tableContent),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: tableContent,
    );
  }

  Future<void> _printDebtReceipt(
    BuildContext context,
    String customerName,
    int totalDebt,
  ) async {
    final printerProv = context.read<PrinterProvider>();
    final ledgerProv = context.read<CustomerLedgerProvider>();
    if (!printerProv.isConnected) {
      if (!mounted) return;
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

    final processed = ledgerProv.processCustomerDebts(customerName);
    final activeDebts = processed['activeDebts'] as List<dynamic>;

    final receiptItems = <ReceiptItem>[];
    for (final d in activeDebts) {
      final date = d['date'] as String;
      final remaining = (d['remaining'] as num).toInt();
      final dateParts = date.split('-');
      final shortDate =
          '${dateParts[2]}/${dateParts[1]}/${dateParts[0].substring(2)}';
      receiptItems.add(
        ReceiptItem(
          name: shortDate,
          detail: 'Hutang',
          subtotal: rupiahPlain(remaining),
        ),
      );
    }

    final result = await printerProv.printReceipt(
      items: receiptItems,
      totalText: rupiahPlain(totalDebt),
      paidText: '-',
      changeText: 'Belum dibayar',
      customerName: customerName,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result ? 'Struk hutang $customerName tercetak' : 'Gagal cetak struk',
        ),
        backgroundColor: result ? AppTheme.paid : AppTheme.debt,
      ),
    );
  }
}

class _StokMinyakSection extends StatefulWidget {
  final TextEditingController qtyController;
  final TextEditingController priceController;
  final VoidCallback? onSaved;
  final FocusNode? qtyFocusNode;
  final FocusNode? priceFocusNode;

  const _StokMinyakSection({
    required this.qtyController,
    required this.priceController,
    this.onSaved,
    this.qtyFocusNode,
    this.priceFocusNode,
  });

  @override
  State<_StokMinyakSection> createState() => _StokMinyakSectionState();
}

class _StokMinyakSectionState extends State<_StokMinyakSection> {
  void _save() async {
    final qty = parseNumInput(widget.qtyController.text);
    final price = parseNumInput(widget.priceController.text);
    if (qty > 0) {
      final oilProv = context.read<OilStockProvider>();
      final selectedDate = context.read<TabProvider>().selectedDate;
      await oilProv.addOil(selectedDate, qty, price);
      widget.onSaved?.call();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    return Consumer<OilStockProvider>(
      builder: (context, oilProv, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stok Minyak',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (isMobile)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: widget.qtyController,
                        focusNode: widget.qtyFocusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                        decoration: const InputDecoration(
                          labelText: 'Jumlah (liter/kg)',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: widget.priceController,
                        focusNode: widget.priceFocusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                        decoration: const InputDecoration(
                          labelText: 'Harga (Rp)',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Subtotal:',
                            style: TextStyle(
                              color: AppTheme.inkSoft,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            rupiahD(
                              parseNumInput(widget.qtyController.text) *
                                      parseNumInput(widget.priceController.text),
                            ),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Simpan'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.qtyController,
                          focusNode: widget.qtyFocusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                          decoration: const InputDecoration(
                            labelText: 'Jumlah (liter/kg)',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _save(),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: widget.priceController,
                          focusNode: widget.priceFocusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                          decoration: const InputDecoration(
                            labelText: 'Harga (Rp)',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _save(),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        rupiahD(
                          parseNumInput(widget.qtyController.text) *
                                  parseNumInput(widget.priceController.text),
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Simpan'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ManajemenStokSection extends StatefulWidget {
  final VoidCallback? onSaved;
  const _ManajemenStokSection({this.onSaved});
  @override
  State<_ManajemenStokSection> createState() => _ManajemenStokSectionState();
}

class _ManajemenStokSectionState extends State<_ManajemenStokSection> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final List<TextEditingController> _sackControllers = [
    TextEditingController(),
  ];
  final Map<String, TextEditingController> _editControllers = {};
  final Map<String, TextEditingController> _editPriceControllers = {};
  String? _editingBatchKey;
  String? _editingPriceKey;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    for (final c in _sackControllers) {
      c.dispose();
    }
    for (final c in _editControllers.values) {
      c.dispose();
    }
    for (final c in _editPriceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addSackField() =>
      setState(() => _sackControllers.add(TextEditingController()));
  void _removeSackField(int index) {
    if (_sackControllers.length > 1) {
      setState(() {
        _sackControllers[index].dispose();
        _sackControllers.removeAt(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    return Consumer<StockManagementProvider>(
      builder: (context, smProv, _) {
        final grouped = <String, List<StockManagement>>{};
        for (final sm in smProv.currentDateStocks) {
          grouped.putIfAbsent(sm.name, () => []).add(sm);
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Stok Bahan',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isMobile)
                      Flexible(
                        child: Text(
                          'Total: ${rupiahD(smProv.dayTotal)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      Text(
                        'Total: ${rupiahD(smProv.dayTotal)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isMobile)
                  Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nama Pemegang',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                        decoration: const InputDecoration(
                          labelText: 'Harga/sak (Rp)',
                          isDense: true,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Nama Pemegang',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                          decoration: const InputDecoration(
                            labelText: 'Harga/sak (Rp)',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                ...List.generate(_sackControllers.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sackControllers[i],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Sak ${i + 1} (kg)',
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_sackControllers.length > 1)
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 20,
                              color: AppTheme.debt,
                            ),
                            onPressed: () => _removeSackField(i),
                          ),
                      ],
                    ),
                  );
                }),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _addSackField,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Tambah Sak'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _save,
                      child: const Text('Simpan'),
                    ),
                  ],
                ),
                if (grouped.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...grouped.entries.map(
                    (entry) => _buildHolderCard(entry.key, entry.value, smProv),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _save() async {
    final name = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.split(',').first.replaceAll('.', '')) ?? 0;
    final sacks = _sackControllers
        .map((c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0)
        .where((v) => v > 0)
        .toList();
    if (name.isNotEmpty && sacks.isNotEmpty) {
      final selectedDate = context.read<TabProvider>().selectedDate;
      await context.read<StockManagementProvider>().addStockMgmt(
        selectedDate,
        name,
        price,
        sacks,
      );
      widget.onSaved?.call();
      _nameController.clear();
      _priceController.clear();
      setState(() {
        for (final c in _sackControllers) {
          c.clear();
        }
      });
    }
  }

  Widget _buildHolderCard(
    String holderName,
    List<StockManagement> items,
    StockManagementProvider smProv,
  ) {
    final holderTotal = items.fold<int>(0, (sum, s) => sum + s.subtotal);
    final isMobile = AppTheme.isMobile(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppTheme.ink.withValues(alpha: 0.05),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    holderName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showAddSackDialog(context, holderName, smProv),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '+ Sak',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  rupiahD(holderTotal),
                  style: const TextStyle(
                    color: AppTheme.debt,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          _buildHolderTable(items, smProv, isMobile),
        ],
      ),
    );
  }

  Widget _buildHolderTable(
    List<StockManagement> items,
    StockManagementProvider smProv,
    bool isMobile,
  ) {
    const double cDate = 90;
    final double cSak = isMobile ? 48 : 55;
    final double cKg = isMobile ? 52 : 65;
    final double cPrice = isMobile ? 100 : 120;
    final double cSub = isMobile ? 100 : 120;
    final double cDel = isMobile ? 28 : 40;
    final double tableW = isMobile
        ? cSak + cKg + cPrice + cSub + cDel + 24
        : cDate + cSak + cKg + cPrice + cSub + cDel + 24;

    final headerRow = Container(
      color: AppTheme.ink.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (!isMobile)
            SizedBox(
              width: cDate,
              child: const Text(
                'TANGGAL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
          SizedBox(
            width: cSak,
            child: const Text(
              'SAK',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: cKg,
            child: const Text(
              'KG',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: cPrice,
            child: const Text(
              'HARGA/SAK',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: cSub,
            child: const Text(
              'SUBTOTAL',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(width: cDel),
        ],
      ),
    );

    final dataRows = items.asMap().entries.expand((entry2) {
      final sm = entry2.value;
      final batches = sm.batches ?? [];
      return batches.asMap().entries.map((bEntry) {
        final bi = bEntry.key;
        final batch = bEntry.value;
        final sacks = (batch['sacks'] as List?) ?? [];
        final batchId = batch['id'] as String?;
        final batchQty = sacks.fold<double>(
          0,
          (a, b) => a + (b as num).toDouble(),
        );
        final batchPrice = (batch['price'] as num?)?.toInt() ?? sm.price;
        final batchSubtotal = batchQty * batchPrice;
        final editKey = '${sm.id}_$batchId';
        final isEditing = _editingBatchKey == editKey;
        final isPriceEditing = _editingPriceKey == editKey;

        return Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.line, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              if (!isMobile)
                SizedBox(
                  width: cDate,
                  child: Text(
                    bi == 0 ? fmtDate(sm.date) : '',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              SizedBox(
                width: cSak,
                child: Text(
                  'Sak ${bi + 1}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              SizedBox(
                width: cKg,
                child: isEditing
                    ? TextField(
                        controller: _editControllers[editKey],
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.all(4),
                        ),
                        onSubmitted: (_) =>
                            _saveBatchEdit(sm.id!, batchId!, smProv),
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() {
                            _editingBatchKey = editKey;
                            _editControllers[editKey] = TextEditingController(
                              text: fmtKg(batchQty),
                            );
                          });
                        },
                        child: Text(
                          fmtKg(batchQty),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
              ),
              SizedBox(
                width: cPrice,
                child: isPriceEditing
                    ? TextField(
                        controller: _editPriceControllers[editKey],
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          RupiahInputFormatter(allowDecimal: true),
                        ],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.all(6),
                        ),
                        onSubmitted: (_) =>
                            _savePriceEdit(sm.id!, batchId!, smProv),
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() {
                            _editingPriceKey = editKey;
                            _editPriceControllers[editKey] =
                                TextEditingController(
                                  text: batchPrice.toString(),
                                );
                          });
                        },
                        child: Text(
                          rupiahD(batchPrice),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
              ),
              SizedBox(
                width: cSub,
                child: Text(
                  rupiahD(batchSubtotal),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: cDel,
                child: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppTheme.debt,
                  ),
                  onPressed: () =>
                      smProv.deleteStockBatch(sm.id!, batchId!),
                ),
              ),
            ],
          ),
        );
      });
    });

    final totalRow = _buildTotalRow(items, isMobile: isMobile);

    final tableContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [headerRow, ...dataRows, totalRow],
    );

    if (isMobile) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(width: tableW, child: tableContent),
      );
    }
    return tableContent;
  }

  void _showAddSackDialog(
    BuildContext context,
    String holderName,
    StockManagementProvider smProv,
  ) {
    final sackController = TextEditingController();
    final holderItems = smProv.currentDateStocks.where((s) => s.name == holderName);
    final defaultPrice = holderItems.isNotEmpty ? holderItems.first.price : 0;
    final priceController = TextEditingController(
      text: defaultPrice > 0 ? defaultPrice.toString() : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tambah Sak - $holderName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: sackController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Jumlah kg',
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
              decoration: const InputDecoration(
                labelText: 'Harga per sak (Rp)',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final kg =
                  double.tryParse(sackController.text.replaceAll(',', '.')) ??
                  0;
              final price =
                  int.tryParse(priceController.text.split(',').first.replaceAll('.', '')) ??
                  defaultPrice;
              if (kg > 0) {
                await smProv.addStockMgmt(
                  context.read<TabProvider>().selectedDate,
                  holderName,
                  price,
                  [kg],
                );
                widget.onSaved?.call();
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
  }

  void _saveBatchEdit(
    int itemId,
    String batchId,
    StockManagementProvider smProv,
  ) async {
    final controller = _editControllers['${itemId}_$batchId'];
    if (controller == null) return;
    final newKg = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
    final item = smProv.monthStocks.firstWhere((s) => s.id == itemId);
    final batch = (item.batches ?? []).firstWhere((b) => b['id'] == batchId);
    final oldSacks = List<double>.from(
      (batch['sacks'] as List?)?.map((e) => (e as num).toDouble()) ?? [],
    );
    if (oldSacks.isNotEmpty) oldSacks[0] = newKg;
    await smProv.updateBatchSacks(itemId, batchId, oldSacks);
    setState(() {
      _editingBatchKey = null;
    });
  }

  void _savePriceEdit(
    int itemId,
    String batchId,
    StockManagementProvider smProv,
  ) async {
    final controller = _editPriceControllers['${itemId}_$batchId'];
    if (controller == null) return;
    final newPrice = int.tryParse(controller.text.split(',').first.replaceAll('.', '')) ?? 0;
    if (newPrice > 0) {
      await smProv.updateBatchPrice(itemId, batchId, newPrice);
    }
    setState(() {
      _editingPriceKey = null;
    });
  }

  Widget _buildTotalRow(
    List<StockManagement> items, {
    bool isMobile = false,
  }) {
    double totalKg = 0;
    double totalSub = 0;
    for (final sm in items) {
      for (final batch in (sm.batches ?? [])) {
        final sacks = (batch['sacks'] as List?) ?? [];
        final batchQty = sacks.fold<double>(
          0,
          (a, b) => a + (b as num).toDouble(),
        );
        final batchPrice = (batch['price'] as num?)?.toInt() ?? sm.price;
        totalKg += batchQty;
        totalSub += batchQty * batchPrice;
      }
    }
    final cSak = isMobile ? 48.0 : 55.0;
    final cKg = isMobile ? 52.0 : 65.0;
    final cPrice = isMobile ? 100.0 : 120.0;
    final cSub = isMobile ? 100.0 : 120.0;
    final cDel = isMobile ? 28.0 : 40.0;
    return Container(
      color: AppTheme.ink.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (!isMobile) const SizedBox(width: 90),
          SizedBox(
            width: cSak,
            child: const Text(
              'TOTAL',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: cKg,
            child: Text(
              fmtKg(totalKg),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            width: cPrice,
          ),
          SizedBox(
            width: cSub,
            child: Text(
              rupiahD(totalSub),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(width: cDel),
        ],
      ),
    );
  }
}

class _SisaBarangSection extends StatefulWidget {
  final VoidCallback? onSaved;
  const _SisaBarangSection({this.onSaved});
  @override
  State<_SisaBarangSection> createState() => _SisaBarangSectionState();
}

class _SisaBarangSectionState extends State<_SisaBarangSection> {
  int? _selectedProductId;
  bool _isCustom = false;
  final _nameController = TextEditingController();
  final _qtyController = TextEditingController();
  final _priceController = TextEditingController();
  final Map<int, TextEditingController> _editQtyControllers = {};
  final Map<int, TextEditingController> _editPriceControllers = {};
  int? _editingId;
  int? _editingPriceId;

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    for (final c in _editQtyControllers.values) {
      c.dispose();
    }
    for (final c in _editPriceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    return Consumer2<StockRemainingProvider, ProductProvider>(
      builder: (context, srProv, prodProv, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sisa Barang',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Total: ${rupiahD(srProv.dayTotal)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isMobile)
                  Column(
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _isCustom ? -1 : _selectedProductId,
                        decoration: const InputDecoration(
                          labelText: 'Produk',
                          isDense: true,
                        ),
                        items: [
                          ...prodProv.products.map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            ),
                          ),
                          const DropdownMenuItem(
                            value: -1,
                            child: Text('Lainnya...'),
                          ),
                        ],
                        onChanged: (val) => setState(() {
                          if (val == -1) {
                            _isCustom = true;
                            _selectedProductId = null;
                          } else {
                            _isCustom = false;
                            _selectedProductId = val;
                          }
                        }),
                      ),
                        if (_isCustom) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Nama Barang',
                            isDense: true,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _qtyController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Kg',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _priceController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                              decoration: const InputDecoration(
                                labelText: 'Harga (Rp)',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Tambah'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          initialValue: _isCustom ? -1 : _selectedProductId,
                          decoration: const InputDecoration(
                            labelText: 'Produk',
                            isDense: true,
                          ),
                          items: [
                            ...prodProv.products.map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name),
                              ),
                            ),
                            const DropdownMenuItem(
                              value: -1,
                              child: Text('Lainnya...'),
                            ),
                          ],
                          onChanged: (val) => setState(() {
                            if (val == -1) {
                              _isCustom = true;
                              _selectedProductId = null;
                            } else {
                              _isCustom = false;
                              _selectedProductId = val;
                            }
                          }),
                        ),
                      ),
                      if (_isCustom) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nama Barang',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _qtyController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Jumlah (kg)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                          decoration: const InputDecoration(
                            labelText: 'Harga (Rp)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Tambah'),
                      ),
                    ],
                  ),
                if (srProv.currentDateStocks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildList(srProv),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _save() async {
    final name = _isCustom
        ? _nameController.text.trim()
        : context
              .read<ProductProvider>()
              .products
              .where((p) => p.id == _selectedProductId)
              .firstOrNull
              ?.name;
    final price = int.tryParse(_priceController.text.split(',').first.replaceAll('.', '')) ?? 0;
    final qty = double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? 0;
    if (name != null && name.isNotEmpty) {
      final selectedDate = context.read<TabProvider>().selectedDate;
      await context.read<StockRemainingProvider>().addRemain(
        selectedDate,
        Product(id: 0, name: name, price: price),
        qty,
        price,
      );
      widget.onSaved?.call();
      _qtyController.clear();
      _priceController.clear();
      _nameController.clear();
    }
  }

  Widget _buildList(StockRemainingProvider srProv) {
    final isMobile = AppTheme.isMobile(context);
    const double cDate = 90;
    final double cName = isMobile ? 110 : 120;
    final double cKg = isMobile ? 52 : 65;
    final double cPrice = isMobile ? 100 : 120;
    final double cSub = isMobile ? 100 : 120;
    final double cDel = isMobile ? 28 : 40;
    final double tableW = isMobile
        ? cName + cKg + cPrice + cSub + cDel + 24
        : cDate + cName + cKg + cPrice + cSub + cDel + 24;

    final headerRow = Container(
      color: AppTheme.ink.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (!isMobile)
            SizedBox(
              width: cDate,
              child: const Text(
                'TANGGAL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
          SizedBox(
            width: cName,
            child: Text(
              'NAMA',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: cKg,
            child: Text(
              'KG',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: cPrice,
            child: Text(
              'HARGA/kg',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: cSub,
            child: Text(
              'SUBTOTAL',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(width: cDel),
        ],
      ),
    );

    final dataRows = srProv.currentDateStocks.asMap().entries.map((entry) {
      final sr = entry.value;
      final isEditing = _editingId == sr.id;
      final isPriceEditing = _editingPriceId == sr.id;
      return Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.line, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (!isMobile)
              SizedBox(
                width: cDate,
                child: Text(
                  fmtDate(sr.date),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            SizedBox(
              width: cName,
              child: Text(
                sr.name,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: cKg,
              child: isEditing
                  ? TextField(
                      controller: _editQtyControllers.putIfAbsent(
                        sr.id!,
                        () => TextEditingController(text: fmtKg(sr.qty)),
                      ),
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 11),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.all(4),
                      ),
                      onSubmitted: (_) => _saveQtyEdit(sr),
                    )
                  : GestureDetector(
                      onTap: () => setState(() {
                        _editingId = sr.id;
                        _editQtyControllers[sr.id!] =
                            TextEditingController(text: fmtKg(sr.qty));
                      }),
                      child: Text(
                        fmtKg(sr.qty),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
            ),
            SizedBox(
              width: cPrice,
              child: isPriceEditing
                  ? TextField(
                      controller: _editPriceControllers.putIfAbsent(
                        sr.id!,
                        () => TextEditingController(
                          text: sr.price.toString(),
                        ),
                      ),
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        RupiahInputFormatter(allowDecimal: true),
                      ],
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.all(6),
                      ),
                      onSubmitted: (_) => _savePriceEdit(sr),
                    )
                  : GestureDetector(
                      onTap: () => setState(() {
                        _editingPriceId = sr.id;
                        _editPriceControllers[sr.id!] =
                            TextEditingController(
                              text: sr.price.toString(),
                            );
                      }),
                      child: Text(
                        rupiahD(sr.price),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.debt,
                        ),
                      ),
                    ),
            ),
            SizedBox(
              width: cSub,
              child: Text(
                rupiahD(sr.subtotal),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: cDel,
              child: IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: AppTheme.debt,
                ),
                onPressed: () => srProv.deleteRemain(sr.id!),
              ),
            ),
          ],
        ),
      );
    });

    final tableContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [headerRow, ...dataRows],
    );

    if (isMobile) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: tableW, child: tableContent),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: tableContent,
    );
  }

  void _saveQtyEdit(StockRemaining sr) async {
    final controller = _editQtyControllers[sr.id];
    if (controller == null) return;
    final newQty = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
    final srProv = context.read<StockRemainingProvider>();
    final selectedDate = context.read<TabProvider>().selectedDate;
    if (sr.date == selectedDate) {
      await srProv.updateRemain(
        sr.id!,
        newQty,
        sr.price,
        sr.date ?? todayString(),
      );
    } else {
      await srProv.addRemain(
        selectedDate,
        Product(id: 0, name: sr.name, price: sr.price),
        newQty,
        sr.price,
      );
    }
    if (mounted) {
      setState(() {
        _editingId = null;
      });
    }
  }

  void _savePriceEdit(StockRemaining sr) async {
    final controller = _editPriceControllers[sr.id];
    if (controller == null) return;
    final newPrice = int.tryParse(controller.text.split(',').first.replaceAll('.', '')) ?? 0;
    final srProv = context.read<StockRemainingProvider>();
    final selectedDate = context.read<TabProvider>().selectedDate;
    if (sr.date == selectedDate) {
      await srProv.updateRemain(
        sr.id!,
        sr.qty,
        newPrice,
        sr.date ?? todayString(),
      );
    } else {
      await srProv.addRemain(
        selectedDate,
        Product(id: 0, name: sr.name, price: newPrice),
        sr.qty,
        newPrice,
      );
    }
    if (mounted) {
      setState(() {
        _editingPriceId = null;
      });
    }
  }
}

class _HutangPribadiSection extends StatefulWidget {
  final VoidCallback? onSaved;
  const _HutangPribadiSection({this.onSaved});
  @override
  State<_HutangPribadiSection> createState() => _HutangPribadiSectionState();
}

class _HutangPribadiSectionState extends State<_HutangPribadiSection> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final Map<String, TextEditingController> _editingControllers = {};
  int? _editingId;
  String? _editingField;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    for (final c in _editingControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    return Consumer<PersonalLedgerProvider>(
      builder: (context, plProv, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Hutang Pribadi',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Total: ${rupiahD(plProv.dayTotal)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isMobile)
                  Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nama',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                        decoration: const InputDecoration(
                          labelText: 'Jumlah (Rp)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Catatan',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Tambah'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Nama',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
                          decoration: const InputDecoration(
                            labelText: 'Jumlah (Rp)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _noteController,
                          decoration: const InputDecoration(
                            labelText: 'Catatan',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Tambah'),
                      ),
                    ],
                  ),
                if (plProv.currentDateLedgers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildList(plProv),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _save() async {
    final name = _nameController.text.trim();
    final amount =
        int.tryParse(_amountController.text.split(',').first.replaceAll('.', '')) ?? 0;
    if (name.isNotEmpty && amount > 0) {
      await context.read<PersonalLedgerProvider>().addHutangPribadi(
        context.read<TabProvider>().selectedDate,
        name,
        amount,
        _noteController.text,
      );
      widget.onSaved?.call();
      _nameController.clear();
      _amountController.clear();
      _noteController.clear();
    }
  }

  void _startEdit(PersonalLedger pl, String field, String initialValue) {
    setState(() {
      _editingId = pl.id;
      _editingField = field;
      _editingControllers[field] = TextEditingController(text: initialValue);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingControllers.clear();
      _editingId = null;
      _editingField = null;
    });
  }

  Future<void> _saveInlineEdit(
    PersonalLedger pl,
    String field,
    PersonalLedgerProvider plProv,
  ) async {
    final controller = _editingControllers[field];
    if (controller == null) return;
    final name = field == 'name'
        ? controller.text.trim()
        : pl.name;
    final amount = field == 'amount'
        ? int.tryParse(controller.text.split(',').first.replaceAll('.', '')) ?? 0
        : pl.amount;
    final note = field == 'note'
        ? controller.text.trim()
        : pl.note ?? '';
    if (name.isEmpty || amount <= 0) {
      _cancelEdit();
      return;
    }
    final selectedDate = context.read<TabProvider>().selectedDate;
    if (pl.date == selectedDate) {
      await plProv.updateEntry(pl.id!, name, amount, note);
    } else {
      await plProv.addHutangPribadi(selectedDate, name, amount, note);
    }
    widget.onSaved?.call();
    if (mounted) {
      setState(() {
        _editingControllers.clear();
        _editingId = null;
        _editingField = null;
      });
    }
  }

  Widget _editableCell(
    PersonalLedger pl,
    String field,
    String display,
    PersonalLedgerProvider plProv, {
    required String editValue,
    bool bold = false,
    TextStyle? style,
    TextAlign textAlign = TextAlign.left,
  }) {
    if (_editingId == pl.id && _editingField == field) {
      final controller = _editingControllers[field]!;
      final isAmount = field == 'amount';
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: isAmount ? TextInputType.number : TextInputType.text,
              inputFormatters:
                  isAmount ? [RupiahInputFormatter(allowDecimal: true)] : null,
              textAlign: TextAlign.left,
              style: style ?? const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              ),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onSubmitted: (_) => _saveInlineEdit(pl, field, plProv),
            ),
          ),
          SizedBox(
            width: 28,
            child: IconButton(
              icon: const Icon(Icons.check, size: 18, color: AppTheme.paid),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: () => _saveInlineEdit(pl, field, plProv),
            ),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: () => _startEdit(pl, field, editValue),
      child: Text(
        display,
        style: style ??
            TextStyle(
              fontSize: 11,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: AppTheme.accent,
            ),
        textAlign: textAlign,
        softWrap: true,
        maxLines: null,
      ),
    );
  }

  Widget _buildList(PersonalLedgerProvider plProv) {
    final isMobile = AppTheme.isMobile(context);
    const double cDate = 90;
    final double cName = isMobile ? 100 : 120;
    final double cAmt = isMobile ? 100 : 120;
    final double cNote = isMobile ? 130 : 150;
    final double cDel = isMobile ? 28 : 40;
    final double tableW = isMobile
        ? cName + cAmt + cNote + cDel + 24
        : cDate + cName + cAmt + cNote + cDel + 24;

    final headerRow = Container(
      color: AppTheme.ink.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (!isMobile)
            SizedBox(
              width: cDate,
              child: const Text(
                'TANGGAL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
          SizedBox(
            width: cName,
            child: Text(
              'NAMA',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: cAmt,
            child: Text(
              'JUMLAH',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          SizedBox(
            width: cNote,
            child: Text(
              'CATATAN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          SizedBox(width: cDel),
        ],
      ),
    );

    final dataRows = plProv.currentDateLedgers.asMap().entries.map((entry) {
      final pl = entry.value;
      return Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.line, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (!isMobile)
              SizedBox(
                width: cDate,
                child: Text(
                  fmtDate(pl.date),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            SizedBox(
              width: cName,
              child: _editableCell(
                pl,
                'name',
                pl.name,
                plProv,
                editValue: pl.name,
              ),
            ),
            SizedBox(
              width: cAmt,
              child: _editableCell(
                pl,
                'amount',
                rupiahD(pl.amount),
                plProv,
                editValue: pl.amount.toString(),
                bold: true,
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(
              width: cNote,
              child: _editableCell(
                pl,
                'note',
                pl.note ?? '',
                plProv,
                editValue: pl.note ?? '',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
            SizedBox(
              width: cDel,
              child: IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: AppTheme.debt,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => plProv.deleteEntry(pl.id!),
              ),
            ),
          ],
        ),
      );
    });

    final tableContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [headerRow, ...dataRows],
    );

    if (isMobile) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: tableW, child: tableContent),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: tableContent,
    );
  }
}

class _SaldoDeductionSection extends StatefulWidget {
  final TextEditingController aController;
  final TextEditingController bController;
  final VoidCallback? onSaved;
  final FocusNode? aFocusNode;
  final FocusNode? bFocusNode;
  const _SaldoDeductionSection({
    required this.aController,
    required this.bController,
    this.onSaved,
    this.aFocusNode,
    this.bFocusNode,
  });
  @override
  State<_SaldoDeductionSection> createState() => _SaldoDeductionSectionState();
}

class _SaldoDeductionSectionState extends State<_SaldoDeductionSection> {
  double get _result {
    return parseNumInput(widget.aController.text) -
        parseNumInput(widget.bController.text);
  }

  void _save() async {
    final a = parseNumInput(widget.aController.text);
    final b = parseNumInput(widget.bController.text);
    if (a > 0 || b > 0) {
      await context.read<SaldoDeductionProvider>().addSaldo(
        context.read<TabProvider>().selectedDate,
        a,
        b,
        '',
      );
      widget.onSaved?.call();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    final fieldA = TextField(
      controller: widget.aController,
      focusNode: widget.aFocusNode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
      decoration: const InputDecoration(labelText: 'A', isDense: true),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    );
    final fieldB = TextField(
      controller: widget.bController,
      focusNode: widget.bFocusNode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [RupiahInputFormatter(allowDecimal: true)],
      decoration: const InputDecoration(labelText: 'B', isDense: true),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    );
    final minus = const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '−',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
    final equals = const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '=',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
    final result = Text(
      rupiahD(_result),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      textAlign: TextAlign.right,
    );
    final saveBtn = IconButton(
      icon: const Icon(Icons.save, color: AppTheme.accent),
      onPressed: _save,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pengurangan Saldo',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (isMobile) ...[
              Row(
                children: [
                  Expanded(child: fieldA),
                  minus,
                  Expanded(child: fieldB),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: result),
                  saveBtn,
                ],
              ),
            ] else
              Row(
                children: [
                  Expanded(child: fieldA),
                  minus,
                  Expanded(child: fieldB),
                  equals,
                  Expanded(child: result),
                  const SizedBox(width: 8),
                  saveBtn,
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RincianHarianSection extends StatefulWidget {
  final TextEditingController oilQtyController;
  final TextEditingController oilPriceController;
  final TextEditingController saldoAController;
  final TextEditingController saldoBController;
  const _RincianHarianSection({
    required this.oilQtyController,
    required this.oilPriceController,
    required this.saldoAController,
    required this.saldoBController,
  });
  @override
  State<_RincianHarianSection> createState() => _RincianHarianSectionState();
}

class _RincianHarianSectionState extends State<_RincianHarianSection> {
  String _sig = '';

  @override
  Widget build(BuildContext context) {
    final oilProv = context.watch<OilStockProvider>();
    final smProv = context.watch<StockManagementProvider>();
    final srProv = context.watch<StockRemainingProvider>();
    final ledgerProv = context.watch<CustomerLedgerProvider>();
    final plProv = context.watch<PersonalLedgerProvider>();
    final cdbProv = context.watch<CustomerDailyBalanceProvider>();
    final ringProv = context.watch<RingkasanProvider>();

    final newSig =
        '${oilProv.monthTotal}|${smProv.monthTotal}|${srProv.monthTotal}|${plProv.monthTotal}|${cdbProv.dayTotal}|${ledgerProv.balances.values.fold<int>(0, (s, v) => s + (v > 0 ? v : 0))}';
    if (newSig != _sig) {
      _sig = newSig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final tabProv = context.read<TabProvider>();
        final ledger = context.read<CustomerLedgerProvider>();
        context.read<RingkasanProvider>().calculate(
          activeMonth: tabProv.activeMonth,
          selectedDate: tabProv.selectedDate,
          customerBalances: ledger.balances,
        );
      });
    }

    final liveOil =
        parseNumInput(widget.oilQtyController.text) *
                parseNumInput(widget.oilPriceController.text);
    final liveSaldo = parseNumInput(widget.saldoAController.text) -
        parseNumInput(widget.saldoBController.text);
    final daily = ringProv.daily;
    final dStockMgmt = daily != null ? (daily['stockMgmt'] as num).toInt() : 0;
    final dRemain = daily != null ? (daily['remain'] as num).toInt() : 0;
    final dHutangPel = cdbProv.dayTotal;
    final dHutangPri = daily != null ? (daily['hutangPri'] as num).toInt() : 0;
    final totalHari = liveOil + dStockMgmt + dRemain + dHutangPel;
    final saldoHari = totalHari - dHutangPri;
    final totalAkhir = saldoHari - liveSaldo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _dailyRow('Stok Minyak', rupiahD(liveOil)),
            _dailyRow('Stok Bahan', rupiahD(dStockMgmt)),
            _dailyRow('Sisa Barang', rupiahD(dRemain)),
            _dailyRow(
              'Hutang Pelanggan',
              rupiahD(dHutangPel),
              valueColor: dHutangPel > 0 ? AppTheme.debt : AppTheme.paid,
            ),
            _dailyRow('Hutang Pribadi', rupiahD(dHutangPri)),
            _dailyRow('Pengurangan Saldo', rupiahD(liveSaldo)),
            const Divider(height: 24),
            _dailyRow('Total Hari Ini', rupiahD(totalHari), bold: true),
            const Divider(height: 20),
            _dailyRow('Saldo', rupiahD(saldoHari)),
            _dailyRow('TOTAL', rupiahD(totalAkhir), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _dailyRow(
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
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
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: valueColor ?? AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}
