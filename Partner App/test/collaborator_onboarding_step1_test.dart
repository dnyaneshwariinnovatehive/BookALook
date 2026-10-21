import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/onboarding_draft.dart';
import 'package:partner_app/screens/collaborator/onboard_salon_screen.dart';
import 'package:partner_app/theme/app_theme.dart';

void main() {
  group('Step 1 Reception Number and Commercial Preference Tests', () {
    test('OnboardingDraft does not require salonPhone / reception number on step 0', () {
      final draft = OnboardingDraft(enquiryId: 'enq_test')
        ..salonName = 'Test Salon'
        ..description = 'A lovely salon'
        ..ownerName = 'John Doe'
        ..ownerPhone = '9876543210'
        ..salonPhone = '' // empty reception number
        ..preferredCommercialModel = 'subscription';

      // Step 0 required fields should be satisfied even with empty salonPhone
      expect(draft.missingOn(0), isEmpty);
    });

    testWidgets('Step 1 displays Reception number (optional) and shows plan dropdown conditionally with details',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: OnboardSalonScreen(),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<OnboardSalonScreenState>(find.byType(OnboardSalonScreen));
      state.seedForTest(
        draft: OnboardingDraft(enquiryId: 'enq_1')
          ..salonName = 'Test Glamour'
          ..preferredCommercialModel = 'subscription',
        subscriptionPlans: [
          {
            'id': 'plan_starter_1',
            'name': 'Starter',
            'price': 1999,
            'validity_days': 30,
            'whatsapp_campaign_limit': 250,
          },
          {
            'id': 'plan_growth_2',
            'name': 'Growth',
            'price': 2999,
            'validity_days': 30,
            'whatsapp_campaign_limit': 1000,
            'has_priority_visibility': true,
          },
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify "Reception number" label is present with (optional)
      expect(find.text('Reception number'), findsOneWidget);
      expect(find.text('  (optional)'), findsWidgets);

      // Verify "Salon phone" is NOT present
      expect(find.text('Salon phone'), findsNothing);

      // Verify Commercial Model options
      expect(find.text('Subscription Plan'), findsOneWidget);
      expect(find.text('Commission Model'), findsOneWidget);

      // Initially preferredCommercialModel is 'subscription', so dropdown is shown
      expect(find.text('Preferred subscription plan'), findsOneWidget);
      expect(find.text('Not sure yet (Choose after approval)'), findsOneWidget);

      // Tap "Commission Model"
      await tester.tap(find.text('Commission Model'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Preferred subscription plan dropdown should be hidden when Commission Model is selected
      expect(find.text('Preferred subscription plan'), findsNothing);
      expect(find.text('Requested commission rate (%)'), findsOneWidget);

      // Tap back to "Subscription Plan"
      await tester.tap(find.text('Subscription Plan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Preferred subscription plan dropdown should reappear
      expect(find.text('Preferred subscription plan'), findsOneWidget);
      expect(find.text('Requested commission rate (%)'), findsNothing);

      // Tap the dropdown to open it
      await tester.tap(find.text('Not sure yet (Choose after approval)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check that plans with formatted details appear in dropdown menu
      expect(find.text('Starter (₹1999 · 30 days · 250 WA campaigns)'), findsWidgets);
      expect(find.text('Growth (₹2999 · 30 days · 1000 WA campaigns · Priority visibility)'), findsWidgets);

      // Select Growth plan
      await tester.tap(find.text('Growth (₹2999 · 30 days · 1000 WA campaigns · Priority visibility)').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify draft preferredPlanId is updated
      expect(state.draft?.preferredPlanId, 'plan_growth_2');
    });
  });
}
