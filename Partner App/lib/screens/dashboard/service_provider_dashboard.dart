import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tab_navigator.dart';
import '../qr_scanner_screen.dart';
import '../subscription_locked_screen.dart';
import '../../services/salon_access_api.dart';
import 'tabs/provider_profile_tab.dart';
import 'tabs/provider_home_tab.dart';
import 'tabs/provider_walk_in_tab.dart';
import '../provider_dashboard_screen.dart';

class ServiceProviderDashboard extends StatefulWidget {
  final Map<String, dynamic> salon;
  final Map<String, dynamic> provider;
  final Map<String, dynamic> user;
  
  const ServiceProviderDashboard({
    super.key, 
    required this.salon,
    required this.provider,
    required this.user,
  });

  @override
  State<ServiceProviderDashboard> createState() => _ServiceProviderDashboardState();
}

class _ServiceProviderDashboardState extends State<ServiceProviderDashboard> {
  int _currentIndex = 0; // Default to home tab as requested

  /// One navigator per tab so a page pushed from inside a tab stays inside
  /// that tab and the bottom navigation bar remains visible.
  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(4, (_) => GlobalKey<NavigatorState>());

  /// The salon's plan gates the whole shell, so it is checked before the tabs
  /// are drawn rather than letting each screen fail on its own.
  SalonAccess? _access;
  bool _checkingAccess = true;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    setState(() => _checkingAccess = true);

    try {
      final access = await SalonAccessApi.check(widget.salon['id'].toString());
      if (!mounted) return;
      setState(() {
        _access = access;
        _checkingAccess = false;
      });
    } catch (_) {
      // A failed check must not lock staff out of a salon that has paid.
      if (!mounted) return;
      setState(() {
        _access = null;
        _checkingAccess = false;
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == _currentIndex) {
      // Tapping the tab you are already on goes back to its first page.
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _currentIndex = index);
  }

  /// Back unwinds the active tab first, then falls back to Home and only then
  /// leaves the app.
  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;

    final navigator = _navigatorKeys[_currentIndex].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }

    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }

    SystemNavigator.pop();
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(salonId: widget.salon['id'].toString()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_access != null && _access!.isLocked) {
      return LockedSalonScope(
        salonId: widget.salon['id'].toString(),
        child: SubscriptionLockedScreen(access: _access!, onRecheck: _checkAccess),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final List<Widget> pages = [
      ProviderHomeTab(salon: widget.salon, provider: widget.provider, user: widget.user),
      ProviderDashboardScreen(salonId: widget.salon['id'].toString()),
      ProviderWalkInTab(salon: widget.salon, provider: widget.provider),
      ProviderProfileTab(
        salon: widget.salon,
        provider: widget.provider,
        user: widget.user,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < pages.length; i++)
            TabNavigator(navigatorKey: _navigatorKeys[i], root: pages[i]),
        ],
      ),
      // Scanning is the provider's most common action, so it sits on the shell
      // and is reachable from every tab and every page inside them.
      floatingActionButton: FloatingActionButton(
        onPressed: _openScanner,
        backgroundColor: AppTheme.accentColor,
        foregroundColor: Colors.white,
        tooltip: 'Scan customer QR',
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedItemColor: AppTheme.accentColor,
          unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today),
              label: 'Schedule',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_add_alt_1_outlined),
              activeIcon: Icon(Icons.person_add_alt_1),
              label: 'Add Walk-in',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
