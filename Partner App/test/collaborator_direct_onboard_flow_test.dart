import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/onboarding_draft.dart';
import 'package:partner_app/screens/collaborator/onboard_salon_screen.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_home_tab.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_onboarded_tab.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/collaborator/collaborator_card.dart';

void main() {
  group('OnboardingDraft direct onboarding tests', () {
    test('OnboardingDraft.direct creates draft without enquiry', () {
      final draft = OnboardingDraft.direct(salonId: '42');
      expect(draft.isDirect, isTrue);
      expect(draft.enquiryId.startsWith('direct_'), isTrue);
      expect(draft.editingSalonId, '42');

      final fields = draft.toFormFields();
      expect(fields['salon_id'], '42');
      expect(fields.containsKey('enquiry_id'), isFalse);
    });

    test('OnboardingDraft enquiry draft isDirect is false', () {
      final draft = OnboardingDraft(enquiryId: 'enq_123');
      expect(draft.isDirect, isFalse);

      final fields = draft.toFormFields();
      expect(fields.containsKey('salon_id'), isFalse);
    });

    test('Draft restores editingSalonId correctly from JSON', () {
      final draft = OnboardingDraft.direct(salonId: '99');
      final json = draft.toJson();
      final restored = OnboardingDraft.fromJson(json);

      expect(restored.isDirect, isTrue);
      expect(restored.editingSalonId, '99');
    });

    test('queuedForSubmission defaults to false and round-trips via JSON', () {
      final draft = OnboardingDraft.direct(salonId: '55');
      expect(draft.queuedForSubmission, isFalse);

      draft.queuedForSubmission = true;
      final json = draft.toJson();
      expect(json['queued_for_submission'], isTrue);

      final restored = OnboardingDraft.fromJson(json);
      expect(restored.queuedForSubmission, isTrue);
    });

    test('Cover photo index and photo paths are preserved and serialized', () {
      final draft = OnboardingDraft.direct();
      draft.photoPaths = ['/path/to/img1.jpg', '/path/to/img2.jpg'];
      draft.coverIndex = 1;

      final json = draft.toJson();
      expect(json['cover_index'], 1);
      expect(json['photo_paths'], ['/path/to/img1.jpg', '/path/to/img2.jpg']);

      final restored = OnboardingDraft.fromJson(json);
      expect(restored.coverIndex, 1);
      expect(restored.photoPaths.length, 2);
    });
  });

  group('CollaboratorHomeTab direct onboarding and statistics tests', () {
    testWidgets('Displays Pending, Approved, and Rejected statistics and handles taps', (tester) async {
      var assignedCalls = 0;
      var mySalonsCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CollaboratorHomeTab(
              onGoToAssigned: () => assignedCalls++,
              onGoToMySalons: () => mySalonsCalls++,
            ),
          ),
        ),
      );
      await tester.pump();

      final homeFinder = find.byType(CollaboratorHomeTab);
      tester.state<CollaboratorHomeTabState>(homeFinder).seedForTest(
        profile: {
          'name': 'Priya Sharma',
          'stats': {
            'pending': 3,
            'approved': 7,
            'rejected': 1,
            'assigned': 4,
          },
        },
        assignedCount: 4,
      );
      await tester.pumpAndSettle();

      // Check stats tiles
      expect(find.text('My Onboarded Salons'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Assigned to onboard'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);

      // Tap Pending tile -> routes to My Salons
      await tester.tap(find.text('Pending'));
      await tester.pumpAndSettle();
      expect(mySalonsCalls, 1);

      // Tap Approved tile -> routes to My Salons
      await tester.tap(find.text('Approved'));
      await tester.pumpAndSettle();
      expect(mySalonsCalls, 2);

      // Tap Rejected tile -> routes to My Salons
      await tester.tap(find.text('Rejected'));
      await tester.pumpAndSettle();
      expect(mySalonsCalls, 3);

      // Tap Assigned tile -> routes to Assigned tab
      await tester.tap(find.text('Assigned to onboard'));
      await tester.pumpAndSettle();
      expect(assignedCalls, 1);
    });

    testWidgets('Onboard New Salon button opens OnboardSalonScreen directly without redirecting to Assigned', (tester) async {
      var assignedCalled = false;
      var mySalonsCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CollaboratorHomeTab(
              onGoToAssigned: () => assignedCalled = true,
              onGoToMySalons: () => mySalonsCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      final homeFinder = find.byType(CollaboratorHomeTab);
      tester.state<CollaboratorHomeTabState>(homeFinder).seedForTest(
        profile: {
          'name': 'Priya Sharma',
          'stats': {
            'pending': 0,
            'approved': 0,
            'rejected': 0,
            'assigned': 0,
          },
        },
        assignedCount: 0,
      );
      await tester.pumpAndSettle();

      // Find the "Onboard New Salon" button
      final onboardBtn = find.widgetWithText(ElevatedButton, 'Onboard New Salon');
      expect(onboardBtn, findsOneWidget);

      // Tap the button
      await tester.tap(onboardBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify OnboardSalonScreen was opened, NOT redirected to Assigned
      expect(assignedCalled, isFalse);
      expect(find.byType(OnboardSalonScreen), findsOneWidget);
    });
  });

  group('CollaboratorOnboardedTab direct salon tests', () {
    Map<String, dynamic> directSalon({
      required String id,
      required String status,
      required bool canEdit,
      String? rejectionReason,
    }) => {
      'id': id,
      'enquiry_id': null,
      'name': 'Studio Elegance',
      'status': status,
      'can_edit': canEdit,
      'rejection_reason': rejectionReason,
      'cover_photo_url': null,
      'address': 'MG Road',
      'city': 'Mumbai',
      'services_count': 0,
      'owner_name': 'Rohit',
      'owner_phone': '9876543210',
      'submitted_at': '2026-10-18T10:00:00Z',
      'plan_name': null,
      'days_left': null,
      'renews_on': null,
      'lapsed': false,
      'needs_plan': false,
    };

    testWidgets('approved direct salon is strictly read-only with Handed over label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: CollaboratorOnboardedTab()),
        ),
      );
      await tester.pump();

      tester
          .state<CollaboratorOnboardedTabState>(
            find.byType(CollaboratorOnboardedTab),
          )
          .seedForTest([
            directSalon(id: '101', status: 'active', canEdit: false),
          ]);
      await tester.pumpAndSettle();

      expect(find.text('Handed over'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Fix'), findsNothing);

      // Tap should unfold details, NOT navigate to edit screen
      await tester.tap(find.byType(CollaboratorCard).first);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardSalonScreen), findsNothing);
      expect(find.text('MG Road, Mumbai'), findsWidgets);
    });

    testWidgets('rejected direct salon shows rejection reason and Fix button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: CollaboratorOnboardedTab()),
        ),
      );
      await tester.pump();

      tester
          .state<CollaboratorOnboardedTabState>(
            find.byType(CollaboratorOnboardedTab),
          )
          .seedForTest([
            directSalon(
              id: '102',
              status: 'rejected',
              canEdit: true,
              rejectionReason: 'Cover photo is blurry. Please upload a clear photo.',
            ),
          ]);
      await tester.pumpAndSettle();

      expect(find.text('Sent back'), findsOneWidget);
      expect(find.text('Cover photo is blurry. Please upload a clear photo.'), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);

      // Tapping Fix opens OnboardSalonScreen
      await tester.tap(find.text('Fix'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(OnboardSalonScreen), findsOneWidget);
    });

    testWidgets('pending direct salon shows Waiting on SuperAdmin and Edit button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: CollaboratorOnboardedTab()),
        ),
      );
      await tester.pump();

      tester
          .state<CollaboratorOnboardedTabState>(
            find.byType(CollaboratorOnboardedTab),
          )
          .seedForTest([
            directSalon(id: '103', status: 'pending_approval', canEdit: true),
          ]);
      await tester.pumpAndSettle();

      expect(find.text('Waiting on SuperAdmin'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);

      // Tapping Edit opens OnboardSalonScreen
      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(OnboardSalonScreen), findsOneWidget);
    });
  });
}
