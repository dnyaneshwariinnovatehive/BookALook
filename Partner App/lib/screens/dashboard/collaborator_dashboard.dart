import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/collaborator_badges.dart';
import '../../services/onboarding_draft_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/collaborator/collaborator_pill_nav_bar.dart';
import '../../widgets/tab_navigator.dart';
import 'collaborator_tabs/collaborator_assigned_tab.dart';
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
  static const _assignedTab = 2;
  static const _profileTab = 3;

  /// One navigator per tab so a page pushed from inside a tab renders in that
  /// tab's body instead of covering the whole screen, leaving the bottom bar
  /// visible underneath.
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  /// The tabs live inside an [IndexedStack] and stay mounted, so the shell keeps
  /// a handle on each one in order to tell it to reload or to stop polling.
  final GlobalKey<CollaboratorHomeTabState> _homeKey =
      GlobalKey<CollaboratorHomeTabState>();
  final GlobalKey<CollaboratorOnboardedTabState> _mySalonsKey =
      GlobalKey<CollaboratorOnboardedTabState>();
  final GlobalKey<CollaboratorAssignedTabState> _assignedKey =
      GlobalKey<CollaboratorAssignedTabState>();
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

    // A tab's own initState runs during the first build, so its State handle
    // does not exist yet while this frame is being assembled. Anything the
    // shell has to tell a tab on frame one has to be delivered afterwards, or
    // the tab silently runs the whole session on whatever default it shipped
    // with. Assigned defaults to "not visible", so this is what starts its poll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTabVisibility();
    });
  }

  @override
  void dispose() {
    _badges.dispose();
    super.dispose();
  }

  /// Tells each tab whether anyone is looking at it.
  ///
  /// Only Assigned acts on this today, but the shell is the only thing that
  /// knows the answer, so it stays here rather than becoming an Assigned
  /// concern.
  void _syncTabVisibility() {
    _assignedKey.currentState?.setActive(_currentIndex == _assignedTab);
  }

  /// Tapping the tab you are already on returns it to its first page and
  /// refreshes it, so "I'm on Assigned and I want to see it again" is one tap.
  void _onItemTapped(int index) {
    if (index == _currentIndex) {
      _refreshTab(index);
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }

    setState(() => _currentIndex = index);
    _syncTabVisibility();
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
      case _assignedTab:
        _assignedKey.currentState?.reload();
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
      _syncTabVisibility();
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
      onGoToAssigned: () => _goTo(_assignedTab),
      onGoToMySalons: () => _goTo(_mySalonsTab),
    ),
    _mySalonsTab => CollaboratorOnboardedTab(
      key: _mySalonsKey,
      badges: _badges,
      onGoToAssigned: () => _goTo(_assignedTab),
    ),
    _assignedTab => CollaboratorAssignedTab(key: _assignedKey, badges: _badges),
    _ => CollaboratorProfileTab(key: _profileKey),
  };

  void _goTo(int index) {
    setState(() => _currentIndex = index);
    _syncTabVisibility();
    _refreshTab(index);
  }

  /// The app bar used to say "Collaborator Dashboard", which told a
  /// collaborator nothing they did not already know and repeated the greeting
  /// already shown on Home.
  ///
  /// It now carries the tab's name and a one-line explanation of what lives in
  /// it. "My Salons" and "Assigned" are two similar nouns for two different
  /// queues, and this is where that gets disambiguated — the labels stay as they
  /// are, but nothing is left to guess about.
  PreferredSizeWidget _buildAppBar() {
    const subtitles = <int, String>{
      _homeTab: 'Where to pick up today',
      _mySalonsTab: 'Salons you submitted, and their approval status',
      _assignedTab: 'Salons waiting to be onboarded',
      _profileTab: 'Your details and your tally',
    };
    const titles = <int, String>{
      _homeTab: 'Home',
      _mySalonsTab: 'My Salons',
      _assignedTab: 'Assigned',
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
    );
  }

  Widget _buildNavBar() {
    return ListenableBuilder(
      // Both sources matter: the tabs push queue counts in through [_badges],
      // and the draft store pushes the number of finished-but-unsent
      // submissions. The store is a ChangeNotifier that outlives every tab, so
      // merging the two keeps the badge live whether the count came from a
      // network read or from the device.
      listenable: Listenable.merge([_badges, OnboardingDraftStore.instance]),
      builder: (context, _) {
        // Drafts waiting for signal are the collaborator's own unsent work, so
        // they ride along on the Assigned badge rather than needing a tab of
        // their own.
        final queued = _badges.queuedDrafts(OnboardingDraftStore.instance);

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
            label: 'Assigned',
            icon: Icons.inbox_outlined,
            activeIcon: Icons.inbox,
            badge: _badges.assignedCount + queued,
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
