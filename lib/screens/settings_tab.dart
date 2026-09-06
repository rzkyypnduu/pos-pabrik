import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../constants/app_theme.dart';
import '../constants/formatters.dart';
import '../database/database_helper.dart';
import '../providers/printer_provider.dart';
import '../providers/backup_provider.dart';
import '../providers/tab_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/oil_stock_provider.dart';
import '../providers/stock_management_provider.dart';
import '../providers/stock_remaining_provider.dart';
import '../providers/customer_ledger_provider.dart';
import '../providers/personal_ledger_provider.dart';
import '../providers/saldo_deduction_provider.dart';
import '../providers/ringkasan_provider.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController _storeNameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _sloganCtrl;
  late TextEditingController _footerCtrl;
  late final TextEditingController _deviceNameCtrl;
  final _deviceNameFocus = FocusNode();
  final _picker = ImagePicker();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final prov = context.read<PrinterProvider>();
    _storeNameCtrl = TextEditingController(text: prov.storeName);
    _addressCtrl = TextEditingController(text: prov.shopAddress);
    _phoneCtrl = TextEditingController(text: prov.phone);
    _sloganCtrl = TextEditingController(text: prov.slogan);
    _footerCtrl = TextEditingController(text: prov.footer);
    _deviceNameCtrl = TextEditingController(
      text: context.read<BackupProvider>().deviceName,
    );
  }

  void _syncFromProvider(PrinterProvider prov) {
    if (!_loaded && prov.storeName.isNotEmpty) {
      _loaded = true;
      _storeNameCtrl.text = prov.storeName;
      _addressCtrl.text = prov.shopAddress;
      _phoneCtrl.text = prov.phone;
      _sloganCtrl.text = prov.slogan;
      _footerCtrl.text = prov.footer;
    }
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _sloganCtrl.dispose();
    _footerCtrl.dispose();
    _deviceNameCtrl.dispose();
    _deviceNameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<PrinterProvider>();
    final isMobile = AppTheme.isMobile(context);
    _syncFromProvider(prov);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('PRINTER'),
          const SizedBox(height: 10),
          if (Platform.isWindows) _windowsPrinterCard(prov, isMobile),
          if (Platform.isAndroid) _bluetoothPrinterCard(prov, isMobile),
          const SizedBox(height: 20),

          _sectionHeader('INFO TOKO & STRUK'),
          const SizedBox(height: 10),
          _infoCard(prov, isMobile),
          const SizedBox(height: 20),

          _sectionHeader('BACKUP OTOMATIS'),
          const SizedBox(height: 10),
          _backupCard(context, isMobile),
          const SizedBox(height: 20),

          _sectionHeader('DATA'),
          const SizedBox(height: 10),
          _dataCard(isMobile),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.inkSoft,
        letterSpacing: 1,
      ),
    );
  }

  Widget _windowsPrinterCard(PrinterProvider prov, bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.line, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: prov.selectedWindowsPrinter.isNotEmpty
                  ? AppTheme.paid.withValues(alpha: 0.08)
                  : AppTheme.debt.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.print,
                  color: prov.selectedWindowsPrinter.isNotEmpty
                      ? AppTheme.paid
                      : AppTheme.debt,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prov.selectedWindowsPrinter.isNotEmpty
                            ? prov.selectedWindowsPrinter
                            : 'Tidak ada printer dipilih',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: prov.selectedWindowsPrinter.isNotEmpty
                              ? AppTheme.paid
                              : AppTheme.debt,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        prov.selectedWindowsPrinter.isNotEmpty
                            ? 'USB - Siap cetak'
                            : 'Pilih printer USB',
                        style: TextStyle(
                          fontSize: 12,
                          color: prov.selectedWindowsPrinter.isNotEmpty
                              ? AppTheme.paid
                              : AppTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: isMobile ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: prov.isLoadingWindowsPrinters
                        ? null
                        : () => prov.loadWindowsPrinters(),
                    icon: prov.isLoadingWindowsPrinters
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.usb, size: 18),
                    label: Text(
                      prov.isLoadingWindowsPrinters
                          ? 'Memuat...'
                          : 'Cari Printer USB',
                    ),
                  ),
                ),
                if (prov.selectedWindowsPrinter.isNotEmpty)
                  SizedBox(
                    width: isMobile ? double.infinity : null,
                    child: OutlinedButton.icon(
                      onPressed: () => _testPrint(context),
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Test Print'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.paid,
                        side: const BorderSide(color: AppTheme.paid),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (prov.windowsPrinters.isNotEmpty)
            ...prov.windowsPrinters.map(
              (name) => ListTile(
                leading: Icon(
                  Icons.print,
                  color: name == prov.selectedWindowsPrinter
                      ? AppTheme.accent
                      : AppTheme.inkSoft,
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    fontWeight: name == prov.selectedWindowsPrinter
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: name == prov.selectedWindowsPrinter
                    ? const Icon(
                        Icons.check_circle,
                        color: AppTheme.paid,
                        size: 20,
                      )
                    : const Icon(Icons.chevron_right, size: 20),
                onTap: () => prov.selectWindowsPrinter(name),
              ),
            ),
          SwitchListTile(
            title: const Text(
              'Auto Print Struk',
              style: TextStyle(fontSize: 14),
            ),
            subtitle: const Text(
              'Cetak otomatis setelah pembayaran',
              style: TextStyle(fontSize: 12),
            ),
            value: prov.autoPrint,
            onChanged: (v) => prov.autoPrint = v,
            activeThumbColor: AppTheme.accent,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ),
    );
  }

  Widget _bluetoothPrinterCard(PrinterProvider prov, bool isMobile) {
    final isConnected = prov.connectionStatus == 'connected';
    final isChecking = prov.connectionStatus == 'checking';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.line, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isConnected
                  ? AppTheme.paid.withValues(alpha: 0.08)
                  : AppTheme.debt.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: isConnected ? AppTheme.paid : AppTheme.debt,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prov.selectedBtName.isNotEmpty
                            ? prov.selectedBtName
                            : 'Tidak ada printer',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isConnected ? AppTheme.paid : AppTheme.debt,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isConnected
                            ? 'Terhubung'
                            : isChecking
                            ? 'Mengecek...'
                            : 'Belum terhubung',
                        style: TextStyle(
                          fontSize: 12,
                          color: isConnected ? AppTheme.paid : AppTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: isMobile ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: () => _showBtDevicePicker(context),
                    icon: const Icon(Icons.bluetooth_searching, size: 18),
                    label: const Text('Pilih Printer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: const BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
                if (isConnected)
                  SizedBox(
                    width: isMobile ? double.infinity : null,
                    child: OutlinedButton.icon(
                      onPressed: () => _testPrint(context),
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Test Print'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.paid,
                        side: const BorderSide(color: AppTheme.paid),
                      ),
                    ),
                  ),
                if (prov.selectedBtAddress.isNotEmpty && !isConnected)
                  SizedBox(
                    width: isMobile ? double.infinity : null,
                    child: OutlinedButton.icon(
                      onPressed: () => prov.loadSavedBtDevice(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Hubungkan'),
                    ),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text(
              'Auto Print Struk',
              style: TextStyle(fontSize: 14),
            ),
            subtitle: const Text(
              'Cetak otomatis setelah pembayaran',
              style: TextStyle(fontSize: 12),
            ),
            value: prov.autoPrint,
            onChanged: (v) => prov.autoPrint = v,
            activeThumbColor: AppTheme.accent,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(PrinterProvider prov, bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.line, width: 1.5),
      ),
      child: Column(
        children: [
          _field('Nama Toko', _storeNameCtrl, (v) => prov.storeName = v),
          const SizedBox(height: 12),
          _field('Alamat', _addressCtrl, (v) => prov.shopAddress = v),
          const SizedBox(height: 12),
          _field('No. Telp', _phoneCtrl, (v) => prov.phone = v),
          const SizedBox(height: 12),
          _field('Slogan Penutup', _sloganCtrl, (v) => prov.slogan = v),
          const SizedBox(height: 12),
          _field('Footer Struk', _footerCtrl, (v) => prov.footer = v),
          const SizedBox(height: 16),
          Container(height: 1, color: AppTheme.line),
          const SizedBox(height: 16),
          if (prov.logoPath.isNotEmpty && File(prov.logoPath).existsSync())
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(prov.logoPath),
                  height: 60,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickLogo(context),
                  icon: const Icon(Icons.image, size: 18),
                  label: Text(
                    prov.logoPath.isNotEmpty ? 'Ganti Logo' : 'Pilih Logo',
                  ),
                ),
              ),
              if (prov.logoPath.isNotEmpty) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => prov.logoPath = '',
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.debt,
                    side: const BorderSide(color: AppTheme.debt),
                  ),
                  child: const Text('Hapus'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: AppTheme.line),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showReceiptPreview(context, prov),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text('Preview Struk'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataCard(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cadangkan (Export) dan Pulihkan (Import) database aplikasi untuk memindahkan data antar perangkat.',
            style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: isMobile ? double.infinity : null,
                child: OutlinedButton.icon(
                  onPressed: () => _exportData(context),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Export Data'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: const BorderSide(color: AppTheme.accent),
                  ),
                ),
              ),
              SizedBox(
                width: isMobile ? double.infinity : null,
                child: OutlinedButton.icon(
                  onPressed: () => _importData(context),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Load / Impor Data'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.paid,
                    side: const BorderSide(color: AppTheme.paid),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backupCard(BuildContext context, bool isMobile) {
    final prov = context.watch<BackupProvider>();
    if (!_deviceNameFocus.hasFocus && _deviceNameCtrl.text != prov.deviceName) {
      _deviceNameCtrl.text = prov.deviceName;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            title: const Text(
              'Aktifkan Backup Otomatis',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Backup database otomatis setiap hari & saat aplikasi ditutup',
              style: TextStyle(fontSize: 12),
            ),
            value: prov.enabled,
            onChanged: (v) => prov.enabled = v,
            activeThumbColor: AppTheme.accent,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _deviceNameCtrl,
            focusNode: _deviceNameFocus,
            decoration: const InputDecoration(
              labelText: 'Nama Perangkat',
              labelStyle: TextStyle(fontSize: 13),
              prefixIcon: Icon(Icons.computer, size: 18),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (v) => prov.deviceName = v,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Text(
                    prov.destinationPath.isNotEmpty
                        ? prov.destinationPath
                        : 'Belum ada folder dipilih',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: prov.destinationPath.isNotEmpty
                          ? AppTheme.ink
                          : AppTheme.inkSoft,
                      fontWeight: prov.destinationPath.isNotEmpty
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickBackupFolder(context),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Pilih Folder'),
              ),
            ],
          ),
          if (prov.destinationPath.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Akan disimpan di: ${prov.effectiveBackupFolder}',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tips: pilih folder Google Drive (mis. My Drive\\POS Backup) agar backup terupload otomatis ke cloud.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  width: isMobile ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed:
                        prov.isBackingUp || prov.effectiveBackupFolder.isEmpty
                        ? null
                        : () => _backupNow(context),
                    icon: prov.isBackingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup, size: 18),
                    label: Text(
                      prov.isBackingUp ? 'Menyimpan...' : 'Backup Sekarang',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: const BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (prov.lastStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              prov.lastStatus,
              style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'File backup disimpan ${prov.retentionDays} hari terakhir lalu dihapus otomatis.',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBackupFolder(BuildContext context) async {
    final prov = context.read<BackupProvider>();
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pilih Folder Tujuan Backup',
    );
    if (path == null) return;
    prov.destinationPath = path;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Folder backup disimpan'),
        backgroundColor: AppTheme.paid,
      ),
    );
  }

  Future<void> _backupNow(BuildContext context) async {
    final prov = context.read<BackupProvider>();
    final ok = await prov.backupNow();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Backup berhasil disimpan' : 'Backup gagal'),
        backgroundColor: ok ? AppTheme.paid : AppTheme.debt,
      ),
    );
  }

  Future<void> _exportData(BuildContext context) async {
    try {
      final defaultName =
          'pos_krupuk_backup_${DateTime.now().millisecondsSinceEpoch}.db';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Cadangan Database',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (result == null) return;
      await DatabaseHelper.instance.exportDatabase(result);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data berhasil di-export'),
          backgroundColor: AppTheme.paid,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export gagal: $e'),
          backgroundColor: AppTheme.debt,
        ),
      );
    }
  }

  Future<void> _importData(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pilih File Cadangan Database',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (result == null || result.files.single.path == null) return;
      if (!context.mounted) return;
      final src = result.files.single.path!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import Data'),
          content: const Text(
            'Import akan MENGGANTI seluruh data yang ada saat ini dengan data dari file cadangan. Lanjutkan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.debt),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await DatabaseHelper.instance.importDatabase(src);
      if (!context.mounted) return;
      await _reloadAllData();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Import berhasil. Data telah dipulihkan.'),
          backgroundColor: AppTheme.paid,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import gagal: $e'),
          backgroundColor: AppTheme.debt,
        ),
      );
    }
  }

  Future<void> _reloadAllData() async {
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
    await expProv.loadMonthExpenses(
      monthRange(tabProv.activeMonth)[0],
      monthRange(tabProv.activeMonth)[1],
    );
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
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    Function(String) onChanged,
  ) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      style: const TextStyle(fontSize: 14),
      onChanged: onChanged,
    );
  }

  Future<void> _pickLogo(BuildContext context) async {
    final prov = context.read<PrinterProvider>();
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) prov.logoPath = picked.path;
  }

  Future<void> _testPrint(BuildContext context) async {
    final prov = context.read<PrinterProvider>();
    final result = await prov.printTest();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result ? 'Test print berhasil' : 'Test print gagal'),
        backgroundColor: result ? AppTheme.paid : AppTheme.debt,
      ),
    );
  }

  void _showReceiptPreview(BuildContext context, PrinterProvider prov) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ReceiptPreviewSheet(prov: prov),
    );
  }

  void _showBtDevicePicker(BuildContext context) async {
    final prov = context.read<PrinterProvider>();
    final hasPermission = await prov.checkAndRequestPermissions();
    if (!hasPermission && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Izin Bluetooth ditolak')));
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: prov,
        child: const _BtDevicePickerSheet(),
      ),
    );
  }
}

class _ReceiptPreviewSheet extends StatelessWidget {
  final PrinterProvider prov;
  const _ReceiptPreviewSheet({required this.prov});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Preview Struk',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    child: _buildReceipt(prov),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReceipt(PrinterProvider prov) {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prov.logoPath.isNotEmpty && File(prov.logoPath).existsSync())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRect(
              child: Align(
                alignment: Alignment.center,
                heightFactor: 0.7,
                child: Image.file(
                  File(prov.logoPath),
                  height: 60,
                  width: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        Text(
          prov.storeName.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        if (prov.shopAddress.isNotEmpty)
          Text(
            prov.shopAddress,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        if (prov.phone.isNotEmpty)
          Text(
            'Telp: ${prov.phone}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        const SizedBox(height: 4),
        const Text(
          '--------------------------------',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: AppTheme.inkSoft),
        ),
        Text(
          '$dateStr $timeStr',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10),
        ),
        const Text(
          '--------------------------------',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 8),
        _receiptItem('Krupuk Udang', '2 kg x 25.000', '50.000'),
        _receiptItem('Krupuk Ikan', '1 kg x 30.000', '30.000'),
        _receiptItem('Kerupuk Putih', '3 kg x 15.000', '45.000'),
        const SizedBox(height: 4),
        const Text(
          '--------------------------------',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 4),
        _receiptRow('TOTAL', 'Rp125.000', bold: true),
        _receiptRow('BAYAR', 'Rp150.000'),
        _receiptRow('KEMBALI', 'Rp25.000'),
        const Text(
          '--------------------------------',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 8),
        Text(
          prov.slogan.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        if (prov.footer.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            prov.footer,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9),
          ),
        ],
      ],
    );
  }

  Widget _receiptItem(String name, String detail, String subtotal) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(detail, style: const TextStyle(fontSize: 11)),
            Text(
              subtotal,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _receiptRow(String label, String value, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _BtDevicePickerSheet extends StatefulWidget {
  const _BtDevicePickerSheet();
  @override
  State<_BtDevicePickerSheet> createState() => _BtDevicePickerSheetState();
}

class _BtDevicePickerSheetState extends State<_BtDevicePickerSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterProvider>().loadBondedDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<PrinterProvider>();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pilih Printer Bluetooth',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Pastikan printer sudah dipasangkan di pengaturan Bluetooth',
                style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: prov.isScanning
                          ? null
                          : () => prov.scanDevices(),
                      icon: prov.isScanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search, size: 18),
                      label: Text(
                        prov.isScanning ? 'Mencari...' : 'Cari Perangkat',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: prov.loadBondedDevices,
                      icon: const Icon(Icons.bluetooth, size: 18),
                      label: const Text('Terpasang'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: prov.isLoadingDevices
                    ? const Center(child: CircularProgressIndicator())
                    : prov.btDevices.isEmpty
                    ? Center(
                        child: Text(
                          'Tidak ada perangkat ditemukan',
                          style: TextStyle(color: AppTheme.inkSoft),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: prov.btDevices.length,
                        itemBuilder: (ctx, i) {
                          final device = prov.btDevices[i];
                          final isSaved =
                              device.address == prov.selectedBtAddress;
                          return ListTile(
                            leading: Icon(
                              Icons.bluetooth,
                              color: isSaved
                                  ? AppTheme.accent
                                  : AppTheme.inkSoft,
                            ),
                            title: Text(
                              device.name ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: isSaved
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              device.address,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: isSaved
                                ? const Icon(
                                    Icons.check_circle,
                                    color: AppTheme.paid,
                                    size: 20,
                                  )
                                : const Icon(Icons.chevron_right, size: 20),
                            onTap: () => _connectBt(ctx, device),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _connectBt(BuildContext context, BtcDevice device) async {
    final prov = context.read<PrinterProvider>();
    final result = await prov.connectBt(
      device.address,
      device.name ?? 'Unknown',
    );
    if (!context.mounted) return;
    if (result) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terhubung ke ${device.name}'),
          backgroundColor: AppTheme.paid,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal menghubungkan'),
          backgroundColor: AppTheme.debt,
        ),
      );
    }
  }
}
