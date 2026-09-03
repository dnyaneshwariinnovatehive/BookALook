import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'dashboard_screen.dart';
import '../registration/admin_registration_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../phone_screen.dart';

class SalonSelectionScreen extends StatelessWidget {
  final List<dynamic> salons;
  const SalonSelectionScreen({super.key, required this.salons});

  void _selectSalon(BuildContext context, dynamic salon) {
    if (salon['status'] == 'pending_approval') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Approval Pending', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text(
            'This salon is pending for approval. Contact on +91 9876543210 for more info.',
            style: TextStyle(color: AppTheme.lightTextBody, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // In a real app, you would save the selected salon ID in a state management solution or SharedPreferences
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => DashboardScreen(salonData: salon)),
      (route) => false,
    );
  }

  void _addNewSalon(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AdminRegistrationScreen()),
    );
  }

  void _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const PhoneScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('bookalook', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, fontFamily: 'InstagramLogo')), // Fallback to standard bold if font not found
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () => _logout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Text(
                'Switch Account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: salons.length + 1, // +1 for "Add new salon"
                itemBuilder: (context, index) {
                  if (index < salons.length) {
                    final salon = salons[index];
                    final isPending = salon['status'] == 'pending_approval';

                    return InkWell(
                      onTap: () => _selectSalon(context, salon),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: AppTheme.lightBorder,
                              backgroundImage: salon['cover_photo_url'] != null
                                  ? NetworkImage(salon['cover_photo_url'])
                                  : null,
                              child: salon['cover_photo_url'] == null
                                  ? Text(
                                      salon['name']?.substring(0, 1).toUpperCase() ?? 'S',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading, fontSize: 24),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    salon['name'] ?? 'Unnamed Salon',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(salon['city'] ?? 'Unknown location', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                      if (isPending) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('Pending', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 24),
                          ],
                        ),
                      ),
                    );
                  } else {
                    // Add new salon button
                    return InkWell(
                      onTap: () => _addNewSalon(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.transparent,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 1.5),
                                ),
                                child: const Center(
                                  child: Icon(Icons.add, color: Colors.black, size: 28),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              'Add new salon',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
