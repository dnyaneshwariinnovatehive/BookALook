import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/tab_navigator.dart';
import 'tabs/home_tab.dart';
import 'tabs/explore_tab.dart';
import 'tabs/bookings_tab.dart';
import 'tabs/favourites_tab.dart';
import 'tabs/profile_tab.dart';

class MainScreen extends StatefulWidget {
  final bool isGuest;
  final int initialIndex;

  const MainScreen({Key? key, this.isGuest = false, this.initialIndex = 0}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  late final List<Widget> _tabs;

  /// One navigator per tab so a page pushed from inside a tab stays inside
  /// that tab and the bottom navigation bar remains visible.
  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(5, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _tabs = [
      HomeTab(isGuest: widget.isGuest),
      ExploreTab(),
      BookingsTab(isGuest: widget.isGuest),
      FavouritesTab(isGuest: widget.isGuest),
      ProfileTab(isGuest: widget.isGuest),
    ];
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) {
      // Tapping the tab you are already on goes back to its first page.
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _currentIndex = index;
    });
  }

  /// Back unwinds the active tab first, then falls back to the Home tab and
  /// only then leaves the app.
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            TabNavigator(navigatorKey: _navigatorKeys[i], root: _tabs[i]),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
              blurRadius: 20,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
            items: [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.explore_outlined),
                activeIcon: Icon(Icons.explore),
                label: 'Explore',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_today_outlined),
                activeIcon: Icon(Icons.calendar_month),
                label: 'Bookings',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.favorite_outline),
                activeIcon: Icon(Icons.favorite),
                label: 'Favourites',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
