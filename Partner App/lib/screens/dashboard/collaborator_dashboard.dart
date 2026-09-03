import 'package:flutter/material.dart';

import 'collaborator_tabs/collaborator_home_tab.dart';
import 'collaborator_tabs/collaborator_onboarded_tab.dart';
import 'collaborator_tabs/collaborator_assigned_tab.dart';
import 'collaborator_tabs/collaborator_profile_tab.dart';

class CollaboratorDashboardScreen extends StatefulWidget {
  const CollaboratorDashboardScreen({super.key});

  @override
  State<CollaboratorDashboardScreen> createState() => _CollaboratorDashboardScreenState();
}

class _CollaboratorDashboardScreenState extends State<CollaboratorDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const CollaboratorHomeTab(),
    const CollaboratorOnboardedTab(),
    const CollaboratorAssignedTab(),
    const CollaboratorProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collaborator Dashboard'),
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.fact_check),
            label: 'My Salons',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Assigned',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
