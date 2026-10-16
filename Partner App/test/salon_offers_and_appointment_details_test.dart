import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/appointment_details_screen.dart';

void main() {
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  Widget wrapWithMaterial(Widget widget) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(500, 1000)),
        child: widget,
      ),
    );
  }

  group('Appointment Details Screen — Offer & Discount Tests', () {
    testWidgets('1. Displays dedicated Offer & Discount section with First-Time Customer Offer Applied badge', (tester) async {
      final appointment = {
        'id': 'apt-test-1',
        'status': 'scheduled',
        'appointment_date': '2026-10-20',
        'start_time': '10:00:00',
        'end_time': '10:30:00',
        'total_amount': '400.00',
        'advance_amount': '80.00',
        'balance_amount': '320.00',
        'first_time_offer_id': 'offer-uuid-1234',
        'first_time_discount_amount': '100.00',
        'first_time_offer': {
          'id': 'offer-uuid-1234',
          'name': 'Salon Welcome 20% Off',
          'scope': 'new_to_salon',
          'discount_type': 'percentage',
          'discount_value': '20.00',
        },
        'customer': {
          'name': 'Aarav Patel',
          'phone': '9876543210',
        },
        'services': [
          {
            'price_at_booking': '400.00',
            'original_service_price': '500.00',
            'first_time_discount_amount': '100.00',
            'service': {
              'template': {
                'name': 'Deluxe Haircut',
              },
            },
          },
        ],
      };

      await tester.pumpWidget(wrapWithMaterial(
        AppointmentDetailsScreen(
          appointment: appointment,
          salonId: 'salon-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Check section header
      expect(find.text('Offer & Discount'), findsOneWidget);

      // Check badge
      expect(find.text('First-Time Customer Offer Applied'), findsOneWidget);

      // Check offer name
      expect(find.text('Salon Welcome 20% Off'), findsOneWidget);

      // Check scope label
      expect(find.text('First Booking at this Salon'), findsOneWidget);

      // Check discount badge
      expect(find.text('20.00% OFF'), findsOneWidget);

      // Check offer id
      expect(find.textContaining('offer-uuid-1234'), findsOneWidget);

      // Check line item breakdown
      expect(find.text('Deluxe Haircut'), findsAtLeastNWidgets(1));
      expect(find.text('₹500.00'), findsAtLeastNWidgets(1));
      expect(find.text('-₹100.0'), findsAtLeastNWidgets(1));
      expect(find.text('₹400.00'), findsAtLeastNWidgets(1));

      // Check total offer savings
      expect(find.text('Total Offer Savings'), findsOneWidget);

      // Check billing reconciliation
      expect(find.text('Billing Information'), findsOneWidget);
      expect(find.text('₹400.00'), findsAtLeastNWidgets(1));
      expect(find.textContaining('320'), findsOneWidget);
    });

    testWidgets('2. Displays No offer applied when appointment has no offer or discount', (tester) async {
      final appointment = {
        'id': 'apt-test-2',
        'status': 'scheduled',
        'appointment_date': '2026-10-20',
        'start_time': '11:00:00',
        'end_time': '11:30:00',
        'total_amount': '500.00',
        'advance_amount': '100.00',
        'balance_amount': '400.00',
        'first_time_offer_id': null,
        'first_time_discount_amount': '0.00',
        'first_time_offer': null,
        'customer': {
          'name': 'Pooja Sharma',
          'phone': '9876543211',
        },
        'services': [
          {
            'price_at_booking': '500.00',
            'original_service_price': '500.00',
            'first_time_discount_amount': '0.00',
            'service': {
              'template': {
                'name': 'Basic Facial',
              },
            },
          },
        ],
      };

      await tester.pumpWidget(wrapWithMaterial(
        AppointmentDetailsScreen(
          appointment: appointment,
          salonId: 'salon-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Check section header exists
      expect(find.text('Offer & Discount'), findsOneWidget);

      // Check empty state
      expect(find.text('No offer applied'), findsOneWidget);
      expect(find.text('Standard service pricing was applied at booking.'), findsOneWidget);

      // Make sure first time badge is NOT shown
      expect(find.text('First-Time Customer Offer Applied'), findsNothing);
    });

    testWidgets('3. Legacy appointments without offer fields render cleanly without errors', (tester) async {
      final legacyAppointment = {
        'id': 'legacy-apt-99',
        'status': 'completed',
        'appointment_date': '2025-01-01',
        'start_time': '15:00:00',
        'end_time': '15:30:00',
        'total_amount': '300.00',
        'advance_amount': '0.00',
        'balance_amount': '300.00',
        'customer': {
          'name': 'Rahul Verma',
          'phone': '9876543212',
        },
        'services': [],
      };

      await tester.pumpWidget(wrapWithMaterial(
        AppointmentDetailsScreen(
          appointment: legacyAppointment,
          salonId: 'salon-1',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Appointment Details'), findsAtLeastNWidgets(1));
      expect(find.text('Offer & Discount'), findsOneWidget);
      expect(find.text('No offer applied'), findsOneWidget);
      expect(find.text('Billing Information'), findsOneWidget);
      expect(find.textContaining('300'), findsAtLeastNWidgets(1));
    });
  });
}
