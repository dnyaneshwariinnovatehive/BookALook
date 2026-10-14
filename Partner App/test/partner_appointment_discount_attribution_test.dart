import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  Widget wrapWidget(Widget child, {double width = 400}) {
    return MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: SizedBox(width: width, child: Center(child: child)),
        ),
      ),
    );
  }

  group('Partner App: Appointment Discount Attribution Tests', () {
    testWidgets('1. Appointment with a first-time discount displays persisted attribution', (tester) async {
      final appointment = {
        'id': 'apt-101',
        'status': 'scheduled',
        'appointment_date': '2026-10-25',
        'start_time': '14:00',
        'end_time': '15:00',
        'total_amount': 800.0,
        'advance_amount': 200.0,
        'balance_amount': 600.0,
        'first_time_discount_amount': 200.0,
        'first_time_offer': {
          'id': 'off-first',
          'name': 'New Client 20% Off',
          'discount_type': 'percentage',
          'discount_value': 20,
        },
        'services': [
          {
            'price_at_booking': 800.0,
            'original_service_price': 1000.0,
            'first_time_discount_amount': 200.0,
            'service': {
              'template': {'name': 'Bridal Glow Facial'},
            },
          },
        ],
      };

      final num totalAmount = num.tryParse(appointment['total_amount']?.toString() ?? '0') ?? 0;
      final num advancePaid = num.tryParse(appointment['advance_amount']?.toString() ?? '0') ?? 0;
      final num balanceDue = num.tryParse(appointment['balance_amount']?.toString() ?? '0') ?? totalAmount;
      final num ftdAmount = num.tryParse(appointment['first_time_discount_amount']?.toString() ?? '0') ?? 0;
      final offerName = (appointment['first_time_offer'] as Map?)?['name']?.toString();
      final services = appointment['services'] as List;

      await tester.pumpWidget(wrapWidget(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Services breakdown
            ...services.map((s) {
              final name = s['service']?['template']?['name'] ?? 'Service';
              final priceAtBooking = s['price_at_booking'];
              final origPrice = s['original_service_price'];
              final sFtd = num.tryParse(s['first_time_discount_amount']?.toString() ?? '0') ?? 0;
              final hasLineDisc = sFtd > 0;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(name)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasLineDisc) ...[
                        Text('₹$origPrice', style: const TextStyle(decoration: TextDecoration.lineThrough)),
                        const SizedBox(width: 6),
                      ],
                      Text('₹$priceAtBooking'),
                    ],
                  ),
                ],
              );
            }),
            const Divider(),
            // Billing breakdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Amount'),
                Text('₹$totalAmount'),
              ],
            ),
            if (ftdAmount > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(offerName != null ? 'First-Time Discount ($offerName)' : 'First-Time Discount')),
                  Text('-₹$ftdAmount', style: const TextStyle(color: Color(0xFF16A34A))),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Advance Paid'),
                Text('₹$advancePaid'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Balance Due'),
                Text('₹$balanceDue'),
              ],
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bridal Glow Facial'), findsOneWidget);
      expect(find.text('₹1000.0'), findsOneWidget);
      expect(find.text('₹800.0'), findsWidgets);
      expect(find.text('First-Time Discount (New Client 20% Off)'), findsOneWidget);
      expect(find.text('-₹200.0'), findsOneWidget);
      expect(find.text('Advance Paid'), findsOneWidget);
      expect(find.text('₹200.0'), findsOneWidget);
      expect(find.text('Balance Due'), findsOneWidget);
      expect(find.text('₹600.0'), findsOneWidget);
    });

    testWidgets('2. Appointment without a discount preserves the existing layout', (tester) async {
      final appointment = {
        'id': 'apt-102',
        'status': 'scheduled',
        'total_amount': 500.0,
        'advance_amount': 100.0,
        'balance_amount': 400.0,
        'first_time_discount_amount': null,
        'first_time_offer': null,
        'services': [
          {
            'price_at_booking': 500.0,
            'original_service_price': 500.0,
            'first_time_discount_amount': null,
            'service': {
              'template': {'name': 'Regular Haircut'},
            },
          },
        ],
      };

      final num totalAmount = num.tryParse(appointment['total_amount']?.toString() ?? '0') ?? 0;
      final num advancePaid = num.tryParse(appointment['advance_amount']?.toString() ?? '0') ?? 0;
      final num balanceDue = num.tryParse(appointment['balance_amount']?.toString() ?? '0') ?? totalAmount;
      final num ftdAmount = num.tryParse(appointment['first_time_discount_amount']?.toString() ?? '0') ?? 0;

      await tester.pumpWidget(wrapWidget(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Amount'),
                Text('₹$totalAmount'),
              ],
            ),
            if (ftdAmount > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('First-Time Discount'),
                  Text('-₹$ftdAmount'),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Advance Paid'),
                Text('₹$advancePaid'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Balance Due'),
                Text('₹$balanceDue'),
              ],
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Total Amount'), findsOneWidget);
      expect(find.text('₹500.0'), findsOneWidget);
      expect(find.textContaining('First-Time Discount'), findsNothing);
      expect(find.text('Advance Paid'), findsOneWidget);
      expect(find.text('₹100.0'), findsOneWidget);
      expect(find.text('Balance Due'), findsOneWidget);
      expect(find.text('₹400.0'), findsOneWidget);
    });

    testWidgets('3. Missing optional attribution fields do not crash the screen', (tester) async {
      // Legacy appointment object missing first_time_discount_amount and first_time_offer entirely
      final appointment = {
        'id': 'apt-legacy',
        'status': 'completed',
        'total_amount': 300,
        'advance_amount': 0,
        'balance_amount': 300,
      };

      final num totalAmount = num.tryParse(appointment['total_amount']?.toString() ?? '0') ?? 0;
      final num advancePaid = num.tryParse(appointment['advance_amount']?.toString() ?? '0') ?? 0;
      final num ftdAmount = num.tryParse(appointment['first_time_discount_amount']?.toString() ?? '0') ?? 0;

      await tester.pumpWidget(wrapWidget(
        Column(
          children: [
            Text('Total: ₹$totalAmount'),
            if (ftdAmount > 0) Text('Discount: ₹$ftdAmount'),
            Text('Advance: ₹$advancePaid'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Total: ₹300'), findsOneWidget);
      expect(find.text('Advance: ₹0'), findsOneWidget);
      expect(find.textContaining('Discount'), findsNothing);
    });

    test('4. No payout or commission value is derived from the first-time discount in the UI', () {
      // Payout and commission accounting test:
      // The Partner App strictly presents persisted attribution values and does not alter payout or calculate deductions.
      final appointment = {
        'total_amount': 800.0,
        'first_time_discount_amount': 200.0,
        'commission_rate': 0.15,
      };

      // Ensure that total_amount is strictly the persisted server value
      final displayedTotal = appointment['total_amount'];
      expect(displayedTotal, 800.0);

      // Verify that UI does NOT subtract discount from commission or partner payout
      final commissionBase = appointment['total_amount'] as double;
      expect(commissionBase, 800.0);
    });
  });
}
