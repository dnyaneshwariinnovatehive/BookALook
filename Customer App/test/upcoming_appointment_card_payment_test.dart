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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'dummy_token'});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    AppVersionService.instance.debugVersion = '1.0.0';
    AppVersionService.instance.debugBuildNumber = 1;
  });

  final upcomingBooking = {
    'id': 101,
    'appointment_date': '2026-10-15',
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

  testWidgets(
    'Upcoming booking card displays Advance Paid, Pay at Salon, and Total Payment in one strip without the large Total Payable button',
    (tester) async {
      api.debugSetClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.contains('/customer/appointments')) {
            return http.Response(
              jsonEncode({
                'upcoming': [upcomingBooking],
                'past': [],
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

      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: MyBookingsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Salon name and services are displayed
      expect(find.text('Luxe Hair & Spa'), findsOneWidget);
      expect(find.text('Haircut & Styling'), findsOneWidget);

      // Large "Total Payable" button is removed completely
      expect(find.text('Total Payable'), findsNothing);

      // Payment strip contains all 3 variables in one line: Advance Paid, Pay at Salon, Total Payment
      expect(find.text('Advance Paid: ₹500'), findsOneWidget);
      expect(find.text('Pay at Salon: ₹1000'), findsOneWidget);
      expect(find.text('Total Payment: ₹1500'), findsOneWidget);

      // Action buttons are intact
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Reschedule'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );
}
