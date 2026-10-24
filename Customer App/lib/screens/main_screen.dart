import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/review_service.dart';
import '../services/explore_request_bus.dart';
import '../services/cart_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../widgets/review_prompt_sheet.dart';
import '../widgets/tab_navigator.dart';
import '../widgets/persistent_cart_cta.dart';
import '../widgets/tab_loading_overlay.dart';
import 'tabs/home_tab.dart';
import 'tabs/explore_tab.dart';
import 'tabs/bookings_tab.dart';
import '../utils/app_haptics.dart';
import 'tabs/profile_tab.dart';
import 'my_bookings_screen.dart';
import '../services/deep_link_service.dart';
import '../services/location_service.dart';
import '../widgets/city_picker_sheet.dart';
import '../widgets/location_permission_modal.dart';
import '../services/app_version_service.dart';
import '../services/http_client.dart' show mandatoryUpdateRouteName;
import '../widgets/optional_update_dialog.dart';
import 'mandatory_update_screen.dart';

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

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final List<int> _tabHistory = [];

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

  bool _isTabLoading = false;
  String _loadingMessage = '';
  int _loadingTab = -1;
  int? _targetTabIndex;

  String _getLoadingMessage(int index) {
    switch (index) {
      case 0:
        return "Finding salons near you";
      case 1:
        return "Discovering beauty services";
      case 2:
        return "Loading your appointments";
      case 3:
        return "Loading your profile";
      default:
        return "";
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;

    // After the first frame: the shell has to exist before a modal or sheet can sit on
    // top of it.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Check for available or mandatory updates first
      await _checkAppUpdates();

      // Restore saved city first so one-time permissions or manual selections are loaded
      await LocationService.instance.restore();

      // If opened via QR code or deep link to a specific salon, skip initial modal prompt
      if (!DeepLinkService.instance.hasPendingInitialLink) {
        await _checkLocationPermission();
      }

      // Spaced dialog sequencing: give 1.5s breathing room so review dialogs never clash
      if (!widget.isGuest && mounted) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted && !DeepLinkService.instance.hasPendingInitialLink) {
          _askForPendingReviews();
        }
      }
    });

    _tabs = [
      HomeTab(isGuest: widget.isGuest),
      ExploreTab(key: _exploreKey),
      BookingsTab(bookingsKey: _bookingsKey, isGuest: widget.isGuest),
      ProfileTab(isGuest: widget.isGuest),
    ];

    ExploreRequestBus.instance.addListener(_onExploreRequested);
  }

  Future<void> _checkAppUpdates() async {
    if (!mounted) return;
    try {
      final updateInfo = await AppVersionService.instance.checkUpdate();
      if (!mounted) return;

      if (updateInfo.isMandatory) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(
            settings: const RouteSettings(name: mandatoryUpdateRouteName),
            builder: (_) => MandatoryUpdateScreen(updateInfo: updateInfo),
          ),
          (route) => false,
        );
      } else if (updateInfo.isOptional) {
        OptionalUpdateDialog.showIfEligible(context, updateInfo);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAppUpdates();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ExploreRequestBus.instance.removeListener(_onExploreRequested);
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    if (!mounted) return;

    final hasPerm = await LocationService.instance.hasPermission();
    if (hasPerm) return;

    final hasPrompted = await LocationService.instance
        .hasPromptedInitialLocation();
    if (!hasPrompted) {
      await LocationService.instance.markInitialLocationPrompted();
      if (!mounted) return;
      final granted = await showLocationPermissionModal(context);
      if (mounted && !LocationService.instance.hasCity && granted != true) {
        await showCityPicker(context);
      }
      return;
    }

    if (!widget.isGuest && LocationService.instance.canShowPostLoginReminder) {
      LocationService.instance.markPostLoginReminded();
      if (!mounted) return;
      final granted = await showLocationPermissionModal(context);
      if (mounted && !LocationService.instance.hasCity && granted != true) {
        await showCityPicker(context);
      }
    }
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
      if (_tabHistory.isEmpty || _tabHistory.last != _currentIndex) {
        _tabHistory.add(_currentIndex);
      }
      setState(() => _currentIndex = 1);
    }
  }

  void _onTabTapped(int index) async {
    if (index == _currentIndex && !_isTabLoading) {
      AppHaptics.selectionClick();
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }

    if (_isTabLoading) {
      _targetTabIndex = index;
      return;
    }

    AppHaptics.selectionClick();

    Future<void> realOperation = Future.value();

    if (index == 2 && !widget.isGuest) {
      realOperation =
          _bookingsKey.currentState?.loadBookings() ?? Future.value();
    } else if (index == 1) {
      _exploreKey.currentState?.clearCategoryFilter();
    }

    bool isFast = false;
    final fastTimer = Future.delayed(const Duration(milliseconds: 150));

    await Future.any([
      realOperation.then((_) => isFast = true).catchError((_) => isFast = true),
      fastTimer,
    ]);

    if (!mounted) return;

    if (isFast) {
      // Network is fast, switch instantly without overlay
      final target = _targetTabIndex ?? index;
      if (target != _currentIndex) {
        if (_tabHistory.isEmpty || _tabHistory.last != _currentIndex) {
          _tabHistory.add(_currentIndex);
        }
      }
      setState(() {
        _currentIndex = target;
        _targetTabIndex = null;
      });
      return;
    }

    // Network is slow, show the loading overlay
    final slowTarget = index;
    if (slowTarget != _currentIndex) {
      if (_tabHistory.isEmpty || _tabHistory.last != _currentIndex) {
        _tabHistory.add(_currentIndex);
      }
    }
    setState(() {
      _isTabLoading = true;
      _targetTabIndex = index;
      _loadingTab = index;
      _loadingMessage = _getLoadingMessage(index);
      _currentIndex = index; // Switch instantly under overlay
    });

    try {
      await realOperation;
    } catch (_) {
      // Let individual tabs handle errors
    }

    if (!mounted) return;

    final finalIndex = _targetTabIndex ?? index;

    setState(() {
      _isTabLoading = false;
      _targetTabIndex = null;
      if (_currentIndex != finalIndex) {
        if (_tabHistory.isEmpty || _tabHistory.last != _currentIndex) {
          _tabHistory.add(_currentIndex);
        }
        _currentIndex = finalIndex;
      }
    });

    if (finalIndex != index) {
      _onTabTapped(finalIndex);
    }
  }

  /// Back unwinds the active tab first, then falls back through tab history,
  /// and only leaves the app from the Home tab with no history.
  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;

    final navigator = _navigatorKeys[_currentIndex].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }

    while (_tabHistory.isNotEmpty && _tabHistory.last == _currentIndex) {
      _tabHistory.removeLast();
    }
    if (_tabHistory.isNotEmpty) {
      final prevTab = _tabHistory.removeLast();
      setState(() => _currentIndex = prevTab);
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
      extendBody: false,
      body: ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: CartService.globalCartNotifier,
        builder: (context, cart, _) {
          final bool hasItems =
              cart != null && ((cart['items'] as List?)?.isNotEmpty ?? false);

          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Builder(
                builder: (context) {
                  final mediaQuery = MediaQuery.of(context);
                  // Approximate CTA capsule height (48) + padding (12) + buffer (8) = 68
                  final extraPadding = hasItems ? 68.0 : 0.0;

                  return Stack(
                    children: [
                      MediaQuery(
                        data: mediaQuery.copyWith(
                          padding: mediaQuery.padding.copyWith(
                            bottom: mediaQuery.padding.bottom + extraPadding,
                          ),
                        ),
                        child: IndexedStack(
                          index: _currentIndex,
                          children: [
                            for (var i = 0; i < _tabs.length; i++)
                              TickerMode(
                                enabled: i == _currentIndex,
                                child: TabNavigator(
                                  navigatorKey: _navigatorKeys[i],
                                  root: _tabs[i],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_isTabLoading,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: _isTabLoading
                                ? BookALookTabLoadingOverlay(
                                    message: _loadingMessage,
                                    tabIndex: _loadingTab,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.9,
                            end: 1.0,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: hasItems
                        ? PersistentCartCTA(
                            key: const ValueKey('cart_cta'),
                            cart: cart,
                          )
                        : const SizedBox.shrink(key: ValueKey('empty_cta')),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(
            left: MainScreen.navPillMargin,
            right: MainScreen.navPillMargin,
            bottom: MainScreen.navPillMargin,
          ),
          height: MainScreen.navPillHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: context.colors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF9850F1).withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Row(
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore_rounded,
                  label: 'Explore',
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.calendar_today_outlined,
                  activeIcon: Icons.calendar_month_rounded,
                  label: 'Bookings',
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.person_outline,
                  activeIcon: Icons.person_rounded,
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppTheme.accentColor : context.colors.navIdle;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabTapped(index),
          splashColor: AppTheme.accentColor.withValues(alpha: 0.1),
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AnimatedTabIcon(
                icon: icon,
                activeIcon: activeIcon,
                isSelected: isSelected,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isSelected ? 5 : 0,
                height: isSelected ? 5 : 0,
                decoration: const BoxDecoration(
                  color: AppTheme.accentColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
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

class _AnimatedTabIconState extends State<_AnimatedTabIcon>
    with SingleTickerProviderStateMixin {
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
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.15,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
    ]).animate(_controller);

    _yOffsetAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: -3.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -3.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
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
                  color: widget.isSelected
                      ? AppTheme.accentColor
                      : context.colors.navIdle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
