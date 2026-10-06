import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/review_service.dart';
import '../services/explore_request_bus.dart';
import '../services/cart_service.dart';
import '../theme/app_theme.dart';
import '../widgets/review_prompt_sheet.dart';
import '../widgets/tab_navigator.dart';
import '../widgets/persistent_cart_cta.dart';
import 'tabs/home_tab.dart';
import 'tabs/explore_tab.dart';
import 'tabs/bookings_tab.dart';
import '../utils/app_haptics.dart';
import 'tabs/profile_tab.dart';
import 'my_bookings_screen.dart';
import '../theme/app_colors.dart';

class MainScreen extends StatefulWidget {
  /// The floating navigation pill: 75 tall, held 20 off the sides and the
  /// bottom. Named so tests can rebuild the same footprint; screens should
  /// use bottomClearance() rather than these numbers.
  static const double navPillHeight = 75;
  static const double navPillMargin = 20;

  final bool isGuest;
  final int initialIndex;

  const MainScreen({Key? key, this.isGuest = false, this.initialIndex = 0})
    : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  late final List<Widget> _tabs;

  /// One navigator per tab so a page pushed from inside a tab stays inside
  /// that tab and the bottom navigation bar remains visible.
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  final GlobalKey<MyBookingsScreenState> _bookingsKey =
      GlobalKey<MyBookingsScreenState>();

  /// Explore is filtered from outside its own tab — a category picked on the
  /// home tab lands here — so the shell needs a handle to apply it.
  final GlobalKey<ExploreTabState> _exploreKey = GlobalKey<ExploreTabState>();

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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _askForPendingReviews(),
      );
    }

    _tabs = [
      HomeTab(isGuest: widget.isGuest),
      ExploreTab(key: _exploreKey),
      BookingsTab(bookingsKey: _bookingsKey, isGuest: widget.isGuest),
      ProfileTab(isGuest: widget.isGuest),
    ];

    ExploreRequestBus.instance.addListener(_onExploreRequested);
  }

  @override
  void dispose() {
    ExploreRequestBus.instance.removeListener(_onExploreRequested);
    super.dispose();
  }

  /// A category was picked somewhere else in the app — the home screen's fixed
  /// cards, or the all-categories page.
  ///
  /// The shell is the only thing that knows the tab index exists, so it is the
  /// shell that moves. The request is consumed here, which is what keeps a
  /// later rebuild from re-applying the same filter.
  void _onExploreRequested() {
    final request = ExploreRequestBus.instance.take();
    if (request == null) return;

    // Each tab keeps its own stack, so anything the customer pushed on Explore
    // has to go back to the directory or the filtered list is hidden behind it.
    _navigatorKeys[1].currentState?.popUntil((route) => route.isFirst);

    _exploreKey.currentState?.applyCategoryFilter(
      categoryId: request.categoryId,
      categoryLabel: request.categoryLabel,
    );

    if (_currentIndex != 1) {
      setState(() => _currentIndex = 1);
    }
  }

  void _onTabTapped(int index) {
    AppHaptics.selectionClick();
    if (index == 2 && !widget.isGuest) {
      _bookingsKey.currentState?.loadBookings();
    }
    if (index == 1) {
      // Reaching Explore by tapping the bar means "show me the directory", not
      // "keep showing whichever category I filtered by last". The request
      // listener above switches tabs itself, so it never passes through here
      // and cannot undo its own filter.
      _exploreKey.currentState?.clearCategoryFilter();
    }

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
            // IndexedStack keeps every tab alive and does not mute its tickers,
            // so anything animating on a hidden tab — the category marquee, the
            // banner carousel — would keep running off screen.
            TickerMode(
              enabled: i == _currentIndex,
              child: TabNavigator(
                navigatorKey: _navigatorKeys[i],
                root: _tabs[i],
              ),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: CartService.globalCartNotifier,
            builder: (context, cart, child) {
              if (cart == null) return const SizedBox.shrink();
              return PersistentCartCTA(cart: cart);
            },
          ),
          SafeArea(
            child: Container(
              margin: const EdgeInsets.only(
                left: MainScreen.navPillMargin,
                right: MainScreen.navPillMargin,
                bottom: MainScreen.navPillMargin,
              ),
              height: MainScreen.navPillHeight,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            // Only drawn when the theme has an outline to show: a border adds
            // padding even when transparent, which would shift the bar 1px.
            border: context.colors.raisedOutline.a > 0
                ? Border.all(color: context.colors.raisedOutline, width: 1)
                : null,
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Theme.of(context).colorScheme.surface,
              selectedItemColor: AppTheme.accentColor,
              unselectedItemColor: context.colors.navIdle,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: _AnimatedTabIcon(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    isSelected: _currentIndex == 0,
                  ),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: _AnimatedTabIcon(
                    icon: Icons.explore_outlined,
                    activeIcon: Icons.explore_rounded,
                    isSelected: _currentIndex == 1,
                  ),
                  label: 'Explore',
                ),
                BottomNavigationBarItem(
                  icon: _AnimatedTabIcon(
                    icon: Icons.calendar_today_outlined,
                    activeIcon: Icons.calendar_month_rounded,
                    isSelected: _currentIndex == 2,
                  ),
                  label: 'Bookings',
                ),
                BottomNavigationBarItem(
                  icon: _AnimatedTabIcon(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person_rounded,
                    isSelected: _currentIndex == 3,
                  ),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}

class _AnimatedTabIcon extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;

  const _AnimatedTabIcon({
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
  });

  @override
  State<_AnimatedTabIcon> createState() => _AnimatedTabIconState();
}

class _AnimatedTabIconState extends State<_AnimatedTabIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _yOffsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 60),
    ]).animate(_controller);

    _yOffsetAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -3.0).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -3.0, end: 0.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 60),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _AnimatedTabIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _controller.forward(from: 0.0);
    } else if (!widget.isSelected && oldWidget.isSelected) {
      // Rapid tap handling: immediately snap back if unselected during pop
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _yOffsetAnimation.value),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Icon(
                  widget.isSelected ? widget.activeIcon : widget.icon,
                  key: ValueKey<bool>(widget.isSelected),
                  size: 22,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

