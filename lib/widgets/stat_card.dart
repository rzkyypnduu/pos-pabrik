import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final Color? valueColor;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.ink : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight ? AppTheme.ink : AppTheme.line,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.04,
                color: highlight ? Colors.white70 : AppTheme.inkSoft,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: valueColor ?? (highlight ? Colors.white : AppTheme.ink),
            ),
          ),
        ],
      ),
    );
  }
}
