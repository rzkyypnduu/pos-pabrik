import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentTab;
  final ValueChanged<int> onTabChanged;

  const AppBottomNav({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppTheme.sidebarBg),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentTab,
          onTap: onTabChanged,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppTheme.sidebarBg,
          selectedItemColor: AppTheme.sidebarActive,
          unselectedItemColor: Colors.white70,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.point_of_sale),
              label: 'Transaksi',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2),
              label: 'Produk',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assessment),
              label: 'Hasil',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.summarize),
              label: 'Ringkasan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Pengaturan',
            ),
          ],
        ),
      ),
    );
  }
}
