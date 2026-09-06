import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../constants/formatters.dart';
import '../models/product.dart';
import '../providers/transaction_provider.dart';
import '../providers/product_provider.dart';
import '../providers/customer_ledger_provider.dart';
import '../widgets/window_controls.dart';

class TransaksiFormScreen extends StatefulWidget {
  final String selectedDate;

  const TransaksiFormScreen({super.key, required this.selectedDate});

  @override
  State<TransaksiFormScreen> createState() => _TransaksiFormScreenState();
}

class _TransaksiFormScreenState extends State<TransaksiFormScreen> {
  final _nameController = TextEditingController();
  final _paidController = TextEditingController();
  final _noteController = TextEditingController();
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, FocusNode> _qtyFocusNodes = {};
  int? _selectedProductId;
  final _listScrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};
  final _productFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    final txProv = context.read<TransactionProvider>();
    txProv.loadCustomerNames();
    _nameController.text = txProv.txName;
    _noteController.text = txProv.txNote;
    if (txProv.txPaid.isNotEmpty) {
      _paidController.text = txProv.txPaid;
    }
    if (!txProv.isPaymentFlow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNameDialog();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusProducts());
    }
  }

  void _focusProducts() {
    final products = context.read<ProductProvider>().products;
    if (products.isNotEmpty) {
      setState(() => _selectedProductId = products.first.id);
      _focusQtyOf(products.first.id);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _productFocusNode.requestFocus();
      });
    }
  }

  void _focusQtyOf(int? productId) {
    if (productId == null) return;
    final fn = _qtyFocusNodes[productId.toString()];
    if (fn == null) return;
    _focusQtyNow(productId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusQtyNow(productId);
    });
  }

  void _focusQtyNow(int? productId) {
    if (productId == null) return;
    final fn = _qtyFocusNodes[productId.toString()];
    final c = _qtyControllers[productId.toString()];
    if (fn != null) {
      fn.requestFocus();
      if (c != null && c.text.isNotEmpty) {
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _nameController.dispose();
    _paidController.dispose();
    _noteController.dispose();
    for (var c in _qtyControllers.values) {
      c.dispose();
    }
    for (var f in _qtyFocusNodes.values) {
      f.dispose();
    }
    _productFocusNode.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _showNameDialog() {
    final txProv = context.read<TransactionProvider>();
    if (txProv.customerNames.isEmpty) {
      txProv.loadCustomerNames();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Nama Pelanggan',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<String>.empty();
                  }
                  final typed = textEditingValue.text.trim().toLowerCase();
                  final matches = txProv.customerNames.where(
                    (name) => name.toLowerCase().contains(typed),
                  );
                  final typedName = textEditingValue.text.trim();
                  if (typedName.isNotEmpty &&
                      !matches.any((n) => n.toLowerCase() == typed)) {
                    return [typedName, ...matches];
                  }
                  return matches;
                },
                onSelected: (String selection) {
                  _nameController.text = selection;
                  txProv.setProductName(selection);
                  Navigator.of(ctx).pop();
                  setState(() {});
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _focusProducts(),
                  );
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) {
                      controller.text = _nameController.text;
                      controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: controller.text.length),
                      );
                      controller.addListener(() {
                        _nameController.text = controller.text;
                      });
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Ketik nama pelanggan...',
                          prefixIcon: Icon(Icons.person),
                        ),
                        onSubmitted: (val) {
                          final name = val.trim();
                          if (name.isNotEmpty) {
                            _nameController.text = name;
                            txProv.setProductName(name);
                            Navigator.of(ctx).pop();
                            setState(() {});
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _focusProducts(),
                            );
                          }
                        },
                      );
                    },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(false);
            },
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = _nameController.text.trim();
              if (name.isNotEmpty) {
                txProv.setProductName(name);
                Navigator.of(ctx).pop();
                setState(() {});
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _focusProducts(),
                );
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txProv = context.watch<TransactionProvider>();
    final isEditing = txProv.editingSaleId != null;
    final isDesktop = AppTheme.isDesktop(context);
    final isMobile = AppTheme.isMobile(context);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          if (!isMobile)
            const WindowControls(
              backgroundColor: AppTheme.ink,
              brightness: Brightness.dark,
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: AppTheme.ink),
            child: SafeArea(
              bottom: false,
              top: isMobile,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      txProv.resetForm();
                      Navigator.of(context).pop(false);
                    },
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      isEditing ? 'Bayar: ${txProv.txName}' : 'Transaksi Baru',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child:
                (isDesktop ||
                    (AppTheme.isHandheld(context) &&
                        MediaQuery.of(context).size.width >= 700))
                ? _wideLayout()
                : _narrowLayout(),
          ),
        ],
      ),
    );
  }

  Widget _wideLayout() {
    final txProv = context.watch<TransactionProvider>();
    final prodProv = context.watch<ProductProvider>();
    final ledgerProv = context.watch<CustomerLedgerProvider>();
    final List<Product> products = prodProv.products;
    final rawTotal = txProv.txRawTotal(products);
    final roundedTotal = txProv.txRoundedTotal(products);
    final totalKg = txProv.txQty.values.fold<double>(0, (a, b) => a + b);
    final customerBalance = _nameController.text.isNotEmpty
        ? ledgerProv.balanceFor(_nameController.text)
        : 0;
    final isEditing = txProv.editingSaleId != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _productList(products, txProv)),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: _paymentSummary(
            txProv,
            products,
            rawTotal,
            roundedTotal,
            totalKg,
            customerBalance,
            isEditing,
          ),
        ),
      ],
    );
  }

  Widget _narrowLayout() {
    final txProv = context.watch<TransactionProvider>();
    final prodProv = context.watch<ProductProvider>();
    final ledgerProv = context.watch<CustomerLedgerProvider>();
    final List<Product> products = prodProv.products;
    final rawTotal = txProv.txRawTotal(products);
    final roundedTotal = txProv.txRoundedTotal(products);
    final totalKg = txProv.txQty.values.fold<double>(0, (a, b) => a + b);
    final customerBalance = _nameController.text.isNotEmpty
        ? ledgerProv.balanceFor(_nameController.text)
        : 0;
    final isEditing = txProv.editingSaleId != null;

    return Column(
      children: [
        Expanded(child: _productList(products, txProv)),
        const Divider(height: 1),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: _paymentSummary(
            txProv,
            products,
            rawTotal,
            roundedTotal,
            totalKg,
            customerBalance,
            isEditing,
          ),
        ),
      ],
    );
  }

  Widget _productList(List<Product> products, TransactionProvider txProv) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.ink.withValues(alpha: 0.05),
              border: const Border(
                bottom: BorderSide(color: AppTheme.line, width: 1.5),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 7,
                  child: Text(
                    'PRODUK',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkSoft,
                      letterSpacing: 0.05,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    'QTY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkSoft,
                      letterSpacing: 0.05,
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    'SUBTOTAL',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkSoft,
                      letterSpacing: 0.05,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: products.isEmpty
                ? const Center(
                    child: Text(
                      'Tambahkan produk dulu di tab Produk.',
                      style: TextStyle(color: AppTheme.inkSoft, fontSize: 13),
                    ),
                  )
                : Focus(
                    focusNode: _productFocusNode,
                    onKeyEvent: (node, event) =>
                        _handleProductKey(node, event, products, txProv),
                    child: ListView.builder(
                      controller: _listScrollController,
                      padding: EdgeInsets.zero,
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final qty = txProv.txQty[product.id] ?? 0;
                        return Column(
                          children: [
                            _productRow(product, qty, txProv, products),
                            const Divider(height: 1),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _productRow(
    Product product,
    double qty,
    TransactionProvider txProv,
    List<Product> products,
  ) {
    final hasQty = qty > 0;
    final subtotal = (product.price * qty).round();
    final isSelected = product.id == _selectedProductId;

    if (!_qtyControllers.containsKey(product.id.toString())) {
      _qtyControllers[product.id.toString()] = TextEditingController(
        text: qty > 0
            ? (qty % 1 == 0
                  ? qty.toInt().toString()
                  : qty.toString().replaceAll('.', ','))
            : '',
      );
      final fn = FocusNode();
      fn.addListener(() {
        if (fn.hasFocus) {
          setState(() => _selectedProductId = product.id);
          final c = _qtyControllers[product.id.toString()];
          if (c != null && c.text.isNotEmpty) {
            c.selection = TextSelection(
              baseOffset: 0,
              extentOffset: c.text.length,
            );
          }
        }
      });
      _qtyFocusNodes[product.id.toString()] = fn;
    }
    return InkWell(
      key: _rowKeys.putIfAbsent(product.id!, () => GlobalKey()),
      onTap: () {
        setState(() => _selectedProductId = product.id);
        _focusQtyOf(product.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: hasQty ? AppTheme.accent.withValues(alpha: 0.05) : null,
          border: isSelected
              ? Border.all(color: AppTheme.accent, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${rupiah(product.price)}/kg',
                    style: TextStyle(fontSize: 11, color: AppTheme.inkSoft),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _qtyBtn(Icons.remove, () {
                    txProv.decrementQty(product.id!);
                    _updateQtyController(
                      product.id!.toString(),
                      txProv.txQty[product.id!] ?? 0,
                    );
                    _focusQtyOf(product.id);
                  }),
                  Container(
                    width: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    child: TextField(
                      controller: _qtyControllers[product.id.toString()],
                      focusNode: _qtyFocusNodes[product.id.toString()],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.all(4),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onTap: () => _focusQtyOf(product.id),
                      onChanged: (val) {
                        if (val.isEmpty) {
                          txProv.setQty(product.id!, 0);
                          return;
                        }
                        final parsed =
                            double.tryParse(val.replaceAll(',', '.')) ?? 0;
                        txProv.setQty(product.id!, parsed);
                      },
                    ),
                  ),
                  _qtyBtn(Icons.add, () {
                    txProv.incrementQty(product.id!);
                    _updateQtyController(
                      product.id!.toString(),
                      txProv.txQty[product.id!] ?? 0,
                    );
                    _focusQtyOf(product.id);
                  }),
                ],
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                hasQty ? rupiah(subtotal) : '-',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hasQty ? AppTheme.ink : AppTheme.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleProductKey(
    FocusNode node,
    KeyEvent event,
    List<Product> products,
    TransactionProvider txProv,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (products.isEmpty) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && _isTextField(focused)) {
      return KeyEventResult.ignored;
    }

    int currentIndex = 0;
    if (_selectedProductId != null) {
      final idx = products.indexWhere((p) => p.id == _selectedProductId);
      if (idx >= 0) currentIndex = idx;
    }
    final product = products[currentIndex];
    if (key == LogicalKeyboardKey.arrowRight) {
      txProv.incrementQty(product.id!);
      _updateQtyController(
        product.id!.toString(),
        txProv.txQty[product.id!] ?? 0,
      );
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      txProv.decrementQty(product.id!);
      _updateQtyController(
        product.id!.toString(),
        txProv.txQty[product.id!] ?? 0,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return false;
    }
    final pf = FocusManager.instance.primaryFocus;
    final inQty = pf != null && _qtyFocusNodes.containsValue(pf);
    final inList = _productFocusNode.hasFocus;
    if (!inQty && !inList) return false;

    final products = context.read<ProductProvider>().products;
    if (products.isEmpty) return true;

    int currentIndex = 0;
    if (_selectedProductId != null) {
      final idx = products.indexWhere((p) => p.id == _selectedProductId);
      if (idx >= 0) currentIndex = idx;
    }
    final next = key == LogicalKeyboardKey.arrowDown
        ? currentIndex + 1
        : currentIndex - 1;
    if (next >= 0 && next < products.length) {
      final target = products[next];
      setState(() => _selectedProductId = target.id);
      _ensureSelectedVisible();
      _focusQtyOf(target.id);
    }
    return true;
  }

  bool _isTextField(BuildContext context) {
    final widget = context.widget;
    return widget is TextField || widget is EditableText;
  }

  void _ensureSelectedVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[_selectedProductId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  void _updateQtyController(String? id, double qty) {
    if (id == null) return;
    final controller = _qtyControllers[id];
    if (controller != null) {
      final text = qty > 0
          ? (qty % 1 == 0
                ? qty.toInt().toString()
                : qty.toString().replaceAll('.', ','))
          : '';
      if (controller.text != text) {
        controller.text = text;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
      }
    }
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 14),
      ),
    );
  }

  Widget _paymentSummary(
    TransactionProvider txProv,
    List<Product> products,
    int rawTotal,
    int roundedTotal,
    double totalKg,
    int customerBalance,
    bool isEditing,
  ) {
    final diff = txProv.txDiff(products);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _showNameDialog,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'PELANGGAN',
                  labelStyle: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _debtPill(customerBalance),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 16, color: AppTheme.inkSoft),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                child: Text(
                  _nameController.text.isNotEmpty
                      ? _nameController.text
                      : 'Ketuk isi nama...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: _nameController.text.isNotEmpty
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: _nameController.text.isNotEmpty
                        ? AppTheme.ink
                        : AppTheme.inkSoft,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _infoBox('TOTAL KG', '${fmtKg(totalKg)} kg')),
                const SizedBox(width: 8),
                Expanded(child: _infoBox('BELANJA', rupiah(rawTotal))),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accent,
                    AppTheme.accent.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TAGIHAN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    rupiah(roundedTotal),
                    style: const TextStyle(
                      fontSize: 26,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'DIBAYAR (Rp)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _paidController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [RupiahInputFormatter()],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      hintText: '0',
                      isDense: true,
                    ),
                    onChanged: (val) => txProv.setTxPaid(val),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    txProv.fillLunas(products);
                    _paidController.text = roundedTotal.toString();
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Pas'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _statusBox(diff, txProv.txPaidTouched),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Catatan',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (val) => txProv.setTxNote(val),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (txProv.txName.isEmpty || totalKg <= 0)
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        await txProv.saveSale(
                          date: widget.selectedDate,
                          name: txProv.txName,
                          products: products,
                          note: txProv.txNote,
                          isEditing: isEditing,
                        );
                        if (mounted) {
                          navigator.pop(true);
                        }
                      },
                child: Text(
                  isEditing ? 'Simpan Pembayaran' : 'Simpan Transaksi',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBox(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
    decoration: BoxDecoration(
      color: Colors.grey[50],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: AppTheme.inkSoft,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
      ],
    ),
  );

  Widget _debtPill(int balance) {
    Color bgColor, textColor;
    String text;
    if (balance > 0) {
      bgColor = AppTheme.debtBg;
      textColor = AppTheme.debt;
      text = 'Hutang ${rupiah(balance)}';
    } else if (balance < 0) {
      bgColor = AppTheme.paidBg;
      textColor = AppTheme.paid;
      text = 'Deposit ${rupiah(-balance)}';
    } else {
      bgColor = Colors.grey[200]!;
      textColor = AppTheme.ink;
      text = 'Lunas';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _statusBox(int diff, bool paidTouched) {
    Color bgColor, textColor;
    String text;
    if (!paidTouched) {
      bgColor = AppTheme.debtBg;
      textColor = AppTheme.debt;
      text = 'Belum dibayar';
    } else if (diff > 0) {
      bgColor = AppTheme.debtBg;
      textColor = AppTheme.debt;
      text = 'Kurang ${rupiah(diff)}';
    } else if (diff < 0) {
      bgColor = AppTheme.paidBg;
      textColor = AppTheme.paid;
      text = 'Lebih ${rupiah(-diff)}';
    } else {
      bgColor = AppTheme.paidBg;
      textColor = AppTheme.paid;
      text = 'Lunas';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}
