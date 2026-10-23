import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/registration/steps/step2_salon_details.dart';
import 'package:partner_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Step2SalonDetails hides subscription plan dropdown when commission model is selected', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Map<String, dynamic>? submittedData;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Step2SalonDetails(
            onNext: (data) => submittedData = data,
            onBack: () {},
            initialData: const {
              'salon_name': 'Glamour Salon',
              'description': 'A beauty destination',
              'street_address': '123 MG Road',
              'pincode': '411001',
              'preferred_commercial_model': 'subscription',
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // In subscription model: subscription plan label and dropdown must be shown
    expect(find.text('Preferred Subscription Plan (Optional)'), findsOneWidget);
    expect(find.text('Subscription Plan'), findsOneWidget);
    expect(find.text('Commission Model'), findsOneWidget);
    expect(find.text('Requested Commission Rate (%) *'), findsNothing);

    // Tap on "Commission Model"
    await tester.tap(find.text('Commission Model'));
    await tester.pumpAndSettle();

    // After selecting commission model:
    // 1. Subscription plan label and dropdown must be completely hidden
    expect(find.text('Preferred Subscription Plan (Optional)'), findsNothing);
    // 2. Requested commission rate field must appear
    expect(find.text('Requested Commission Rate (%) *'), findsOneWidget);

    // Tap back to "Subscription Plan"
    await tester.tap(find.text('Subscription Plan'));
    await tester.pumpAndSettle();

    // Subscription plan dropdown must reappear
    expect(find.text('Preferred Subscription Plan (Optional)'), findsOneWidget);
    expect(find.text('Requested Commission Rate (%) *'), findsNothing);
  });

  testWidgets('Step2SalonDetails initialized with commission model does not show subscription plan dropdown', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Step2SalonDetails(
            onNext: (_) {},
            onBack: () {},
            initialData: const {
              'salon_name': 'Glamour Salon',
              'description': 'A beauty destination',
              'street_address': '123 MG Road',
              'pincode': '411001',
              'preferred_commercial_model': 'commission',
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Subscription plan dropdown should NOT be displayed
    expect(find.text('Preferred Subscription Plan (Optional)'), findsNothing);
    // Commission rate input should be displayed
    expect(find.text('Requested Commission Rate (%) *'), findsOneWidget);
  });
}
