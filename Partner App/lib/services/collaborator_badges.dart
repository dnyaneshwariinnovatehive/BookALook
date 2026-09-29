import 'package:flutter/foundation.dart';

import 'onboarding_draft_store.dart';

/// Counts for the bottom navigation badges.
///
/// The counts the nav bar needs are already known by the tabs that own them —
/// Assigned knows how many salons are waiting, My Salons knows how many are
/// stuck in approval. But those counts lived inside each tab's private State,
/// and the nav bar is a sibling of the tabs rather than a parent, so there was
/// nowhere to read them from. Without a shared home the only way a
/// collaborator could find out they had work was to open the tab and look.
///
/// Tabs push their counts here as they load; the nav bar listens. Nothing is
/// refetched — this only relays numbers the tabs already have.
///
/// [queuedDrafts] is not set by any tab. It is read straight off
/// [OnboardingDraftStore], which is a [ChangeNotifier] that outlives every
/// tab, and so cannot be lost by a tab being rebuilt.
class CollaboratorBadges extends ChangeNotifier {
  int _assignedCount = 0;
  int _awaitingApproval = 0;
  int _sentBack = 0;

  /// Salons SuperAdmin has handed this collaborator to onboard.
  int get assignedCount => _assignedCount;

  /// Submitted and waiting on SuperAdmin. Not actionable by the collaborator,
  /// but worth surfacing: it is the answer to "did my work get through?".
  int get awaitingApproval => _awaitingApproval;

  /// Sent back for correction. Actionable, so it counts toward the My Salons
  /// badge — a collaborator who does not see this will not go looking.
  int get sentBack => _sentBack;

  int get mySalonsCount => _awaitingApproval + _sentBack;

  /// Finished submissions still on this device, waiting for signal.
  int queuedDrafts(OnboardingDraftStore store) => store.queuedCount;

  void reportAssigned(int count) {
    if (count == _assignedCount) return;
    _assignedCount = count;
    notifyListeners();
  }

  void reportMySalons({required int awaitingApproval, required int sentBack}) {
    if (awaitingApproval == _awaitingApproval && sentBack == _sentBack) return;
    _awaitingApproval = awaitingApproval;
    _sentBack = sentBack;
    notifyListeners();
  }
}
