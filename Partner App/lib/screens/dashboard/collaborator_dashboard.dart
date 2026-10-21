import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/collaborator_badges.dart';
import '../../services/onboarding_draft_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/collaborator/collaborator_notification_bell.dart';
import '../../widgets/collaborator/collaborator_pill_nav_bar.dart';
import '../../widgets/tab_navigator.dart';
import 'collaborator_tabs/collaborator_approved_tab.dart';
import 'collaborator_tabs/collaborator_home_tab.dart';
import 'collaborator_tabs/collaborator_onboarded_tab.dart';
import 'collaborator_tabs/collaborator_profile_tab.dart';

/// The collaborator's home: Home, My Salons, Assigned, Profile.
///
/// Three things this shell does that the version it replaces did not.
///
/// It keeps the tabs alive. It used to build `tabs[_currentIndex]` and nothing
/// else, so every switch threw away a whole screen's State — scroll position,
/// the selected status filter on My Salons, everything — and the collaborator
/// paid for it with a full-screen spinner on the way back in. That was traded
/// off against refetching on return, which is a real need after a salon visit;
/// it is now got explicitly through [CollaboratorOnboardedTabState.reload] and
/// friends instead of as a side effect of destroying the tab.
///
/// It gives each tab its own navigator. Opening the onboarding wizard from
/// Assigned used to cover the whole screen, bottom bar and all, because the tab
/// had no navigator of its own to push within. See [TabNavigator].
///
/// And it shows the counts. Assigned and My Salons are the two queues a
/// collaborator lives in, and without a badge on the navigation the only way to
/// find out whether you have work is to open the tab and look.
class CollaboratorDashboardScreen extends StatefulWidget {
  const CollaboratorDashboardScreen({super.key});

  @override
  State<CollaboratorDashboardScreen> createState() =>
      _CollaboratorDashboardScreenState();
}

class _CollaboratorDashboardScreenState
    extends State<CollaboratorDashboardScreen> {
  int _currentIndex = 0;

  static const _homeTab = 0;
  static const _mySalonsTab = 1;
  static const _approvedTab = 2;
  static const _profileTab = 3;

  /// One navigator per tab so a page pushed from inside a tab renders in that
  /// tab's body instead of covering the whole screen, leaving the bottom bar
  /// visible underneath.
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  /// The tabs live inside an [IndexedStack] and stay mounted, so the shell keeps
  /// a handle on each one in order to tell it to reload.
  final GlobalKey<CollaboratorHomeTabState> _homeKey =
      GlobalKey<CollaboratorHomeTabState>();
  final GlobalKey<CollaboratorOnboardedTabState> _mySalonsKey =
      GlobalKey<CollaboratorOnboardedTabState>();
  final GlobalKey<CollaboratorApprovedTabState> _approvedKey =
      GlobalKey<CollaboratorApprovedTabState>();
  final GlobalKey<CollaboratorProfileTabState> _profileKey =
      GlobalKey<CollaboratorProfileTabState>();

  /// Counters the tabs push their numbers into for the navigation badges.
  final CollaboratorBadges _badges = CollaboratorBadges();

  @override
  void initState() {
    super.initState();

    // Starts the draft store the moment a collaborator is in the app, so a
    // submission queued during yesterday's visit goes out today without anyone
    // opening the tab it lives in.
    OnboardingDraftStore.instance.load();
  }

  @override
  void dispose() {
    _badges.dispose();
    super.dispose();
  }

  /// Tapping the tab you are already on returns it to its first page and
  /// refreshes it.
  void _onItemTapped(int index) {
    if (index == _currentIndex) {
      _refreshTab(index);
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }

    setState(() => _currentIndex = index);
    _refreshTab(index);
  }

  void _refreshTab(int index) {
    switch (index) {
      case _homeTab:
        _homeKey.currentState?.reload();
        break;
      case _mySalonsTab:
        _mySalonsKey.currentState?.reload();
        break;
      case _approvedTab:
        _approvedKey.currentState?.reload();
        break;
      case _profileTab:
        _profileKey.currentState?.reload();
        break;
    }
  }

  /// Back unwinds the active tab first, then falls back to Home, and only then
  /// leaves the app — the same contract the service provider shell offers.
  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;

    final navigator = _navigatorKeys[_currentIndex].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }

    if (_currentIndex != _homeTab) {
      setState(() => _currentIndex = _homeTab);
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < 4; i++)
              TabNavigator(navigatorKey: _navigatorKeys[i], root: _tabAt(i)),
          ],
        ),
        bottomNavigationBar: _buildNavBar(),
      ),
    );
  }

  Widget _tabAt(int index) => switch (index) {
    _homeTab => CollaboratorHomeTab(
      key: _homeKey,
      badges: _badges,
      onGoToAssigned: () {
        _goTo(_mySalonsTab);
        _mySalonsKey.currentState?.setFilter('assigned');
      },
      onGoToMySalons: () => _goTo(_mySalonsTab),
      onGoToApproved: () => _goTo(_approvedTab),
    ),
    _mySalonsTab => CollaboratorOnboardedTab(
      key: _mySalonsKey,
      badges: _badges,
      onGoToAssigned: () {
        _mySalonsKey.currentState?.setFilter('assigned');
      },
    ),
    _approvedTab => CollaboratorApprovedTab(
      key: _approvedKey,
      badges: _badges,
      onGoToMySalons: () => _goTo(_mySalonsTab),
    ),
    _ => CollaboratorProfileTab(key: _profileKey),
  };

  void _goTo(int index) {
    setState(() => _currentIndex = index);
    _refreshTab(index);
  }

  PreferredSizeWidget _buildAppBar() {
    const subtitles = <int, String>{
      _homeTab: 'Where to pick up today',
      _mySalonsTab: 'All your onboarded, in-review, and assigned salons',
      _approvedTab: 'Salons explicitly approved by Super Admin',
      _profileTab: 'Your details and your tally',
    };
    const titles = <int, String>{
      _homeTab: 'Home',
      _mySalonsTab: 'My Salons',
      _approvedTab: 'Approved Salons',
      _profileTab: 'Profile',
    };

    return AppBar(
      titleSpacing: 20,
      toolbarHeight: 68,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titles[_currentIndex]!,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitles[_currentIndex]!,
            style: TextStyle(
              fontSize: 11.5,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
      actions: _currentIndex == _homeTab
          ? const [CollaboratorNotificationBell()]
          : null,
    );
  }

  Widget _buildNavBar() {
    return ListenableBuilder(
      listenable: _badges,
      builder: (context, _) {
        final items = [
          const CollaboratorNavItem(
            label: 'Home',
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
          ),
          CollaboratorNavItem(
            label: 'My Salons',
            icon: Icons.storefront_outlined,
            activeIcon: Icons.storefront,
            badge: _badges.mySalonsCount,
          ),
          CollaboratorNavItem(
            label: 'Approved Salons',
            icon: Icons.verified_outlined,
            activeIcon: Icons.verified,
            badge: _badges.approvedCount,
          ),
          const CollaboratorNavItem(
            label: 'Profile',
            icon: Icons.person_outline,
            activeIcon: Icons.person,
          ),
        ];

        return CollaboratorPillNavBar(
          items: items,
          currentIndex: _currentIndex,
          onTap: _onItemTapped,
        );
      },
    );
  }
}
