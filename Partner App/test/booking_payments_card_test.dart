import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/services/booking_payments_api.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/booking_payments_card.dart';

PaymentLedger ledger({
  String status = 'unpaid',
  double paid = 0,
  double advanceOutstanding = 200,
  double outstanding = 1000,
  List<BookingRefund> refunds = const [],
  List<BookingPayment> payments = const [],
}) =>
    PaymentLedger(
      total: 1000,
      advanceDue: 200,
      advancePaid: 200 - advanceOutstanding,
      advanceOutstanding: advanceOutstanding,
      paid: paid,
      outstanding: outstanding,
      status: status,
      refunds: refunds,
      payments: payments,
    );

Widget app(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 2600);
    binding.platformDispatcher.views.first.devicePixelRatio = 2.6;
  });
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

  testWidgets('an unpaid booking shows the advance not yet received', (tester) async {
    await tester.pumpWidget(app(BookingPaymentsCard(
      salonId: 's1',
      appointmentId: 'a1',
      loader: () async => ledger(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Unpaid'), findsOneWidget);
    expect(find.textContaining('Advance of ₹200 not yet received'), findsOneWidget);
    expect(find.text('Record advance received'), findsOneWidget);
  });

  testWidgets('recording the advance updates the status in place', (tester) async {
    PaymentLedger? told;
    final calls = <List<Object?>>[];

    await tester.pumpWidget(app(BookingPaymentsCard(
      salonId: 's1',
      appointmentId: 'a1',
      loader: () async => ledger(),
      onChanged: (l) => told = l,
      recorder: (amount, type, mode, reference) async {
        calls.add([amount, type, mode]);
        return ledger(
          status: 'partially_paid',
          paid: amount,
          advanceOutstanding: 0,
          outstanding: 1000 - amount,
          payments: [BookingPayment(id: 'p1', amount: amount, type: type, mode: mode, source: 'recorded')],
        );
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('record_payment_button')));
    await tester.pumpAndSettle();
    // Prefilled with the advance still due; pay by UPI.
    expect(tester.widget<TextField>(find.byKey(const ValueKey('record_amount'))).controller!.text, '200');
    await tester.tap(find.text('UPI'));
    await tester.tap(find.byKey(const ValueKey('record_submit')));
    await tester.pumpAndSettle();

    expect(calls.single, [200.0, 'advance', 'upi']);
    expect(find.text('Partly paid'), findsOneWidget);
    expect(find.textContaining('not yet received'), findsNothing);
    expect(told?.status, 'partially_paid');
  });

  testWidgets('more than is owed is refused before it is sent', (tester) async {
    var sent = 0;
    await tester.pumpWidget(app(BookingPaymentsCard(
      salonId: 's1',
      appointmentId: 'a1',
      loader: () async => ledger(),
      recorder: (a, t, m, r) async {
        sent++;
        return ledger();
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('record_payment_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('record_amount')), '5000');
    await tester.tap(find.byKey(const ValueKey('record_submit')));
    await tester.pump();

    expect(sent, 0);
    expect(find.textContaining('more than is owed'), findsOneWidget);
  });

  testWidgets('a refund the salon owes is shown with a way to mark it returned', (tester) async {
    await tester.pumpWidget(app(BookingPaymentsCard(
      salonId: 's1',
      appointmentId: 'a1',
      canRecord: false,
      loader: () async => ledger(
        status: 'paid',
        advanceOutstanding: 0,
        outstanding: 0,
        refunds: const [BookingRefund(id: 'r1', amount: 200, status: 'awaiting_manual', returnedBy: 'salon')],
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Refund ₹200 to the customer'), findsOneWidget);
    expect(find.text('Mark returned'), findsOneWidget);
    expect(find.byKey(const ValueKey('record_payment_button')), findsNothing);
  });
}
