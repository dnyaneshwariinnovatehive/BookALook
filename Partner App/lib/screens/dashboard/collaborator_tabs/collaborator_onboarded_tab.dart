import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class CollaboratorOnboardedTab extends StatelessWidget {
  const CollaboratorOnboardedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.fact_check_outlined,
            size: 80,
            color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess),
          ),
          const SizedBox(height: 24),
          const Text(
            'My Onboarded Salons',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'A list of all salons you have onboarded, tracking their Pending, Approved, or Rejected status.',
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
