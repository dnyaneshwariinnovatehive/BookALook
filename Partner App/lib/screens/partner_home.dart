import 'package:flutter/widgets.dart';

import 'dashboard/collaborator_dashboard.dart';
import 'dashboard/salon_selection_screen.dart';
import 'dashboard/service_provider_dashboard.dart';

/// The screen a signed-in partner lands on, decided by their role.
///
/// The Partner App serves three kinds of account, each with its own home, and
/// this is the one place that knows which is which. Takes the verify-otp
/// response — the same map that is stored as `auth_state` — and returns null
/// for a role the app does not serve, so the caller can say so rather than
/// leaving the partner on a screen that does nothing.
Widget? partnerHomeFor(Map<String, dynamic> response) {
  return switch (response['role']) {
    'admin' => SalonSelectionScreen(salons: response['salons'] ?? []),
    'service_provider' => ServiceProviderDashboard(
        salon: response['salon'] ?? {},
        provider: response['provider'] ?? {},
        user: response['user'] ?? {},
      ),
    'collaborator' => const CollaboratorDashboardScreen(),
    _ => null,
  };
}
