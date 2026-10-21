import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/onboarding_draft.dart';
import 'package:partner_app/screens/collaborator/onboard_salon_screen.dart';
import 'package:partner_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samplePlans = [
    {
      'id': 'plan_starter',
      'name': 'Starter',
      'price': 1999,
      'validity_days': 30,
      'whatsapp_campaign_limit': 250,
    },
    {
      'id': 'plan_growth',
      'name': 'Growth',
      'price': 2999,
      'validity_days': 30,
      'whatsapp_campaign_limit': 1000,
      'has_priority_visibility': true,
    },
    {
      'id': 'plan_pro',
      'name': 'Pro Enterprise',
      'price': 4999,
      'validity_days': 90,
      'whatsapp_campaign_limit': 5000,
      'has_priority_visibility': true,
    },
  ];

  group('Collaborator Commercial Model UI/UX Tests', () {
    test('Default selection: OnboardingDraft initializes with empty commercial model and requires it in validation', () {
      final draft = OnboardingDraft(enquiryId: 'enq_fresh')
        ..salonName = 'Luxe Beauty'
        ..description = 'A premium salon experience'
        ..ownerName = 'Alice Wonder'
        ..ownerPhone = '9876543210';

      // Initially neither model is selected
      expect(draft.preferredCommercialModel, '');
      expect(draft.missingOn(0), contains('Commercial model'));

      // Once commercial model is chosen, it is satisfied
      draft.preferredCommercialModel = 'subscription';
      expect(draft.missingOn(0), isNot(contains('Commercial model')));
    });

    testWidgets('Initial UI: neither Subscription Plan nor Commission Model is selected', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: OnboardSalonScreen()),
        ),
      );
      await tester.pump();

      final state = tester.state<OnboardSalonScreenState>(find.byType(OnboardSalonScreen));
      state.seedForTest(
        draft: OnboardingDraft(enquiryId: 'enq_fresh')
          ..salonName = 'Luxe Beauty',
        subscriptionPlans: samplePlans,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Both toggles are rendered
      expect(find.text('Subscription Plan'), findsOneWidget);
      expect(find.text('Commission Model'), findsOneWidget);

      // Neither toggle is selected
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);

      // Neither conditional section is shown
      expect(find.text('Preferred subscription plan'), findsNothing);
      expect(find.text('Requested commission rate (%)'), findsNothing);
    });

    testWidgets('Commission Model selection preserves commission UI and behavior', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: OnboardSalonScreen()),
        ),
      );
      await tester.pump();

      final state = tester.state<OnboardSalonScreenState>(find.byType(OnboardSalonScreen));
      state.seedForTest(
        draft: OnboardingDraft(enquiryId: 'enq_fresh'),
        subscriptionPlans: samplePlans,
      );
      await tester.pump();

      // Tap Commission Model
      await tester.tap(find.text('Commission Model'));
      await tester.pumpAndSettle();

      expect(state.draft?.preferredCommercialModel, 'commission');
      expect(state.draft?.preferredPlanId, isNull);
      expect(find.text('Requested commission rate (%)'), findsOneWidget);
      expect(find.text('Preferred subscription plan'), findsNothing);
    });

    testWidgets('Subscription Plan selection defaults to Choose after approval and bottom sheet enables card selection & dismissal', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: OnboardSalonScreen()),
        ),
      );
      await tester.pump();

      final state = tester.state<OnboardSalonScreenState>(find.byType(OnboardSalonScreen));
      state.seedForTest(
        draft: OnboardingDraft(enquiryId: 'enq_fresh'),
        subscriptionPlans: samplePlans,
      );
      await tester.pump();

      // Tap Subscription Plan
      await tester.tap(find.text('Subscription Plan'));
      await tester.pumpAndSettle();

      expect(state.draft?.preferredCommercialModel, 'subscription');
      expect(state.draft?.preferredPlanId, isNull);

      // Preferred subscription plan field is shown with "Choose after approval" by default
      expect(find.text('Preferred subscription plan'), findsOneWidget);
      expect(find.text('Not sure yet (Choose after approval)'), findsOneWidget);

      // Tap subscription dropdown selector to open bottom sheet panel
      await tester.tap(find.text('Not sure yet (Choose after approval)'));
      await tester.pumpAndSettle();

      // Bottom sheet header and dismiss button are present
      expect(find.text('Choose Subscription Plan'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // "Choose after approval" card is visible and recommended
      expect(find.text('RECOMMENDED'), findsOneWidget);

      // Available plan cards are displayed in responsive layout with details
      expect(find.text('Starter Plan'), findsOneWidget);
      expect(find.text('Growth Plan'), findsOneWidget);
      expect(find.text('Pro Enterprise Plan'), findsOneWidget);

      // Test dismiss button: closing panel without changing selection
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Bottom sheet is dismissed and selection remains "Choose after approval"
      expect(find.text('Choose Subscription Plan'), findsNothing);
      expect(state.draft?.preferredPlanId, isNull);

      // Reopen bottom sheet
      await tester.tap(find.text('Not sure yet (Choose after approval)'));
      await tester.pumpAndSettle();

      // Tap on Growth Plan card
      await tester.tap(find.text('Growth Plan'));
      await tester.pumpAndSettle();

      // Bottom sheet closes smoothly and selection is reflected in draft & field
      expect(find.text('Choose Subscription Plan'), findsNothing);
      expect(state.draft?.preferredPlanId, 'plan_growth');
      expect(find.textContaining('Growth'), findsOneWidget);

      // Reopen bottom sheet and select "Choose after approval" again
      await tester.tap(find.textContaining('Growth'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not sure yet (Choose after approval)'));
      await tester.pumpAndSettle();

      expect(state.draft?.preferredPlanId, isNull);
      expect(find.text('Not sure yet (Choose after approval)'), findsOneWidget);
    });
  });
}
