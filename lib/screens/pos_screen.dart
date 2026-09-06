import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/tab_provider.dart';
import '../providers/product_provider.dart';
import '../providers/customer_ledger_provider.dart';
import '../providers/oil_stock_provider.dart';
import '../providers/stock_management_provider.dart';
import '../providers/stock_remaining_provider.dart';
import '../providers/personal_ledger_provider.dart';
import '../providers/saldo_deduction_provider.dart';
import '../providers/printer_provider.dart';
import '../providers/backup_provider.dart';
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
  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final tabProv = context.watch<TabProvider>();
    final isCompact = AppTheme.isCompact(context);

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
                if (isCompact) _mobileHeader(tabProv),
                Expanded(child: tabs[tabProv.currentTab]),
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

  Widget _mobileHeader(TabProvider tabProv) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(color: AppTheme.sidebarBg),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.store, color: AppTheme.sidebarActive, size: 24),
            const SizedBox(width: 8),
            const Text(
              'POS Krupuk',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (AppTheme.isMobile(context))
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                onPressed: () => _reloadTabData(tabProv.currentTab),
              ),
          ],
        ),
      ),
    );
  }
}
