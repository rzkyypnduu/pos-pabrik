import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../constants/formatters.dart';

class ProductCard extends StatelessWidget {
  final String name;
  final int price;
  final double qty;
  final int? subtotal;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<double> onQtyChanged;

  const ProductCard({
    super.key,
    required this.name,
    required this.price,
    required this.qty,
    this.subtotal,
    required this.onIncrement,
    required this.onDecrement,
    required this.onQtyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasQty = qty > 0;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: hasQty ? AppTheme.accent : AppTheme.line,
          width: hasQty ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: hasQty ? const Color(0xFFFFF5E8) : Colors.white,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _qtyBtn(Icons.remove, onDecrement),
              const SizedBox(width: 2),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: TextEditingController(
                      text: qty > 0 ? fmtKg(qty) : '',
                    ),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final parsed =
                          double.tryParse(val.replaceAll(',', '.')) ?? 0;
                      onQtyChanged(parsed);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 2),
              _qtyBtn(Icons.add, onIncrement),
            ],
          ),
          if (price > 0 && qty > 0) ...[
            const SizedBox(height: 3),
            Text(
              rupiah((price * qty).round()),
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.inkSoft,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.line, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 14),
      ),
    );
  }
}
