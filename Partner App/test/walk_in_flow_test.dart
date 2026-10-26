import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/walk_in_history_screen.dart';
import 'package:partner_app/screens/walk_in_screen.dart';
import 'package:partner_app/services/walk_in_api.dart';

/// Adding a walk-in opens "collect payment & complete" straight away, and a
/// collected payment lands on the walk-in history.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<WalkInOptions> options(String _) async => WalkInOptions.fromJson({
        'services': [
          {'id': 's1', 'name': 'Haircut', 'category': 'Hair', 'price': 300, 'duration_minutes': 30},
        ],
        'providers': [
          {'id': 'p1', 'name': 'Asha', 'service_ids': ['s1']},
        ],
        'default_provider_id': 'p1',
        'can_choose_provider': false,
      });

  Future<WalkInResult> create({
    required String customerName,
    required String customerPhone,
    required String gender,
    required List<String> serviceIds,
    String? providerId,
    required bool allowOverlap,
  }) async =>
      WalkInResult.fromJson({
        'message': 'Walk-in started.',
        'appointment': {
          'id': 'apt-1',
          'status': 'in_progress',
          'customer_name': customerName,
          'serving_provider_name': 'Asha',
          'total_amount': 300,
          'advance_amount': 0,
          'balance_amount': 300,
        },
        'bill': {'total': 300, 'balance_due': 300, 'lines': []},
      });

  Future<void> addWalkIn(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ravi');
    await tester.pump();
    await tester.tap(find.text('Haircut'));
    await tester.pump();
    await tester.tap(find.text('Start now'));
    // Not pumpAndSettle: the history screen keeps a spinner going while it
    // loads, which would never settle in a test.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> sized(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('adding a walk-in opens collect payment straight away', (tester) async {
    await sized(tester);
    final opened = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: WalkInScreen(
        salonId: 'salon-1',
        loadOptions: options,
        createWalkIn: create,
        collectPayment: (context, salonId, appointmentId) async {
          opened.add(appointmentId);
          return false;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await addWalkIn(tester);

    expect(opened, ['apt-1']);
    // No "Add another / Go to bill" choice in between any more.
    expect(find.text('Add another'), findsNothing);
  });

  testWidgets('collecting the payment goes to the walk-in history', (tester) async {
    await sized(tester);

    await tester.pumpWidget(MaterialApp(
      home: WalkInScreen(
        salonId: 'salon-1',
        loadOptions: options,
        createWalkIn: create,
        collectPayment: (context, salonId, appointmentId) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    await addWalkIn(tester);

    expect(find.byType(WalkInHistoryScreen), findsOneWidget);
    // The form is replaced, so Back does not return to an empty form.
    expect(find.byType(WalkInScreen), findsNothing);
  });

  testWidgets('closing collect payment keeps the visit in progress and stays put', (tester) async {
    await sized(tester);

    await tester.pumpWidget(MaterialApp(
      home: WalkInScreen(
        salonId: 'salon-1',
        loadOptions: options,
        createWalkIn: create,
        collectPayment: (context, salonId, appointmentId) async => false,
      ),
    ));
    await tester.pumpAndSettle();

    await addWalkIn(tester);

    expect(find.byType(WalkInHistoryScreen), findsNothing);
    expect(find.textContaining('Ravi is in progress'), findsOneWidget);
  });

  testWidgets('an embedded walk-in tab opens the history on top of itself', (tester) async {
    await sized(tester);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WalkInScreen(
          salonId: 'salon-1',
          embedded: true,
          loadOptions: options,
          createWalkIn: create,
          collectPayment: (context, salonId, appointmentId) async => true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await addWalkIn(tester);

    expect(find.byType(WalkInHistoryScreen), findsOneWidget);
  });
}
