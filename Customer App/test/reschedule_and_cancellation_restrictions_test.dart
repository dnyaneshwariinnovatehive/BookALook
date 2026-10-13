import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/screens/my_bookings_screen.dart';
import 'package:customer_app/screens/reschedule_screen.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'dummy_token'});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
  });

  final standardUpcoming = {
    'id': 101,
    'appointment_date': '2026-10-15',
    'start_time': '11:00 AM',
    'status': 'confirmed',
    'total_amount': 1500,
    'advance_paid': 500,
    'balance_amount': 1000,
    'provider_name': 'Sarah',
    'rescheduled_from_id': null,
    'salon': {
      'id': 1,
      'name': 'Luxe Hair & Spa',
      'address': '123 MG Road',
      'phone': '9876543210',
      'cover_image': '',
    },
    'services': [
      {'name': 'Haircut', 'price': 1500},
    ],
    'can_cancel': true,
    'can_reschedule': true,
  };

  final rescheduledUpcoming = {
    'id': 102,
    'appointment_date': '2026-10-16',
    'start_time': '02:00 PM',
    'status': 'confirmed',
    'total_amount': 2000,
    'advance_paid': 600,
    'balance_amount': 1400,
    'provider_name': 'John',
    'rescheduled_from_id': 99, // Already rescheduled once!
    'salon': {
      'id': 1,
      'name': 'Luxe Hair & Spa',
      'address': '123 MG Road',
      'phone': '9876543210',
      'cover_image': '',
    },
    'services': [
      {'name': 'Haircut & Beard trim', 'price': 2000},
    ],
    'can_cancel': true,
    'can_reschedule': true,
  };

  group('MyBookingsScreen - Reschedule and Cancellation Restrictions', () {
    testWidgets('rescheduled appointment displays Rescheduled badge and disables reschedule & cancel with toasts', (tester) async {
      api.debugSetClient(
        MockClient((request) async {
          if (request.url.path.contains('/customer/appointments')) {
            return http.Response(
              jsonEncode({
                'upcoming': [rescheduledUpcoming],
                'past': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }),
      );

      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: MyBookingsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Shows Rescheduled badge
      expect(find.text('Rescheduled'), findsOneWidget);

      // Tap Reschedule button
      final rescheduleBtn = find.text('Reschedule');
      expect(rescheduleBtn, findsOneWidget);
      await tester.tap(rescheduleBtn);
      await tester.pumpAndSettle();

      // Toast feedback appears explaining it cannot be rescheduled again
      expect(
        find.text('This appointment has already been rescheduled once.'),
        findsOneWidget,
      );

      // Tap Cancel button
      final cancelBtn = find.text('Cancel');
      expect(cancelBtn, findsOneWidget);
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      // Toast feedback appears explaining it cannot be cancelled
      expect(
        find.text('Rescheduled appointments cannot be cancelled.'),
        findsOneWidget,
      );
    });

    testWidgets('standard appointment shows Scheduled badge and allows active actions', (tester) async {
      api.debugSetClient(
        MockClient((request) async {
          if (request.url.path.contains('/customer/appointments')) {
            return http.Response(
              jsonEncode({
                'upcoming': [standardUpcoming],
                'past': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }),
      );

      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: MyBookingsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Rescheduled'), findsNothing);
    });
  });

  group('RescheduleScreen - Multi-Slot Selection', () {
    testWidgets('selecting a slot highlights all consecutive slots required for the total service duration', (tester) async {
      api.debugSetClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.contains('/customer/appointments/101/reschedule-options')) {
            return http.Response(
              jsonEncode({
                'current_provider_id': 1,
                'current_date': '2026-10-18',
                'current_time': '10:00:00',
                'total_duration_minutes': 60, // 2 slots needed
                'providers': [
                  {
                    'id': 1,
                    'name': 'Sarah Master',
                    'eligible': true,
                  }
                ],
                'slots': [
                  {'time': '10:00 AM', 'available': true},
                  {'time': '10:30 AM', 'available': true},
                  {'time': '11:00 AM', 'available': true},
                ],
                'closed': false,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }),
      );

      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: RescheduleScreen(appointmentId: '101'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Provider and slots should load
      expect(find.text('Sarah Master'), findsOneWidget);
      expect(find.text('10:00 AM'), findsOneWidget);
      expect(find.text('10:30 AM'), findsOneWidget);
      expect(find.text('11:00 AM'), findsOneWidget);

      // Tap on 10:00 AM slot
      await tester.tap(find.text('10:00 AM'));
      await tester.pumpAndSettle();

      // Check that both slots are indicated as part of the booking
      expect(find.text('Slot 1 (Start)'), findsOneWidget);
      expect(find.text('Included'), findsOneWidget);

      // Verify the descriptive helper text indicates all 2 purple blocks together
      expect(
        find.text('All 2 purple blocks together are your 60 minute appointment, starting at 10:00 AM.'),
        findsOneWidget,
      );
    });
  });
}
