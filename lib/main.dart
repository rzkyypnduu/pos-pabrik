import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'constants/app_theme.dart';
import 'database/database_helper.dart';
import 'providers/tab_provider.dart';
import 'providers/product_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/oil_stock_provider.dart';
import 'providers/stock_management_provider.dart';
import 'providers/stock_remaining_provider.dart';
import 'providers/customer_ledger_provider.dart';
import 'providers/personal_ledger_provider.dart';
import 'providers/saldo_deduction_provider.dart';
import 'providers/customer_daily_balance_provider.dart';
import 'providers/ringkasan_provider.dart';
import 'providers/printer_provider.dart';
import 'providers/backup_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/pos_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');

  DatabaseHelper.initialize();

  final backupProvider = BackupProvider();
  await backupProvider.loadSavedSettings();

  final syncProvider = SyncProvider();
  await syncProvider.loadConfig();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setMinimumSize(const Size(800, 600));
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
      await windowManager.focus();
    });

    AppLifecycleListener(
      onExitRequested: () async {
        await backupProvider.backupOnClose().timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        );
        return AppExitResponse.exit;
      },
    );
  } else {
    AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused) {
          backupProvider.backupOnClose();
        }
      },
    );
  }

  runApp(PosKrupukApp(
    backupProvider: backupProvider,
    syncProvider: syncProvider,
  ));
}

class PosKrupukApp extends StatelessWidget {
  const PosKrupukApp({
    super.key,
    required this.backupProvider,
    required this.syncProvider,
  });

  final BackupProvider backupProvider;
  final SyncProvider syncProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TabProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => OilStockProvider()),
        ChangeNotifierProvider(create: (_) => StockManagementProvider()),
        ChangeNotifierProvider(create: (_) => StockRemainingProvider()),
        ChangeNotifierProvider(create: (_) => CustomerLedgerProvider()),
        ChangeNotifierProvider(create: (_) => PersonalLedgerProvider()),
        ChangeNotifierProvider(create: (_) => SaldoDeductionProvider()),
        ChangeNotifierProvider(create: (_) => CustomerDailyBalanceProvider()),
        ChangeNotifierProvider(create: (_) => RingkasanProvider()),
        ChangeNotifierProvider(create: (_) => PrinterProvider()),
        ChangeNotifierProvider(create: (_) => backupProvider),
        ChangeNotifierProvider(create: (_) => syncProvider),
      ],
      child: MaterialApp(
        title: 'POS Krupuk',
        theme: AppTheme.theme,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const PosScreen(),
      ),
    );
  }
}
