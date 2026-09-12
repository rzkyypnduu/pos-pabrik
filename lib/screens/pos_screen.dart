import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../constants/formatters.dart';
import '../providers/tab_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/customer_ledger_provider.dart';
import '../providers/oil_stock_provider.dart';
import '../providers/stock_management_provider.dart';
import '../providers/stock_remaining_provider.dart';
import '../providers/personal_ledger_provider.dart';
import '../providers/saldo_deduction_provider.dart';
import '../providers/ringkasan_provider.dart';
import '../providers/printer_provider.dart';
import '../providers/backup_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/window_controls.dart';
import 'transaksi_tab.dart';
import 'produk_tab.dart';
import 'hasil_tab.dart';
import 'ringkasan_tab.dart';
import 'settings_tab.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _zoomController = TransformationController();
  bool _isClampingZoom = false;
  int _lastSyncRev = 0;

  void _onZoomChanged() {
    if (_isClampingZoom || !mounted) return;
    final m = _zoomController.value.clone();
    final s = m.getMaxScaleOnAxis();
    if (s > 1.0) {
      final vw = MediaQuery.sizeOf(context).width;
      final minTx = vw * (1 - s);
      final tx = m.entry(0, 3);
      final clamped = tx.clamp(minTx, 0.0);
      if (clamped != tx) {
        _isClampingZoom = true;
        m.setEntry(0, 3, clamped);
        _zoomController.value = m;
        _isClampingZoom = false;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _zoomController.addListener(_onZoomChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<ProductProvider>().loadProducts();
      context.read<CustomerLedgerProvider>().loadAll();
      final printerProv = context.read<PrinterProvider>();
      final backupProv = context.read<BackupProvider>();
      await printerProv.loadSavedSettings();
      await backupProv.loadSavedSettings();
      await backupProv.runBackupIfDue();
    });
  }

  @override
  void dispose() {
    _zoomController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    _setZoom(_zoomController.value.getMaxScaleOnAxis() * 1.25);
  }

  void _zoomOut() {
    _setZoom(_zoomController.value.getMaxScaleOnAxis() / 1.25);
  }

  void _setZoom(double target) {
    final newScale = target.clamp(1.0, 3.0);
    _zoomController.value =
        Matrix4.diagonal3Values(newScale, newScale, newScale);
  }

  @override
  Widget build(BuildContext context) {
    final tabProv = context.watch<TabProvider>();
    final isCompact = AppTheme.isCompact(context);
    final syncRev = context.select<SyncProvider, int>(
      (s) => s.revision,
    );
    if (syncRev != _lastSyncRev) {
      _lastSyncRev = syncRev;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reloadTabData(tabProv.currentTab);
      });
    }

    final tabs = [
      const TransaksiTab(),
      const ProdukTab(),
      const HasilTab(),
      const RingkasanTab(),
      const SettingsTab(),
    ];

    return Scaffold(
      body: Row(
        children: [
          if (!isCompact)
            AppSidebar(
              currentTab: tabProv.currentTab,
              onTabChanged: (i) {
                tabProv.setTab(i);
                _reloadTabData(i);
              },
            ),
          Expanded(
            child: Column(
              children: [
                if (!isCompact) const WindowControls(),
                if (isCompact) _mobileHeader(),
                Expanded(
                  child: AppTheme.isMobile(context)
                      ? InteractiveViewer(
                          transformationController: _zoomController,
                          minScale: 1.0,
                          maxScale: 3.0,
                          scaleFactor: 0.5,
                          boundaryMargin: EdgeInsets.zero,
                          interactionEndFrictionCoefficient: 0.5,
                          child: RefreshIndicator(
                            onRefresh: () => _refreshAllData(),
                            child: tabs[tabProv.currentTab],
                          ),
                        )
                      : tabs[tabProv.currentTab],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isCompact
          ? AppBottomNav(
              currentTab: tabProv.currentTab,
              onTabChanged: (i) {
                tabProv.setTab(i);
                _reloadTabData(i);
              },
            )
          : null,
    );
  }

  void _reloadTabData(int tabIndex) {
    final context = this.context;
    final tabProv = context.read<TabProvider>();
    switch (tabIndex) {
      case 0: // Transaksi
        context.read<CustomerLedgerProvider>().loadAll();
        context.read<TransactionProvider>().loadDaySales(tabProv.selectedDate);
        context.read<ExpenseProvider>().loadDayExpenses(tabProv.selectedDate);
        break;
      case 1: // Produk
        context.read<ProductProvider>().loadProducts();
        break;
      case 2: // Hasil
        final ledgerProv = context.read<CustomerLedgerProvider>();
        final oilProv = context.read<OilStockProvider>();
        final smProv = context.read<StockManagementProvider>();
        final srProv = context.read<StockRemainingProvider>();
        final plProv = context.read<PersonalLedgerProvider>();
        final sdProv = context.read<SaldoDeductionProvider>();
        ledgerProv.loadAll();
        oilProv.loadMonthStocks(tabProv.activeMonth);
        smProv.loadMonthStocks(tabProv.activeMonth);
        srProv.loadMonthStocks(tabProv.activeMonth);
        plProv.loadMonth(tabProv.activeMonth);
        sdProv.loadMonth(tabProv.activeMonth);
        break;
      case 3: // Ringkasan
        context.read<CustomerLedgerProvider>().loadAll();
        break;
      case 4: // Pengaturan
        break;
    }
  }

  Widget _mobileHeader() {
    final prov = context.watch<PrinterProvider>();
    final hasLogo = prov.logoPath.isNotEmpty && File(prov.logoPath).existsSync();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        border: Border(
          bottom: BorderSide(color: AppTheme.line, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (hasLogo)
              ClipRect(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Image.file(
                    File(prov.logoPath),
                    fit: BoxFit.contain,
                  ),
                ),
              )
            else
              const Icon(Icons.store, color: AppTheme.accent, size: 24),
            const Spacer(),
            if (AppTheme.isMobile(context)) ...[
              _buildZoomButton(Icons.zoom_out, _zoomOut),
              const SizedBox(width: 6),
              _buildZoomButton(Icons.zoom_in, _zoomIn),
              const SizedBox(width: 6),
              _buildZoomButton(Icons.center_focus_strong, _resetZoom),
            ],
          ],
        ),
      ),
    );
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
    setState(() {});
  }

  Future<void> _refreshAllData() async {
    final tabProv = context.read<TabProvider>();
    final prodProv = context.read<ProductProvider>();
    final txProv = context.read<TransactionProvider>();
    final expProv = context.read<ExpenseProvider>();
    final ledgerProv = context.read<CustomerLedgerProvider>();
    final oilProv = context.read<OilStockProvider>();
    final smProv = context.read<StockManagementProvider>();
    final srProv = context.read<StockRemainingProvider>();
    final plProv = context.read<PersonalLedgerProvider>();
    final sdProv = context.read<SaldoDeductionProvider>();
    final ringkasanProv = context.read<RingkasanProvider>();

    await prodProv.loadProducts();
    await ledgerProv.loadAll();
    await txProv.loadDaySales(tabProv.selectedDate);
    txProv.initQtyMap(prodProv.products);
    await txProv.loadCustomerNames();
    await expProv.loadDayExpenses(tabProv.selectedDate);
    final range = monthRange(tabProv.activeMonth);
    await expProv.loadMonthExpenses(range[0], range[1]);
    await oilProv.loadMonthStocks(tabProv.activeMonth);
    await smProv.loadMonthStocks(tabProv.activeMonth);
    await srProv.loadMonthStocks(tabProv.activeMonth);
    await plProv.loadMonth(tabProv.activeMonth);
    await sdProv.loadMonth(tabProv.activeMonth);
    await ringkasanProv.calculate(
      activeMonth: tabProv.activeMonth,
      selectedDate: tabProv.selectedDate,
      customerBalances: ledgerProv.balances,
    );
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.line, width: 1),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppTheme.accent, size: 20),
        ),
      ),
    );
  }
}
