import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../constants/app_theme.dart';
import '../providers/backup_provider.dart';

class WindowControls extends StatefulWidget {
  final Color? backgroundColor;
  final Brightness? brightness;

  const WindowControls({super.key, this.backgroundColor, this.brightness});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  void _checkMaximized() async {
    bool maximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {
        _isMaximized = maximized;
      });
    }
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    final bgColor = widget.backgroundColor ?? AppTheme.bg;
    final brightness = widget.brightness ?? Brightness.light;

    return Container(
      height: 32,
      color: bgColor,
      child: Row(
        children: [
          const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
          WindowCaptionButton.minimize(
            brightness: brightness,
            onPressed: () => windowManager.minimize(),
          ),
          if (_isMaximized)
            WindowCaptionButton.unmaximize(
              brightness: brightness,
              onPressed: () => windowManager.unmaximize(),
            )
          else
            WindowCaptionButton.maximize(
              brightness: brightness,
              onPressed: () => windowManager.maximize(),
            ),
          WindowCaptionButton.close(
            brightness: brightness,
            onPressed: () => _requestClose(),
          ),
        ],
      ),
    );
  }

  Future<void> _requestClose() async {
    if (!context.mounted) {
      await windowManager.destroy();
      return;
    }
    final backup = context.read<BackupProvider>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Text(
              'Tunggu sebentar, sedang backup data...',
              style: TextStyle(fontSize: 13.5),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await backup.backupOnClose().timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
    try {
      await windowManager.destroy();
    } catch (_) {}
  }
}
