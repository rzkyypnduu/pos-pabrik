import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final VoidCallback onConfirm;
  final bool isDestructive;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = 'Ya',
    this.cancelText = 'Batal',
    required this.onConfirm,
    this.isDestructive = false,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => ConfirmationDialog(
        title: title,
        message: message,
        onConfirm: () {
          Navigator.of(ctx).pop();
          onConfirm();
        },
        isDestructive: isDestructive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(cancelText),
        ),
        ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive ? AppTheme.debt : AppTheme.accent,
          ),
          child: Text(confirmText),
        ),
      ],
    );
  }
}
