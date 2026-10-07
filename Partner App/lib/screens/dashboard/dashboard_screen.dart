import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/tab_navigator.dart';
import '../subscription_locked_screen.dart';
import '../onboarding/welcome_success_screen.dart';
import '../../services/salon_access_api.dart';
import '../../services/wallet_balance.dart';
import 'tabs/home_tab.dart';
import 'tabs/appointments_tab.dart';
import 'tabs/staff_tab.dart';
import 'tabs/services_tab.dart';
import 'tabs/more_tab.dart';
import '../../widgets/location_permission_modal.dart';
import '../../widgets/animated_staff_icon.dart';

class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic> salonData;

  const DashboardScreen({super.key, required this.salonData});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  late List<Widget> _tabs;

  /// One navigator per tab so a page pushed from inside a tab stays inside
  /// that tab and the bottom navigation bar remains visible.
  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(5, (_) => GlobalKey<NavigatorState>());


  /// The salon's plan gates the whole shell, so it is checked before the tabs
  /// are drawn rather than letting each screen fail on its own.
  SalonAccess? _access;
  bool _checkingAccess = true;
  String? _initError;
  bool _showWelcome = false;
  bool _hasCheckedLocationReminder = false;

  Future<void> _checkAccess() async {
    setState(() => _checkingAccess = true);

    try {
      final access = await SalonAccessApi.check(widget.salonData['id'].toString());
      if (!mounted) return;

      // This response already carries the coin balance, so the pill in every
      // header costs nothing extra to fill.
      WalletBalance.seedFrom(access);

      bool showWelcome = false;
      if (access.hasNeverSubscribed) {
        final grantedAt = access.welcomeBonusGrantedAt;
        if (grantedAt != null) {
          final now = DateTime.now();
          if (now.isAfter(grantedAt) && now.difference(grantedAt).inDays < 7) {
            final prefs = await SharedPreferences.getInstance();
            final key = 'welcome_shown_${widget.salonData['id']}';
            if (prefs.getBool(key) != true) {
              showWelcome = true;
              await prefs.setBool(key, true);
            }
          }
        }
      }

      setState(() {
        _access = access;
        _showWelcome = showWelcome;
        _checkingAccess = false;
        try {
          _buildTabs();
        } catch (e, stack) {
          _initError = 'Error in _buildTabs (success path): $e\n$stack';
        }
      });
      
      if (mounted && !showWelcome && !access.isLocked && !_hasCheckedLocationReminder) {
        _hasCheckedLocationReminder = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            LocationPermissionModal.checkAndShow(context, widget.salonData['id'].toString());
          }
        });
      }
    } catch (e, stack) {
      // A failed check must not lock a paying salon out of its own app.
      if (!mounted) return;
      setState(() {
        _access = null;
        _checkingAccess = false;
        try {
          _buildTabs();
        } catch (innerE, innerStack) {
          _initError = 'Error in _buildTabs (catch path): $innerE\n$innerStack\nOriginal error: $e';
        }
      });
    }
  }

  void _buildTabs() {
    _tabs = [
      HomeTab(
        salonId: widget.salonData['id'].toString(), 
        salonName: widget.salonData['name']?.toString() ?? '',
        planName: _access?.planName,
        daysRemaining: _access?.daysRemaining,
      ),
      AppointmentsTab(salonId: widget.salonData['id'].toString()),
      StaffTab(salonId: widget.salonData['id'].toString()),
      ServicesTab(salonId: widget.salonData['id'].toString()),
      MoreTab(
        salonData: widget.salonData,
        planName: _access?.planName,
        daysRemaining: _access?.daysRemaining,
        onSalonUpdated: (updatedData) {
          setState(() {
            widget.salonData.addAll(updatedData);
            _buildTabs();
          });
        },
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _buildTabs();
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
    if (_initError != null) {
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              _initError!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        ),
      );
    }

    if (_checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_access != null && _access!.isLocked) {
      if (_showWelcome) {
        return WelcomeSuccessScreen(
          access: _access!,
          onContinue: () {
            setState(() => _showWelcome = false);
          },
        );
      }
      return LockedSalonScope(
        salonId: widget.salonData['id'].toString(),
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
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            TabNavigator(navigatorKey: _navigatorKeys[i], root: _tabs[i]),
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              spreadRadius: 0,
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedItemColor: AppTheme.accentColor,
            unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            showUnselectedLabels: true,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            elevation: 0,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, height: 1.5),
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
                icon: const AnimatedStaffIcon(isActive: false),
                activeIcon: const AnimatedStaffIcon(isActive: true),
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
      ),
    );
  }
}
