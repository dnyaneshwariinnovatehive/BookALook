import 'package:flutter/material.dart';

import '../../services/onboarding_draft_store.dart';
import 'collaborator_tabs/collaborator_assigned_tab.dart';
import 'collaborator_tabs/collaborator_home_tab.dart';
import 'collaborator_tabs/collaborator_onboarded_tab.dart';
import 'collaborator_tabs/collaborator_profile_tab.dart';

class CollaboratorDashboardScreen extends StatefulWidget {
  const CollaboratorDashboardScreen({super.key});

  @override
  State<CollaboratorDashboardScreen> createState() => _CollaboratorDashboardScreenState();
}

class _CollaboratorDashboardScreenState extends State<CollaboratorDashboardScreen> {
  int _currentIndex = 0;

  static const _mySalonsTab = 1;
  static const _assignedTab = 2;

  @override
  void initState() {
    super.initState();
    // Starts the draft store the moment a collaborator is in the app, so a
    // submission queued during yesterday's visit goes out today without anyone
    // opening the tab it lives in.
    OnboardingDraftStore.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      CollaboratorHomeTab(
        onGoToAssigned: () => setState(() => _currentIndex = _assignedTab),
        onGoToMySalons: () => setState(() => _currentIndex = _mySalonsTab),
      ),
      const CollaboratorOnboardedTab(),
      const CollaboratorAssignedTab(),
      const CollaboratorProfileTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collaborator Dashboard'),
      ),
      // Rebuilt per tab rather than kept alive, so each list refetches when the
      // collaborator returns to it — which after a salon visit it should.
      body: tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check), label: 'My Salons'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'Assigned'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
