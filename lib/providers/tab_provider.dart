import 'package:flutter/material.dart';
import '../constants/formatters.dart' as fmt;

class TabProvider extends ChangeNotifier {
  int _currentTab = 0;
  String _activeMonth = fmt.activeMonthString();
  String _selectedDate = fmt.todayString();

  int get currentTab => _currentTab;
  String get activeMonth => _activeMonth;
  String get selectedDate => _selectedDate;
  String get monthLbl => fmt.monthLabel(_activeMonth);

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  void setSelectedDate(String date) {
    _selectedDate = date;
    notifyListeners();
  }

  void setActiveMonth(String month) {
    _activeMonth = month;
    notifyListeners();
  }

  void prevMonth() {
    _activeMonth = fmt.prevMonth(_activeMonth);
    notifyListeners();
  }

  void nextMonth() {
    _activeMonth = fmt.nextMonth(_activeMonth);
    notifyListeners();
  }
}
