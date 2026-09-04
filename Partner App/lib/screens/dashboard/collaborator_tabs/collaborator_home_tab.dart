import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class CollaboratorHomeTab extends StatelessWidget {
  const CollaboratorHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.storefront,
            size: 80,
            color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkInfo : AppTheme.lightInfo),
          ),
          const SizedBox(height: 24),
          Text(
            'Ready to Onboard?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'Create a new salon profile, add services, and submit for SuperAdmin approval.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
              ),
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: () {
              // Future feature: Navigate to Salon Onboarding Flow
            },
            icon: Icon(Icons.add_business),
            label: Text('Onboard New Salon'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
