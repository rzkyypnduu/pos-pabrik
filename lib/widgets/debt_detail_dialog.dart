import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../constants/formatters.dart';
import '../providers/customer_ledger_provider.dart';

class DebtDetailDialog extends StatefulWidget {
  final String customerName;

  const DebtDetailDialog({super.key, required this.customerName});

  static Future<void> show(BuildContext context, String name) {
    return showDialog(
      context: context,
      builder: (_) => DebtDetailDialog(customerName: name),
    );
  }

  @override
  State<DebtDetailDialog> createState() => _DebtDetailDialogState();
}

class _DebtDetailDialogState extends State<DebtDetailDialog> {
  late TextEditingController _adjustController;

  @override
  void initState() {
    super.initState();
    final provider = context.read<CustomerLedgerProvider>();
    final current = provider.balanceFor(widget.customerName);
    _adjustController = TextEditingController(text: current.toString());
  }

  @override
  void dispose() {
    _adjustController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CustomerLedgerProvider>(
      builder: (context, provider, _) {
        final detail = provider.debtDetailWithRunningBalance(widget.customerName);
        final entries = detail['entries'] as List;
        final finalBalance = detail['finalBalance'] as int;

        return AlertDialog(
          title: Text('Riwayat Hutang: ${widget.customerName}'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entries.isNotEmpty) ...[
                  SizedBox(
                    height: 300,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Tanggal')),
                          DataColumn(label: Text('Tipe')),
                          DataColumn(label: Text('Jumlah'), numeric: true),
                          DataColumn(label: Text('Saldo'), numeric: true),
                          DataColumn(label: Text('')),
                        ],
                        rows: entries.map<DataRow>((e) {
                          final isTambahan = e['type'] == 'tambah';
                          return DataRow(cells: [
                            DataCell(Text(fmtDate(e['date']),
                                style: const TextStyle(fontSize: 13))),
                            DataCell(Chip(
                              label: Text(
                                isTambahan ? 'Hutang' : 'Bayar',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isTambahan ? AppTheme.debt : AppTheme.paid,
                                ),
                              ),
                              backgroundColor: isTambahan
                                  ? AppTheme.debtBg
                                  : AppTheme.paidBg,
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            )),
                            DataCell(Text(
                              rupiah(e['amount']),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 13),
                            )),
                            DataCell(Text(
                              rupiah(e['running']),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: e['running'] > 0
                                    ? AppTheme.debt
                                    : AppTheme.paid,
                              ),
                            )),
                            DataCell(IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                await provider.deleteLedgerEntry(e['id']);
                              },
                            )),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Belum ada riwayat hutang.'),
                  ),
                const Divider(),
                Row(
                  children: [
                    const Text('Total Hutang: ',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      rupiah(finalBalance),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: finalBalance > 0 ? AppTheme.debt : AppTheme.paid,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _adjustController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Atur manual',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final newTotal =
                            int.tryParse(_adjustController.text) ?? 0;
                        await provider.adjustTotalDebt(
                            widget.customerName, newTotal);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: const Text('Atur'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }
}
