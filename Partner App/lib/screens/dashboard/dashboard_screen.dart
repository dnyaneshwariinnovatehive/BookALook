import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../widgets/tab_navigator.dart';
import '../qr_scanner_screen.dart';
import 'tabs/home_tab.dart';
import 'tabs/appointments_tab.dart';
import 'tabs/staff_tab.dart';
import 'tabs/services_tab.dart';
import 'tabs/more_tab.dart';

class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic> salonData;

  const DashboardScreen({super.key, required this.salonData});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  late final List<Widget> _tabs;

  /// One navigator per tab so a page pushed from inside a tab stays inside
  /// that tab and the bottom navigation bar remains visible.
  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(5, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    _tabs = [
      const HomeTab(),
      AppointmentsTab(salonId: widget.salonData['id'].toString()),
      StaffTab(salonId: widget.salonData['id']),
      ServicesTab(salonId: widget.salonData['id']),
      MoreTab(salonId: widget.salonData['id']),
    ];
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) {
      // Tapping the tab you are already on goes back to its first page.
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Back unwinds the active tab first, then falls back to Home and only then
  /// leaves the app.
  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;

    final navigator = _navigatorKeys[_selectedIndex].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }

    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: _buildShell(context),
    );
  }

  /// The scanner lives on the shell, so it is one tap away from every tab and
  /// every page inside them.
  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(salonId: widget.salonData['id'].toString()),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            TabNavigator(navigatorKey: _navigatorKeys[i], root: _tabs[i]),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openScanner,
        backgroundColor: AppTheme.accentColor,
        foregroundColor: Colors.white,
        tooltip: 'Scan customer QR',
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6).withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedItemColor: AppTheme.accentColor,
          unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          showUnselectedLabels: true,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today),
              label: 'Appointments',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Staff',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.content_cut_outlined),
              activeIcon: Icon(Icons.content_cut),
              label: 'Services',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
