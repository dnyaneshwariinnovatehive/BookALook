import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_restricted_view.dart';
import '../my_bookings_screen.dart';

class BookingsTab extends StatelessWidget {
  final bool isGuest;
  final GlobalKey<MyBookingsScreenState>? bookingsKey;

  const BookingsTab({Key? key, required this.isGuest, this.bookingsKey}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return const GuestRestrictedView(
        title: 'Login or Sign Up',
        message: 'Please login or sign up to view and manage your salon bookings.',
        tabIndex: 2,
        icon: Icons.calendar_month,
      );
    }

    return MyBookingsScreen(key: bookingsKey);
  }
}

