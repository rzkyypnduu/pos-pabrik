import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../constants/formatters.dart';
import '../providers/product_provider.dart';
import '../widgets/confirmation_dialog.dart';

class ProdukTab extends StatefulWidget {
  const ProdukTab({super.key});

  @override
  State<ProdukTab> createState() => _ProdukTabState();
}

class _ProdukTabState extends State<ProdukTab> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  int? _editingId;
  final _editPriceControllers = <int, TextEditingController>{};

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    for (final c in _editPriceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prodProv = context.watch<ProductProvider>();
    final isMobile = AppTheme.isMobile(context);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Add Product Form
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tambah Produk',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (isMobile)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nama produk',
                            hintText: 'Contoh: Kabur',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [RupiahInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Harga per kg (Rp)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _addProduct,
                          child: const Text('Tambah'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => prodProv.seedProducts(),
                          child: const Text('Isi Contoh'),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nama produk',
                              hintText: 'Contoh: Kabur',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [RupiahInputFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'Harga per kg (Rp)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _addProduct,
                          child: const Text('Tambah'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => prodProv.seedProducts(),
                          child: const Text('Isi Contoh'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Product List
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Daftar Produk',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                if (prodProv.products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(
                      child: Text(
                        'Belum ada produk. Tambahkan atau pakai tombol Isi Contoh.',
                        style: TextStyle(color: AppTheme.inkSoft),
                      ),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: isMobile ? 0 : MediaQuery.of(context).size.width - (AppTheme.isDesktop(context) ? 280 : 64),
                      ),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                            AppTheme.ink.withValues(alpha: 0.05)),
                        horizontalMargin: 16,
                        columns: const [
                          DataColumn(label: Text('Nama',
                              style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(
                              label: Text('Harga / kg',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                              numeric: true),
                          DataColumn(label: Text('')),
                        ],
                        rows: prodProv.products.map((product) {
                          final isEditing = _editingId == product.id;
                          if (!_editPriceControllers.containsKey(product.id)) {
                            _editPriceControllers[product.id!] =
                                TextEditingController(
                                    text: product.price.toString());
                          }

                          return DataRow(cells: [
                            DataCell(Text(product.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(
                              isEditing
                                  ? SizedBox(
                                      width: 150,
                                      child: TextField(
                                        controller:
                                            _editPriceControllers[product.id],
                                        keyboardType: TextInputType.number,
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                        ),
                                        onSubmitted: (val) => _updatePrice(product.id!, val),
                                      ),
                                    )
                                  : Text(
                                      product.price > 0
                                          ? rupiah(product.price)
                                          : 'belum diatur',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        color: product.price > 0
                                            ? AppTheme.ink
                                            : AppTheme.debt,
                                        fontWeight: product.price > 0
                                            ? FontWeight.w600
                                            : FontWeight.w700,
                                        fontSize: product.price > 0 ? 14 : 12,
                                      ),
                                    ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _editingId = isEditing ? null : product.id;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: AppTheme.accent
                                                .withValues(alpha: 0.4)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                          isEditing ? 'Selesai' : 'Ubah Harga',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.accent)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => ConfirmationDialog.show(
                                      context: context,
                                      title: 'Hapus Produk',
                                      message:
                                          'Hapus produk ${product.name}?',
                                      isDestructive: true,
                                      onConfirm: () => prodProv
                                          .deleteProduct(product.id!),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: AppTheme.debt
                                                .withValues(alpha: 0.4)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Hapus',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.debt)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addProduct() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text;
    final price = int.tryParse(priceText.replaceAll('.', '').replaceAll(',', '')) ?? 0;
    if (name.isNotEmpty) {
      await context.read<ProductProvider>().addProduct(name, price);
      _nameController.clear();
      _priceController.clear();
    }
  }

  void _updatePrice(int id, String val) async {
    final price = int.tryParse(val.replaceAll('.', '').replaceAll(',', '')) ?? 0;
    await context.read<ProductProvider>().updateProductPrice(id, price);
    setState(() {
      _editingId = null;
    });
  }
}
