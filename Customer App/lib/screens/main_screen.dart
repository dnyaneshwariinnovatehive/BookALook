import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';
import '../widgets/review_prompt_sheet.dart';
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

  /// Visits waiting to be rated, asked about one at a time.
  ///
  /// The prompt belongs here rather than on the home tab because it should
  /// follow the customer into the app however they arrive — a deep link from a
  /// QR code lands on a salon page, not on home.
  bool _askedThisSession = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    // After the first frame: the shell has to exist before a sheet can sit on
    // top of it.
    if (!widget.isGuest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askForPendingReviews());
    }

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

  /// Ask about unrated visits, one sheet at a time.
  ///
  /// Only ever once per launch, and it stops the moment someone dismisses one:
  /// a customer with four unrated visits who skips the first is telling us
  /// something, and stacking three more sheets on them would be the fastest way
  /// to teach them to ignore the prompt forever.
  Future<void> _askForPendingReviews() async {
    if (_askedThisSession) return;
    _askedThisSession = true;

    final pending = await ReviewService.pending();
    if (!mounted || pending.isEmpty) return;

    for (final visit in pending) {
      final submitted = await ReviewPromptSheet.show(
        context,
        Map<String, dynamic>.from(visit as Map),
      );

      if (!mounted || !submitted) break;
    }
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
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            TabNavigator(navigatorKey: _navigatorKeys[i], root: _tabs[i]),
        ],
      ),
      bottomNavigationBar: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border(
            top: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? AppTheme.darkBorder 
                  : AppTheme.lightBorder,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedItemColor: AppTheme.accentColor,
            unselectedItemColor: Theme.of(context).brightness == Brightness.dark 
                ? AppTheme.darkTextBody 
                : AppTheme.lightTextBody,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.home_outlined, size: 22)),
                activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.home_rounded, size: 22)),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.explore_outlined, size: 22)),
                activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.explore_rounded, size: 22)),
                label: 'Explore',
              ),
              BottomNavigationBarItem(
                icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.calendar_today_outlined, size: 22)),
                activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.calendar_month_rounded, size: 22)),
                label: 'Bookings',
              ),
              BottomNavigationBarItem(
                icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.favorite_outline, size: 22)),
                activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.favorite_rounded, size: 22)),
                label: 'Favourites',
              ),
              BottomNavigationBarItem(
                icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.person_outline, size: 22)),
                activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.person_rounded, size: 22)),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
