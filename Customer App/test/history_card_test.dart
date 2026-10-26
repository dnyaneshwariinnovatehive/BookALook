import 'dart:convert';

import 'package:customer_app/screens/my_bookings_screen.dart';
import 'package:customer_app/services/app_version_service.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The History card: one clear action at the bottom — "Rate your experience"
/// until the visit is rated, then "View invoice".
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'dummy_token'});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    AppVersionService.instance.debugVersion = '1.0.0';
    AppVersionService.instance.debugBuildNumber = 1;
  });

  Map<String, dynamic> booking(int id, {String status = 'completed', Map<String, dynamic>? review, bool canReview = false, bool invoice = false}) => {
        'id': id,
        'appointment_date': '2026-10-10',
        'start_time': '14:00:00',
        'status': status,
        'total_amount': 2200,
        'salon': {'id': id, 'name': 'Salon $id', 'cover_image': ''},
        'services': [
          {'name': 'Facial'},
          {'name': 'Haircut'},
          {'name': 'Manicure'},
        ],
        'can_review': canReview,
        if (review != null) 'review': review,
        if (invoice) 'invoice': {'url': 'https://example.com/i/$id', 'number': 'BAL-$id'},
      };

  Future<void> pumpHistory(WidgetTester tester, List<Map<String, dynamic>> past) async {
    api.debugSetClient(MockClient((request) async {
      if (request.url.path.contains('/customer/appointments')) {
        return http.Response(jsonEncode({'upcoming': [], 'past': past}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    }));

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const Scaffold(body: MyBookingsScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
  }

  testWidgets('an unrated completed visit offers "Rate your experience"', (tester) async {
    await pumpHistory(tester, [booking(1, canReview: true, invoice: true)]);

    final button = find.byKey(const ValueKey('history_rate_button'));
    expect(button, findsOneWidget);
    expect(find.text('Rate your experience'), findsOneWidget);
    // Rating comes first; the invoice button replaces it once rated.
    expect(find.byKey(const ValueKey('history_invoice_button')), findsNothing);

    final label = tester.widget<Text>(find.text('Rate your experience'));
    expect(label.style?.fontWeight, FontWeight.w800);
  });

  testWidgets('a rated visit shows its rating and "View invoice" in the same place', (tester) async {
    await pumpHistory(tester, [
      booking(2, review: {'rating': 4, 'comment': 'Lovely', 'age_label': '2 days ago'}, invoice: true),
    ]);

    expect(find.byKey(const ValueKey('history_invoice_button')), findsOneWidget);
    expect(find.text('View invoice'), findsOneWidget);
    expect(find.byKey(const ValueKey('history_rate_button')), findsNothing);
    expect(find.text('Rated'), findsOneWidget);
  });

  testWidgets('the card keeps the essentials readable', (tester) async {
    await pumpHistory(tester, [booking(3, canReview: true)]);

    expect(find.text('Salon 3'), findsOneWidget);
    expect(find.text('Facial, Haircut +1 more'), findsOneWidget);
    expect(find.textContaining('2:00 PM'), findsOneWidget);
    expect(find.text('₹2,200'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
  });

  testWidgets('a cancelled visit has no rate or invoice button', (tester) async {
    await pumpHistory(tester, [booking(4, status: 'cancelled')]);

    expect(find.byKey(const ValueKey('history_rate_button')), findsNothing);
    expect(find.byKey(const ValueKey('history_invoice_button')), findsNothing);
    expect(find.text('Report issue'), findsOneWidget);
  });
}
