import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../constants/app_theme.dart';
import '../providers/printer_provider.dart';

class AppSidebar extends StatefulWidget {
  final int currentTab;
  final ValueChanged<int> onTabChanged;

  const AppSidebar({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _isHovered = false;

  Widget _buildLogoContent() {
    final prov = context.watch<PrinterProvider>();
    final hasLogo = prov.logoPath.isNotEmpty && File(prov.logoPath).existsSync();
    final Widget logo = hasLogo
        ? ClipRect(
            child: SizedBox(
              width: 24,
              height: 24,
              child: Image.file(
                File(prov.logoPath),
                fit: BoxFit.contain,
              ),
            ),
          )
        : const Icon(Icons.store, color: AppTheme.sidebarActive, size: 24);
    final content = _isHovered
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              logo,
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  prov.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          )
        : Center(child: logo);
    if (Platform.isWindows) {
      return DragToMoveArea(child: content);
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final navTabs = [
      {'icon': Icons.point_of_sale, 'label': 'Transaksi'},
      {'icon': Icons.inventory_2, 'label': 'Produk'},
      {'icon': Icons.assessment, 'label': 'Hasil'},
      {'icon': Icons.summarize, 'label': 'Ringkasan'},
    ];

    final sidebarWidth = _isHovered ? 220.0 : 48.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: sidebarWidth,
        child: ClipRect(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: sidebarWidth,
            decoration: const BoxDecoration(color: AppTheme.sidebarBg),
            child: Column(
              children: [
                // ── Logo ──
                SizedBox(
                  height: 60,
                  child: _buildLogoContent(),
                ),
                const Divider(color: AppTheme.line, height: 1),

                // ── Nav Items ──
                ...List.generate(navTabs.length, (i) {
                  final tab = navTabs[i];
                  final isActive = widget.currentTab == i;
                  return InkWell(
                    onTap: () => widget.onTabChanged(i),
                    child: Container(
                      height: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppTheme.sidebarActive.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isHovered
                          ? Row(
                              children: [
                                const SizedBox(width: 12),
                                Icon(
                                  tab['icon'] as IconData,
                                  color: isActive ? AppTheme.sidebarActive : Colors.white60,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    tab['label'] as String,
                                    style: TextStyle(
                                      color: isActive ? Colors.white : Colors.white60,
                                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: Icon(
                                tab['icon'] as IconData,
                                color: isActive ? AppTheme.sidebarActive : Colors.white60,
                                size: 22,
                              ),
                            ),
                    ),
                  );
                }),

                const Spacer(),

                // ── Divider before settings ──
                const Divider(color: AppTheme.line, height: 1),

                // ── Settings (bottom) ──
                InkWell(
                  onTap: () => widget.onTabChanged(4),
                  child: Container(
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.currentTab == 4
                          ? AppTheme.sidebarActive.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isHovered
                        ? Row(
                            children: [
                              const SizedBox(width: 12),
                              Icon(
                                Icons.settings,
                                color: widget.currentTab == 4 ? AppTheme.sidebarActive : Colors.white60,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Pengaturan',
                                  style: TextStyle(
                                    color: widget.currentTab == 4 ? Colors.white : Colors.white60,
                                    fontWeight: widget.currentTab == 4 ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Icon(
                              Icons.settings,
                              color: widget.currentTab == 4 ? AppTheme.sidebarActive : Colors.white60,
                              size: 22,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
