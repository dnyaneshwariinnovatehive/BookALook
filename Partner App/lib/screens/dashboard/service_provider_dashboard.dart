import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/floating_pill_nav_bar.dart';
import '../../widgets/tab_navigator.dart';
import '../subscription_locked_screen.dart';
import '../../services/salon_access_api.dart';
import '../../services/auth_service.dart';
import '../../services/staff_api.dart';
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

class _ServiceProviderDashboardState extends State<ServiceProviderDashboard>
    with WidgetsBindingObserver {
  int _currentIndex = 0; // Default to home tab as requested
  late Map<String, dynamic> _provider;

  /// One navigator per tab so a page pushed from inside a tab stays inside
  /// that tab and the bottom navigation bar remains visible.
  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(4, (_) => GlobalKey<NavigatorState>());

  /// Keep the tab's own State reachable from the shell. The tabs live inside
  /// the IndexedStack, so they stay alive across tab switches — the shell has
  /// to ask them to reload when the user comes back, and when a walk-in is
  /// created in another tab.
  final GlobalKey<ProviderHomeTabState> _homeKey = GlobalKey<ProviderHomeTabState>();
  final GlobalKey<ProviderDashboardScreenState> _scheduleKey =
      GlobalKey<ProviderDashboardScreenState>();
  final GlobalKey<ProviderProfileTabState> _profileKey =
      GlobalKey<ProviderProfileTabState>();

  /// The salon's plan gates the whole shell, so it is checked before the tabs
  /// are drawn rather than letting each screen fail on its own.
  SalonAccess? _access;
  bool _checkingAccess = true;

  @override
  void initState() {
    super.initState();
    _provider = Map<String, dynamic>.from(widget.provider);
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
    _refreshProviderProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTabVisibility();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshProviderProfile();
      _checkAccess();
    }
  }

  Future<void> _refreshProviderProfile() async {
    try {
      final res = await StaffApi.fetchMyProfile(widget.salon['id'].toString());
      if (res['provider'] != null && mounted) {
        final updatedProvider = Map<String, dynamic>.from(res['provider']);
        setState(() {
          _provider = updatedProvider;
        });
        _homeKey.currentState?.updateProvider(updatedProvider);
        _profileKey.currentState?.updateProvider(updatedProvider);

        try {
          final prefs = await SharedPreferences.getInstance();
          final authStr = prefs.getString('auth_state');
          if (authStr != null) {
            final authData = jsonDecode(authStr) as Map<String, dynamic>;
            authData['provider'] = updatedProvider;
            await prefs.setString('auth_state', jsonEncode(authData));
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _syncTabVisibility() {
    _homeKey.currentState?.setActive(_currentIndex == 0);
    _scheduleKey.currentState?.setActive(_currentIndex == 1);
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
      // Tapping the tab you are already on goes back to its first page, and so
      // the content on that tab reloads.
      _refreshTab(index);
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _currentIndex = index);
    _syncTabVisibility();
    _refreshTab(index);
  }

  /// Reload the appointment tab that was just opened. Home and Schedule both
  /// read from the live appointments endpoint, so data created in another tab
  /// (a walk-in, for instance) shows up without a manual refresh.
  void _refreshTab(int index) {
    switch (index) {
      case 0:
        _refreshProviderProfile();
        _homeKey.currentState?.loadAppointments();
        break;
      case 1:
        _scheduleKey.currentState?.loadAppointments();
        break;
      case 3:
        _refreshProviderProfile();
        break;
    }
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



  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.salon['status'] == 'deactivated') {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cancel_outlined, color: Colors.red, size: 80),
                const SizedBox(height: 24),
                Text('Salon Deactivated', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.red, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('This salon has been deactivated by the administrator. You can no longer access the service provider dashboard.', textAlign: TextAlign.center),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () => AuthService().logout(context),
                  child: const Text('Log Out'),
                ),
              ],
            ),
          ),
        ),
      );
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
      ProviderHomeTab(key: _homeKey, salon: widget.salon, provider: _provider, user: widget.user),
      ProviderDashboardScreen(key: _scheduleKey, salonId: widget.salon['id'].toString()),
      ProviderWalkInTab(
        salon: widget.salon,
        provider: _provider,
        onCreated: () => _homeKey.currentState?.loadAppointments(),
      ),
      ProviderProfileTab(
        key: _profileKey,
        salon: widget.salon,
        provider: _provider,
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
      bottomNavigationBar: FloatingPillNavBar(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        items: const [
          PillNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
          PillNavItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_month_rounded, label: 'Schedule'),
          PillNavItem(icon: Icons.person_add_alt_1_outlined, activeIcon: Icons.person_add_alt_1_rounded, label: 'Add Walk-in'),
          PillNavItem(icon: Icons.person_outline, activeIcon: Icons.person_rounded, label: 'Profile'),
        ],
      ),
    );
  }
}
