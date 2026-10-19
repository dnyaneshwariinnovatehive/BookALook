import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/widgets/review_prompt_sheet.dart';
import 'package:customer_app/widgets/complaint_bottom_sheet.dart';

void main() {
  Widget testShell(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  group('ReviewPromptSheet UI Tests', () {
    testWidgets('Review prompt does not contain complaint or problem reporting elements', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        testShell(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ReviewPromptSheet.show(context, const {
                'appointment_id': 101,
                'salon_name': 'Luxury Cuts',
                'provider_name': 'Aarav',
              }),
              child: const Text('Open Rating'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Rating'));
      await tester.pumpAndSettle();

      // Should display rating elements
      expect(find.textContaining('Luxury Cuts'), findsOneWidget);
      expect(find.text('Submit rating'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);

      // Should NOT display any complaint or report toggles/buttons
      expect(find.text('Report a problem instead'), findsNothing);
      expect(find.text('Report a problem'), findsNothing);
      expect(find.text('File a complaint'), findsNothing);
      expect(find.text('Subject of complaint'), findsNothing);
    });
  });

  group('ComplaintBottomSheet UI Tests', () {
    testWidgets('Complaint sheet renders fields and validates empty inputs', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        testShell(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ComplaintBottomSheet.show(context, const {
                'id': 202,
                'salon': {'name': 'Royal Spa'},
                'appointment_date': '2026-10-15',
              }),
              child: const Text('Open Complaint'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Complaint'));
      await tester.pumpAndSettle();

      // Title & headers
      expect(find.text('Report a Problem'), findsOneWidget);
      expect(find.text('Submit Report'), findsOneWidget);

      // Validation check on empty submit
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a short subject for your report.'), findsOneWidget);
    });
  });
}
