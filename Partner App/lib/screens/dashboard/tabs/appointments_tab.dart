import 'package:flutter/material.dart';
import '../../provider_dashboard_screen.dart';

class AppointmentsTab extends StatelessWidget {
  final String salonId;
  const AppointmentsTab({super.key, required this.salonId});

  @override
  Widget build(BuildContext context) {
    // We return ProviderDashboardScreen directly as it has its own Scaffold and AppBar.
    // ProviderDashboardScreen was built to display appointments for the salon.
    return ProviderDashboardScreen(salonId: salonId);
  }
}
