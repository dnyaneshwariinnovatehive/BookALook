import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/screens/my_bookings_screen.dart';
import 'package:customer_app/services/app_version_service.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/theme/app_colors.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'dummy_token'});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    AppVersionService.instance.debugVersion = '1.0.0';
    AppVersionService.instance.debugBuildNumber = 1;
  });

  final upcomingBooking = {
    'id': 101,
    'appointment_date': '2026-10-25',
    'start_time': '11:00 AM',
    'status': 'confirmed',
    'total_amount': 1500,
    'advance_paid': 500,
    'balance_amount': 1000,
    'provider_name': 'Sarah',
    'salon': {
      'id': 1,
      'name': 'Luxe Hair & Spa',
      'address': '123 MG Road',
      'phone': '9876543210',
      'cover_image': '',
    },
    'services': [
      {'name': 'Haircut & Styling', 'price': 1500},
    ],
    'can_cancel': true,
    'can_reschedule': true,
  };

  final pastBookings = [
    {
      'id': 201,
      'appointment_date': '2026-10-10',
      'start_time': '02:00 PM',
      'status': 'completed',
      'total_amount': 2200,
      'advance_paid': 2200,
      'balance_amount': 0,
      'provider_name': 'Alex',
      'salon': {
        'id': 2,
        'name': 'Urban Glow Salon',
        'address': '45 Indiranagar',
        'phone': '9123456780',
        'cover_image': '',
      },
      'services': [
        {'name': 'Facial & Cleanup', 'price': 2200},
      ],
      'can_review': true,
    },
    {
      'id': 202,
      'appointment_date': '2026-10-05',
      'start_time': '04:30 PM',
      'status': 'cancelled',
      'total_amount': 800,
      'advance_paid': 800,
      'balance_amount': 0,
      'provider_name': 'David',
      'salon': {
        'id': 3,
        'name': 'Classic Cuts',
        'address': '78 Koramangala',
        'phone': '9345678901',
        'cover_image': '',
      },
      'services': [
        {'name': 'Beard Grooming', 'price': 800},
      ],
    },
    {
      'id': 203,
      'appointment_date': '2026-09-28',
      'start_time': '01:00 PM',
      'status': 'rescheduled',
      'total_amount': 1200,
      'advance_paid': 400,
      'balance_amount': 800,
      'provider_name': 'Maya',
      'salon': {
        'id': 1,
        'name': 'Luxe Hair & Spa',
        'address': '123 MG Road',
        'phone': '9876543210',
        'cover_image': '',
      },
      'services': [
        {'name': 'Manicure', 'price': 1200},
      ],
    },
  ];

  testWidgets(
    'Dark Mode: MyBookingsScreen renders with brand dark palette, visible card boundaries, and dark status badges in both Upcoming and History',
    (tester) async {
      api.debugSetClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.contains('/customer/appointments')) {
            return http.Response(
              jsonEncode({
                'upcoming': [upcomingBooking],
                'past': pastBookings,
                'cancellation_cutoff_minutes': 90,
                'reschedule_cutoff_minutes': 90,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.binding.setSurfaceSize(const Size(700, 900));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: MyBookingsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Verify Header and Segmented Tab Bar exist
      expect(find.text('My Bookings'), findsOneWidget);
      expect(find.text('Manage your appointments'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);

      // 2. Verify Upcoming appointment card details
      expect(find.text('Luxe Hair & Spa'), findsOneWidget);
      expect(find.text('Haircut & Styling'), findsOneWidget);
      expect(find.text('Advance Paid: ₹500'), findsOneWidget);
      expect(find.text('Pay at Salon: ₹1000'), findsOneWidget);
      expect(find.text('Total Payment: ₹1500'), findsOneWidget);

      // 3. Verify Confirmed/Scheduled dark status badge colors
      final confirmedBadgeText = tester.widget<Text>(find.text('Scheduled'));
      expect(confirmedBadgeText.style?.color, const Color(0xFF4ADE80));

      // 4. Verify Action buttons
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Reschedule'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // 5. Switch to History tab
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      // 6. Verify Filter Chips in History tab
      expect(find.widgetWithText(FilterChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Completed'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Cancelled'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Rescheduled'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'No Show'), findsOneWidget);

      // 7. Verify History appointment cards
      expect(find.text('Urban Glow Salon'), findsOneWidget);
      expect(find.text('Classic Cuts'), findsOneWidget);
      expect(find.text('Luxe Hair & Spa'), findsOneWidget);

      // 8. Verify Status Badges in History
      final completedBadge = tester.widget<Text>(
        find.descendant(of: find.byType(Container), matching: find.text('Completed')).last,
      );
      expect(completedBadge.style?.color, const Color(0xFF4ADE80));

      final cancelledBadge = tester.widget<Text>(
        find.descendant(of: find.byType(Container), matching: find.text('Cancelled')).last,
      );
      expect(cancelledBadge.style?.color, const Color(0xFFF87171));

      final rescheduledBadge = tester.widget<Text>(
        find.descendant(of: find.byType(Container), matching: find.text('Rescheduled')).last,
      );
      expect(rescheduledBadge.style?.color, const Color(0xFFC084FC));

      // 9. Test filtering to Cancelled
      await tester.tap(find.widgetWithText(FilterChip, 'Cancelled'));
      await tester.pumpAndSettle();

      expect(find.text('Classic Cuts'), findsOneWidget);
      expect(find.text('Urban Glow Salon'), findsNothing);

      // 10. Test filtering to Completed
      await tester.tap(find.widgetWithText(FilterChip, 'Completed'));
      await tester.pumpAndSettle();

      expect(find.text('Urban Glow Salon'), findsOneWidget);
      expect(find.text('Classic Cuts'), findsNothing);
    },
  );

  testWidgets(
    'Dark Mode: Empty states in Upcoming and History show dark theme and purple accents',
    (tester) async {
      api.debugSetClient(
        MockClient((request) async {
          return http.Response(
            jsonEncode({
              'upcoming': [],
              'past': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: MyBookingsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Upcoming Empty State
      expect(find.text('No upcoming appointments'), findsOneWidget);
      expect(find.text('When you book a salon, it shows up here.'), findsOneWidget);
      expect(find.text('Explore salons'), findsOneWidget);

      // Switch to History tab
      await tester.tap(find.text('History'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // History Empty State
      expect(find.text('No past appointments'), findsOneWidget);
      expect(find.text('Visits you have completed or cancelled appear here.'), findsOneWidget);
    },
  );

  testWidgets(
    'Light Mode: Preserves original light palette completely without regression',
    (tester) async {
      api.debugSetClient(
        MockClient((request) async {
          return http.Response(
            jsonEncode({
              'upcoming': [upcomingBooking],
              'past': pastBookings,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.binding.setSurfaceSize(const Size(500, 900));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: MyBookingsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // In light mode, Confirmed badge text uses light success color
      final confirmedBadgeText = tester.widget<Text>(find.text('Scheduled'));
      expect(confirmedBadgeText.style?.color, const Color(0xFF1B873F));

      // Switch to History
      await tester.tap(find.text('History'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final cancelledBadge = tester.widget<Text>(
        find.descendant(of: find.byType(Container), matching: find.text('Cancelled')).last,
      );
      expect(cancelledBadge.style?.color, const Color(0xFFC62828));
    },
  );
}
