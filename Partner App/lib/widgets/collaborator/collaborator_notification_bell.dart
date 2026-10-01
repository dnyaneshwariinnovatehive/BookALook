import 'dart:async';

import 'package:flutter/material.dart';

import '../../screens/dashboard/collaborator_tabs/collaborator_notifications_screen.dart';
import '../../services/collaborator_api.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// The notifications bell on the collaborator's Home tab.
///
/// Self-contained on purpose. The unread count is not something any tab already
/// knows, unlike the bottom-bar badges, so there is nothing to relay — the bell
/// has to ask the server itself. It polls while it is on screen and stops the
/// moment it is disposed, which happens when the collaborator leaves Home
/// because the shell only builds it for the Home tab.
///
/// The badge counts *important* unread notices only. A collaborator who is told
/// about every row would learn to ignore the dot; both types that count are a
/// salon that needs a phone call or a call that already paid off.
class CollaboratorNotificationBell extends StatefulWidget {
  const CollaboratorNotificationBell({super.key});

  @override
  State<CollaboratorNotificationBell> createState() =>
      _CollaboratorNotificationBellState();
}

class _CollaboratorNotificationBellState
    extends State<CollaboratorNotificationBell> {
  int _unread = 0;
  Timer? _timer;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _refresh();

    // A minute matches the owner app's polling cadence. Faster would spend the
    // device's battery on a number that changes at most a few times a day.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final inbox = await CollaboratorApi.notifications(limit: 1);
    if (!mounted) return;

    if (inbox.importantCount != _unread) {
      setState(() => _unread = inbox.importantCount);
    }
  }

  Future<void> _open() async {
    // The bell sits in the shell's app bar, so this context belongs to the
    // navigator that hosts the tabs rather than to any one tab. That is the right
    // navigator to push from here: the inbox is not part of Home, and pushing it
    // into the Home tab would leave it there after the collaborator switched
    // away. See lib/widgets/tab_navigator.dart.
    if (_opening) return;
    _opening = true;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CollaboratorNotificationsScreen(onRead: _refresh),
      ),
    );

    _opening = false;
    // Coming back having read something should clear the dot immediately rather
    // than up to a minute later.
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return IconButton(
      onPressed: _open,
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            _unread > 0
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
            color: palette.textPrimary,
          ),
          if (_unread > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  _unread > 9 ? '9+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
