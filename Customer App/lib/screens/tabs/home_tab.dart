import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class HomeTab extends StatelessWidget {
  final bool isGuest;

  const HomeTab({Key? key, required this.isGuest}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.lightAccentSoft,
                  child: Icon(Icons.person, color: AppTheme.accentColor),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isGuest ? 'Hi Guest 👋' : 'Welcome back 👋',
                        style: TextStyle(
                          color: AppTheme.lightTextBody,
                          fontSize: 14,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            'Select Location',
                            style: TextStyle(
                              color: AppTheme.lightTextHeading,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down, size: 20, color: AppTheme.accentColor),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.lightBorder),
                  ),
                  child: Icon(Icons.notifications_none, color: AppTheme.lightTextHeading),
                ),
              ],
            ),
            SizedBox(height: 24),

            // Search Bar
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: AppTheme.lightBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: AppTheme.lightTextBody),
                        SizedBox(width: 8),
                        Text(
                          'Search salons, services...',
                          style: TextStyle(color: AppTheme.lightTextLight, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.lightBorder),
                  ),
                  child: Icon(Icons.filter_list, color: AppTheme.lightTextHeading),
                ),
              ],
            ),
            SizedBox(height: 24),

            // Promos Placeholder
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.lightAccentSoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Icon(Icons.local_offer, size: 48, color: AppTheme.accentColor.withOpacity(0.5)),
                  SizedBox(height: 12),
                  Text(
                    'No active offers right now',
                    style: TextStyle(
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'Check back later for exciting spa and salon deals!',
                    style: TextStyle(color: AppTheme.lightTextBody),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),

            // Categories Placeholder
            Text(
              'Categories',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.lightBorder, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  'No categories available yet.',
                  style: TextStyle(color: AppTheme.lightTextBody),
                ),
              ),
            ),
            SizedBox(height: 32),

            // Next Appointment Placeholder
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.lightAccentSoft.withOpacity(0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.lightAccentSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'YOUR NEXT APPOINTMENT',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Text(
                        isGuest ? 'Sign in to see your appointments' : 'No upcoming appointments',
                        style: TextStyle(color: AppTheme.lightTextBody, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),

            // Book Again Placeholder
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Book Again',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
                ),
                Text(
                  'See All',
                  style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Center(
                child: Text(
                  isGuest ? 'Sign in to view your past bookings' : 'You have no previous bookings to show here.',
                  style: TextStyle(color: AppTheme.lightTextBody),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            SizedBox(height: 40), // Bottom padding
          ],
        ),
      ),
    );
  }
}
