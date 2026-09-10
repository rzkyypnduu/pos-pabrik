import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_theme.dart';
import '../constants/formatters.dart';
import '../providers/tab_provider.dart';
import '../providers/ringkasan_provider.dart';
import '../providers/customer_ledger_provider.dart';
import '../widgets/confirmation_dialog.dart';

class RingkasanTab extends StatefulWidget {
  const RingkasanTab({super.key});

  @override
  State<RingkasanTab> createState() => _RingkasanTabState();
}

class _RingkasanTabState extends State<RingkasanTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final tabProv = context.read<TabProvider>();
    final ringProv = context.read<RingkasanProvider>();
    final ledgerProv = context.read<CustomerLedgerProvider>();

    ringProv.calculate(
      activeMonth: tabProv.activeMonth,
      selectedDate: tabProv.selectedDate,
      customerBalances: ledgerProv.balances,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabProv = context.watch<TabProvider>();
    final ringProv = context.watch<RingkasanProvider>();
    final isMobile = AppTheme.isMobile(context);
    final isTablet = AppTheme.isTablet(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Ringkasan ${tabProv.monthLbl}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: isMobile ? 18 : 22,
            ),
          ),
          const SizedBox(height: 16),

          // Monthly Stats Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isMobile ? 1 : (isTablet ? 2 : 4),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: isMobile ? 3.5 : 2.0,
            children: [
              _statBox('Stok Minyak', rupiah(ringProv.totalOil)),
              _statBox('KG Minyak', '${fmtKg(ringProv.totalOilKg)} kg'),
              _statBox('Stok Bahan', rupiah(ringProv.totalStockMgmt)),
              _statBox('Sisa Barang', rupiah(ringProv.totalRemain)),
              _statBox(
                'Hutang Pelanggan',
                rupiah(ringProv.totalHutangPel),
                valueColor: ringProv.totalHutangPel > 0
                    ? AppTheme.debt
                    : AppTheme.paid,
              ),
              _statBox(
                'Hutang Pribadi',
                rupiah(ringProv.totalHutangPri),
                valueColor: ringProv.totalHutangPri > 0
                    ? AppTheme.debt
                    : AppTheme.paid,
              ),
              _statBox('Pengurangan Saldo', rupiahD(ringProv.totalSaldo)),
              _statBox(
                'Total Transaksi',
                '${ringProv.totalMonthlyTransactions}x',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grand Total
          Card(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              child: Row(
                children: [
                  Text(
                    'GRAND TOTAL',
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    rupiah(ringProv.grand),
                    style: TextStyle(
                      fontSize: isMobile ? 22 : 28,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Saldo & TOTAL bulan ini
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'SALDO',
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        rupiah(ringProv.grand - ringProv.totalHutangPri),
                        style: TextStyle(
                          fontSize: isMobile ? 20 : 24,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        rupiahD(
                          ringProv.grand -
                              ringProv.totalHutangPri -
                              ringProv.totalSaldo,
                        ),
                        style: TextStyle(
                          fontSize: isMobile ? 22 : 28,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Total Penjualan
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Penjualan Bulan Ini',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  if (isMobile)
                    Column(
                      children: [
                        _summaryItem(
                          'Total Penjualan',
                          rupiah(ringProv.totalMonthlySales),
                        ),
                        const SizedBox(height: 8),
                        _summaryItem(
                          'Total Diterima',
                          rupiah(ringProv.totalMonthlyPaid),
                        ),
                        const SizedBox(height: 8),
                        _summaryItem(
                          'Total Transaksi',
                          '${ringProv.totalMonthlyTransactions}x',
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _summaryItem(
                            'Total Penjualan',
                            rupiah(ringProv.totalMonthlySales),
                          ),
                        ),
                        Expanded(
                          child: _summaryItem(
                            'Total Diterima',
                            rupiah(ringProv.totalMonthlyPaid),
                          ),
                        ),
                        Expanded(
                          child: _summaryItem(
                            'Total Transaksi',
                            '${ringProv.totalMonthlyTransactions}x',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          _buildDailyChart(ringProv, isMobile),

          const SizedBox(height: 16),
          _buildTopProductsTable(ringProv, isMobile),

          const SizedBox(height: 16),
          _buildTopCustomersTable(ringProv, isMobile),

          const SizedBox(height: 24),
          _buildResetCard(ringProv, tabProv, isMobile),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: valueColor ?? AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildDailyChart(RingkasanProvider ringProv, bool isMobile) {
    if (ringProv.dailySales.isEmpty) return const SizedBox.shrink();
    final dailyData = ringProv.dailySales;
    final maxY = dailyData
        .map((d) => (d['totalSales'] as int?) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Grafik Penjualan Harian',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  maxY: maxY > 0 ? maxY * 1.2 : 100,
                  alignment: BarChartAlignment.spaceAround,
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= 0 && idx < dailyData.length) {
                            final date =
                                dailyData[idx]['date'] as String? ?? '';
                            return Text(
                              date.substring(8),
                              style: const TextStyle(fontSize: 9),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, m) => Text(
                          '${(v / 1000).toStringAsFixed(0)}k',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: dailyData.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: (entry.value['totalSales'] as int).toDouble(),
                          color: AppTheme.accent,
                          width: isMobile ? 6 : 12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductsTable(RingkasanProvider ringProv, bool isMobile) {
    if (ringProv.topProducts.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Produk Terlaris',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FixedColumnWidth(30),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  children: [
                    _tableHeader('#'),
                    _tableHeader('Produk'),
                    _tableHeader('Total'),
                  ],
                ),
                ...ringProv.topProducts.asMap().entries.map(
                  (e) => TableRow(
                    children: [
                      _tableCell('${e.key + 1}'),
                      _tableCell(e.value['name'], bold: true),
                      _tableCell(
                        '${fmtKg(e.value['totalQty'])} kg',
                        align: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCustomersTable(RingkasanProvider ringProv, bool isMobile) {
    if (ringProv.topCustomers.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pelanggan Teraktif',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'paid',
                  label: Text('Dibayar'),
                  icon: Icon(Icons.payments_outlined, size: 16),
                ),
                ButtonSegment(
                  value: 'transactions',
                  label: Text('Transaksi'),
                  icon: Icon(Icons.receipt_long_outlined, size: 16),
                ),
              ],
              selected: {ringProv.topCustomersSortMode},
              onSelectionChanged: (s) {
                ringProv.setTopCustomersSortMode(s.first);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final tableWidth = isMobile
                    ? (constraints.maxWidth >= 300
                          ? constraints.maxWidth
                          : 300.0)
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(30),
                        1: FlexColumnWidth(2),
                        2: FixedColumnWidth(60),
                        3: FlexColumnWidth(1.5),
                      },
                      children: [
                        TableRow(
                          children: [
                            _tableHeader('#'),
                            _tableHeader('Nama'),
                            _tableHeader('Tx'),
                            _tableHeader('Dibayar'),
                          ],
                        ),
                        ...ringProv.topCustomers.asMap().entries.map(
                          (e) => TableRow(
                            children: [
                              _tableCell('${e.key + 1}'),
                              _tableCell(e.value['name'], bold: true),
                              _tableCell(
                                '${e.value['totalTransactions']}x',
                                align: TextAlign.center,
                              ),
                              _tableCell(
                                rupiah(e.value['totalPaid']),
                                align: TextAlign.right,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResetCard(
    RingkasanProvider ringProv,
    TabProvider tabProv,
    bool isMobile,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Manajemen Data',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _resetBtn('Reset Bulan', () async {
                  await ringProv.resetMonth(tabProv.activeMonth);
                  _loadData();
                }),
                _resetBtn('Reset Stok/Saldo', () async {
                  await ringProv.clearOilAndSaldo();
                  _loadData();
                }),
                _resetBtn('Reset Semua', () async {
                  await ringProv.resetAll();
                  _loadData();
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resetBtn(String label, VoidCallback onConfirm) {
    return OutlinedButton(
      onPressed: () => ConfirmationDialog.show(
        context: context,
        title: label,
        message: 'Tindakan ini permanen. Lanjutkan?',
        isDestructive: true,
        onConfirm: onConfirm,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.debt,
        side: const BorderSide(color: AppTheme.debt),
      ),
      child: Text(label),
    );
  }

  Widget _tableHeader(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppTheme.inkSoft,
      ),
    ),
  );
  Widget _tableCell(
    String text, {
    bool bold = false,
    TextAlign align = TextAlign.start,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );
}
