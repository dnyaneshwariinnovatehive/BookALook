import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/main.dart' show themeNotifier;
import 'package:partner_app/screens/collaborator/onboard_salon_screen.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_onboarded_tab.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/collaborator/collaborator_chip.dart';

void main() {
  tearDown(() {
    themeNotifier.value = ThemeMode.light;
  });

  Map<String, dynamic> sampleSalon({
    required String id,
    required String name,
    required String status,
    bool canEdit = false,
  }) => {
    'id': id,
    'name': name,
    'status': status,
    'can_edit': canEdit,
    'rejection_reason': status == 'rejected' ? 'Invalid GST certificate' : null,
    'cover_photo_url': null,
    'address': 'MG Road',
    'city': 'Mumbai',
    'services_count': 3,
    'owner_name': 'Aarav',
    'owner_phone': '9876543210',
    'submitted_at': '2026-10-18T10:00:00Z',
    'plan_name': 'Pro Plan',
    'days_left': 25,
    'renews_on': '2026-11-20',
    'lapsed': false,
    'needs_plan': false,
  };

  Map<String, dynamic> sampleEnquiry({
    required String id,
    required String salonName,
    bool needsCorrection = false,
  }) => {
    'id': id,
    'salon_name': salonName,
    'owner_name': 'Pooja',
    'phone': '9123456789',
    'city': 'Pune',
    'message': 'Looking to onboard quickly',
    'assigned_at': '2026-10-19T10:00:00Z',
    'needs_correction': needsCorrection,
    'rejection_reason': needsCorrection ? 'Address proof needed' : null,
    'salon_id': null,
  };

  Map<String, dynamic> sampleAssignedSalon({
    required String id,
    required String name,
  }) => {
    'id': id,
    'name': name,
    'address': 'FC Road',
    'city': 'Pune',
    'owner_name': 'Vikram',
    'owner_phone': '9811122233',
    'services_count': 0,
    'plan_name': null,
    'days_left': null,
    'needs_plan': true,
  };

  Future<void> pumpTab(
    WidgetTester tester, {
    List<Map<String, dynamic>> salons = const [],
    List<dynamic> enquiries = const [],
    List<dynamic> assignedSalons = const [],
    List<dynamic> alerts = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: CollaboratorOnboardedTab()),
      ),
    );
    await tester.pump();

    tester.state<CollaboratorOnboardedTabState>(
      find.byType(CollaboratorOnboardedTab),
    ).seedForTest(
      salons,
      enquiries: enquiries,
      assignedSalons: assignedSalons,
      alerts: alerts,
    );
    await tester.pumpAndSettle();
  }

  group('CollaboratorOnboardedTab Filters & Functionalities', () {
    testWidgets('Displays all filter chips with correct counts', (tester) async {
      await pumpTab(
        tester,
        salons: [
          sampleSalon(id: '1', name: 'Salon Live', status: 'active'),
          sampleSalon(id: '2', name: 'Salon Review', status: 'pending_approval', canEdit: true),
          sampleSalon(id: '3', name: 'Salon Rejected', status: 'rejected', canEdit: true),
        ],
        enquiries: [
          sampleEnquiry(id: '101', salonName: 'Assigned Enquiry 1'),
        ],
        assignedSalons: [
          sampleAssignedSalon(id: '201', name: 'Directory Salon Care'),
        ],
      );

      // Verify 5 filter chips exist with their labels and counts
      expect(find.byType(CollaboratorFilterChip), findsNWidgets(5));
      expect(find.text('All · 5'), findsOneWidget);
      expect(find.text('Assigned · 2'), findsOneWidget);
      expect(find.text('Pending · 1'), findsOneWidget);
      expect(find.text('Approved · 1'), findsOneWidget);
      expect(find.text('Sent back · 1'), findsOneWidget);
    });

    testWidgets('Filter by Assigned shows enquiries and directory salons with onboarding buttons', (tester) async {
      await pumpTab(
        tester,
        salons: [
          sampleSalon(id: '1', name: 'Salon Live', status: 'active'),
        ],
        enquiries: [
          sampleEnquiry(id: '101', salonName: 'Assigned Enquiry 1'),
        ],
        assignedSalons: [
          sampleAssignedSalon(id: '201', name: 'Directory Salon Care'),
        ],
      );

      // Tap 'Assigned' filter chip
      await tester.tap(find.text('Assigned · 2'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned Enquiry 1'), findsOneWidget);
      expect(find.text('Start onboarding'), findsOneWidget);
      expect(find.text('Directory Salon Care'), findsOneWidget);
      expect(find.text('No plan chosen yet'), findsOneWidget);
      expect(find.text('Call Vikram'), findsOneWidget);

      // Approved salon should not be visible in Assigned filter
      expect(find.text('Salon Live'), findsNothing);
    });

    testWidgets('Tapping Start Onboarding on enquiry opens OnboardSalonScreen', (tester) async {
      await pumpTab(
        tester,
        enquiries: [
          sampleEnquiry(id: '101', salonName: 'Assigned Enquiry 1'),
        ],
      );

      // Tap Start onboarding
      await tester.tap(find.text('Start onboarding'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(OnboardSalonScreen), findsOneWidget);
    });

    testWidgets('Filter by Pending shows pending approval salons with Edit button', (tester) async {
      await pumpTab(
        tester,
        salons: [
          sampleSalon(id: '1', name: 'Salon Live', status: 'active'),
          sampleSalon(id: '2', name: 'Salon In Review', status: 'pending_approval', canEdit: true),
        ],
      );

      await tester.tap(find.text('Pending · 1'));
      await tester.pumpAndSettle();

      expect(find.text('Salon In Review'), findsOneWidget);
      expect(find.text('Waiting on SuperAdmin'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Salon Live'), findsNothing);
    });

    testWidgets('Filter by Sent back shows rejected salons with Fix button and rejection reason', (tester) async {
      await pumpTab(
        tester,
        salons: [
          sampleSalon(id: '1', name: 'Salon Live', status: 'active'),
          sampleSalon(id: '3', name: 'Salon Rejected', status: 'rejected', canEdit: true),
        ],
      );

      // Drag horizontal filter bar to reveal the last chip
      await tester.drag(find.byType(ListView).first, const Offset(-200, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sent back · 1'));
      await tester.pumpAndSettle();

      expect(find.text('Salon Rejected'), findsOneWidget);
      expect(find.text('Sent back'), findsOneWidget);
      expect(find.text('Invalid GST certificate'), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);
      expect(find.text('Salon Live'), findsNothing);
    });

    testWidgets('Filter by Approved shows approved salons with Handed over label', (tester) async {
      await pumpTab(
        tester,
        salons: [
          sampleSalon(id: '1', name: 'Salon Live', status: 'active'),
          sampleSalon(id: '2', name: 'Salon In Review', status: 'pending_approval', canEdit: true),
        ],
      );

      await tester.ensureVisible(find.text('Approved · 1'));
      await tester.tap(find.text('Approved · 1'));
      await tester.pumpAndSettle();

      expect(find.text('Salon Live'), findsOneWidget);
      expect(find.text('Approved & live'), findsOneWidget);
      expect(find.text('Handed over'), findsOneWidget);
      expect(find.text('Salon In Review'), findsNothing);
    });
  });
}
