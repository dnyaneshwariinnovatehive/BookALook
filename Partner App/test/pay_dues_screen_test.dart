import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partner_app/screens/dashboard/more/pay_dues_screen.dart';
import 'package:partner_app/services/payroll_api.dart';
import 'package:partner_app/widgets/payment_qr_card.dart';

void main() {
  SalonPayoutRecord owing({PayoutPaymentInfo? payment}) => SalonPayoutRecord(
        id: 'payout-1',
        cycleType: 'monthly',
        cycleLabel: 'October 2026',
        cycleStart: '2026-10-01',
        cycleEnd: '2026-10-31',
        appointments: 1,
        revenue: 5000,
        advancesHeld: 200,
        billingType: 'commission',
        billingLabel: 'Commission Model',
        commissionPercentage: 20,
        commissionDeducted: 1000,
        walletRedeemed: 0,
        netAmount: -800,
        salonOwes: true,
        amountDue: 800,
        payment: payment,
        status: 'pending',
      );

  Future<PaymentDetails> details() async =>
      const PaymentDetails(upiId: 'bookalook@upi', payeeName: 'BookALook Pvt Ltd');

  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  Future<XFile?> pick() async => XFile.fromData(png, name: 'paid.png');

  Future<List<bool?>> open(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    final results = <bool?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => results.add(await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('shows what is owed and where to pay', (tester) async {
    await open(tester, PayDuesScreen(salonId: 's1', payout: owing(), loadDetails: details));

    expect(find.text('You owe ₹800.00'), findsOneWidget);
    expect(find.text('Pay ₹800'), findsOneWidget);
    expect(find.text('bookalook@upi'), findsOneWidget);
    expect(find.text('to BookALook Pvt Ltd'), findsOneWidget);
  });

  testWidgets('needs the screenshot before sending', (tester) async {
    var calls = 0;
    await open(
      tester,
      PayDuesScreen(
        salonId: 's1',
        payout: owing(),
        loadDetails: details,
        submit: ({required salonId, required payoutId, required screenshotBytes, required screenshotName, transactionId, note}) async {
          calls++;
          return const PayoutPaymentInfo(id: 'x', amount: 800, status: 'pending');
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pay_dues_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Upload the screenshot of your payment first.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('sends the screenshot and reference, then closes', (tester) async {
    final sent = <Map<String, Object?>>[];
    final results = await open(
      tester,
      PayDuesScreen(
        salonId: 's1',
        payout: owing(),
        loadDetails: details,
        pickImage: pick,
        submit: ({required salonId, required payoutId, required screenshotBytes, required screenshotName, transactionId, note}) async {
          sent.add({'salon': salonId, 'payout': payoutId, 'name': screenshotName, 'utr': transactionId, 'bytes': screenshotBytes.length});
          return const PayoutPaymentInfo(id: 'x', amount: 800, status: 'pending');
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pay_dues_pick')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pay_dues_utr')), 'UTR123');
    await tester.tap(find.byKey(const ValueKey('pay_dues_submit')));
    await tester.pumpAndSettle();

    expect(sent.single['salon'], 's1');
    expect(sent.single['payout'], 'payout-1');
    expect(sent.single['utr'], 'UTR123');
    expect(sent.single['bytes'], png.length);
    expect((sent.single['name'] as String).isNotEmpty, isTrue);
    expect(results, [true]);
  });

  testWidgets('shows why the last payment was turned back', (tester) async {
    await open(
      tester,
      PayDuesScreen(
        salonId: 's1',
        payout: owing(payment: const PayoutPaymentInfo(id: 'p', amount: 800, status: 'rejected', rejectionReason: 'Received ₹500 of ₹800')),
        loadDetails: details,
      ),
    );

    expect(find.textContaining('Received ₹500 of ₹800'), findsOneWidget);
  });

  testWidgets('keeps the owner on the screen with the server\'s reason', (tester) async {
    final results = await open(
      tester,
      PayDuesScreen(
        salonId: 's1',
        payout: owing(),
        loadDetails: details,
        pickImage: pick,
        submit: ({required salonId, required payoutId, required screenshotBytes, required screenshotName, transactionId, note}) async =>
            throw Exception('Your payment is already being checked.'),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pay_dues_pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pay_dues_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Your payment is already being checked.'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('says so when BookALook has not set up its QR yet', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PaymentQrCard(amount: 999, load: () async => const PaymentDetails())),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('has not added its payment QR yet'), findsOneWidget);
    expect(find.text('Pay ₹999'), findsOneWidget);
  });
}
