import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../phone_screen.dart';

class CollaboratorProfileTab extends StatefulWidget {
  const CollaboratorProfileTab({super.key});

  @override
  State<CollaboratorProfileTab> createState() => _CollaboratorProfileTabState();
}

class _CollaboratorProfileTabState extends State<CollaboratorProfileTab> {
  
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const PhoneScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blueGrey,
            child: Icon(Icons.person, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 24),
          const Text(
            'Collaborator Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'View and manage your personal profile and contact details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Log Out'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              backgroundColor: Colors.red[50],
              foregroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
