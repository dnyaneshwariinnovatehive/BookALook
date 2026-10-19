import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/onboarding_draft.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_assigned_tab.dart';
import 'package:partner_app/services/onboarding_draft_store.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    OnboardingDraftStore.instance.cancelTimerForTesting();
  });

  testWidgets('verify Discard button is removed from assigned enquiry cards', (tester) async {
    final store = OnboardingDraftStore.instance;

    // Save a draft for enquiry "101"
    final draft = OnboardingDraft(
      enquiryId: '101',
      salonName: 'Glamour Salon',
      ownerName: 'Jane Doe',
    );
    await store.save(draft);

    final key = GlobalKey<CollaboratorAssignedTabState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CollaboratorAssignedTab(key: key),
        ),
      ),
    );

    // Seed enquiries into the tab state
    key.currentState?.seedForTest(
      enquiries: [
        {
          'id': '101',
          'salon_name': 'Glamour Salon',
          'owner_name': 'Jane Doe',
          'phone': '9876543210',
          'city': 'Mumbai',
          'message': 'Looking to join',
          'assigned_at': '2026-10-18T10:00:00Z',
          'needs_correction': false,
        },
        {
          'id': '102',
          'salon_name': 'Style Studio',
          'owner_name': 'John Smith',
          'phone': '9123456789',
          'city': 'Pune',
          'message': 'New inquiry',
          'assigned_at': '2026-10-19T10:00:00Z',
          'needs_correction': false,
        },
      ],
    );

    await tester.pump();

    // Verify enquiry cards are present
    expect(find.text('Glamour Salon'), findsOneWidget);
    expect(find.text('Style Studio'), findsOneWidget);

    // Glamour Salon has a draft, so it shows 'Continue onboarding'
    expect(find.text('Continue onboarding'), findsOneWidget);

    // Style Studio has no draft, so it shows 'Start onboarding'
    expect(find.text('Start onboarding'), findsOneWidget);

    // Verify Discard button is NOT rendered anywhere
    expect(find.text('Discard'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    // Cancel timer before test ends so no pending timers remain
    store.cancelTimerForTesting();
  });
}
