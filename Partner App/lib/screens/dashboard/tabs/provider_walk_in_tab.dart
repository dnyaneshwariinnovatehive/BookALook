import 'package:flutter/material.dart';
import '../../walk_in_screen.dart';

/// The provider's "Add walk-in" tab.
///
/// The form itself is shared with the admin flow — the only difference is who
/// ends up serving, which the API decides from the caller. Keeping one screen
/// means a change to pricing or service selection cannot fix one role and
/// break the other.
class ProviderWalkInTab extends StatelessWidget {
  final Map<String, dynamic> salon;
  final Map<String, dynamic> provider;

  /// Called after a walk-in is created, so the home tab can refresh.
  final VoidCallback? onCreated;

  const ProviderWalkInTab({
    Key? key,
    required this.salon,
    required this.provider,
    this.onCreated,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WalkInScreen(
      salonId: salon['id'].toString(),
      embedded: true,
      onCreated: onCreated,
    );
  }
}
