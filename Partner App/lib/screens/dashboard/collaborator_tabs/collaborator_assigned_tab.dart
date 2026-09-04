import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class CollaboratorAssignedTab extends StatelessWidget {
  const CollaboratorAssignedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_ind_outlined,
            size: 80,
            color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkWarning : AppTheme.lightWarning),
          ),
          const SizedBox(height: 24),
          const Text(
            'Assigned Salons & Alerts',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'Manage salons assigned to you by the SuperAdmin from the public enquiry form, and receive subscription alerts.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
