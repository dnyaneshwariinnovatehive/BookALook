import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_restricted_view.dart';
import '../my_bookings_screen.dart';

class BookingsTab extends StatelessWidget {
  final bool isGuest;

  const BookingsTab({Key? key, required this.isGuest}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return GuestRestrictedView(
        title: 'Sign In Required',
        message: 'Please sign in to view and manage your salon bookings.',
        icon: Icons.calendar_month,
      );
    }

    // Wrap MyBookingsScreen inside a basic scaffold if it doesn't fit or just return it directly.
    // Since MyBookingsScreen is a full Scaffold itself, we can return it directly as a tab content.
    // The only issue might be double AppBars if the parent tab view has one, but typically tabs don't.
    // If double AppBars appear, MyBookingsScreen's appbar can be refactored, but returning it directly is standard.
    return MyBookingsScreen();
  }
}

