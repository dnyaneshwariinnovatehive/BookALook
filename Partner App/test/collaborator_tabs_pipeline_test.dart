import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/main.dart' show themeNotifier;
import 'package:partner_app/screens/dashboard/collaborator_dashboard.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_assigned_tab.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_onboarded_tab.dart';
import 'package:partner_app/services/collaborator_badges.dart';
import 'package:partner_app/services/onboarding_draft_store.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/collaborator/collaborator_card.dart';
import 'package:partner_app/widgets/collaborator/collaborator_empty_state.dart';

void main() {
  tearDown(() {
    themeNotifier.value = ThemeMode.light;
    OnboardingDraftStore.instance.cancelTimerForTesting();
  });

  group('3rd Tab — CollaboratorAssignedTab', () {
    testWidgets('shows empty state when no assigned salons exist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: CollaboratorAssignedTab(),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<CollaboratorAssignedTabState>(
        find.byType(CollaboratorAssignedTab),
      );
      state.seedForTest(enquiries: []);
      await tester.pump();

      expect(find.text('No assigned salons'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      OnboardingDraftStore.instance.cancelTimerForTesting();
    });

    testWidgets('displays assigned enquiry card with owner and city details', (tester) async {
      final badges = CollaboratorBadges();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CollaboratorAssignedTab(badges: badges),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<CollaboratorAssignedTabState>(
        find.byType(CollaboratorAssignedTab),
      );
      state.seedForTest(
        enquiries: [
          {
            'id': 'enquiry-1',
            'salon_name': 'Velvet Touch Unisex Salon',
            'owner_name': 'Rohan Joshi',
            'phone': '9820011223',
            'city': 'Mumbai',
            'message': 'Looking to onboard quickly',
            'assigned_at': '2026-10-18T10:00:00Z',
            'needs_correction': false,
            'salon_status': null,
          },
        ],
      );
      await tester.pump();

      expect(find.text('Velvet Touch Unisex Salon'), findsOneWidget);
      expect(find.text('Rohan Joshi'), findsOneWidget);
      expect(find.text('9820011223'), findsOneWidget);
      expect(find.text('Mumbai'), findsOneWidget);
      expect(find.text('Assigned'), findsOneWidget);
      expect(find.text('Start onboarding'), findsOneWidget);
      expect(badges.assignedCount, 1);
      OnboardingDraftStore.instance.cancelTimerForTesting();
    });

    testWidgets('displays error state with retry on failure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: CollaboratorAssignedTab(),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<CollaboratorAssignedTabState>(
        find.byType(CollaboratorAssignedTab),
      );
      state.seedForTest(
        enquiries: [],
        errorMessage: 'Unable to load assigned salons. Please check your internet connection.',
      );
      await tester.pump();

      expect(
        find.text('Unable to load assigned salons. Please check your internet connection.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      OnboardingDraftStore.instance.cancelTimerForTesting();
    });
  });

  group('2nd Tab — CollaboratorOnboardedTab (My Salons)', () {
    Map<String, dynamic> mockSalon({
      required String id,
      required String name,
      required String status,
      bool isApproved = false,
      String? reason,
    }) => {
      'id': id,
      'name': name,
      'status': status,
      'is_approved': isApproved,
      'rejection_reason': reason,
      'correction_notes': reason,
      'can_edit': !isApproved,
      'cover_photo_url': null,
      'address': 'MG Road',
      'city': 'Pune',
      'services_count': 5,
      'owner_name': 'Pooja',
      'owner_phone': '9123456789',
      'submitted_at': '2026-10-10T10:00:00Z',
    };

    testWidgets('displays salons across all approval statuses with correct badges', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: CollaboratorOnboardedTab()),
        ),
      );
      await tester.pump();

      final state = tester.state<CollaboratorOnboardedTabState>(
        find.byType(CollaboratorOnboardedTab),
      );

      final salons = [
        mockSalon(id: '1', name: 'Approved Salon', status: 'active', isApproved: true),
        mockSalon(id: '2', name: 'Pending Salon', status: 'pending_approval'),
        mockSalon(id: '3', name: 'Rejected Salon', status: 'rejected', reason: 'Update GST'),
      ];

      state.seedForTest(salons);
      await tester.pump();

      expect(find.text('Approved Salon'), findsOneWidget);
      expect(find.text('Pending Salon'), findsOneWidget);
      expect(find.text('Rejected Salon'), findsOneWidget);

      expect(find.text('Approved & live'), findsOneWidget);
      expect(find.text('Waiting on SuperAdmin'), findsOneWidget);
      expect(find.text('Sent back'), findsOneWidget);

      // Verify filters
      expect(find.text('All · 3'), findsOneWidget);
      expect(find.text('Pending · 1'), findsOneWidget);
      expect(find.text('Approved · 1'), findsOneWidget);
      expect(find.text('Sent back · 1'), findsOneWidget);
    });

    testWidgets('status filter isolates salons and empty filter states never say "Check Again"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: CollaboratorOnboardedTab()),
        ),
      );
      await tester.pump();

      final state = tester.state<CollaboratorOnboardedTabState>(
        find.byType(CollaboratorOnboardedTab),
      );

      // Only an approved salon
      state.seedForTest([
        mockSalon(id: '1', name: 'Approved Salon', status: 'active', isApproved: true),
      ]);
      await tester.pump();

      // Tap 'Pending' filter
      await tester.tap(find.textContaining('Pending'));
      await tester.pump();

      expect(find.text('No pending salons'), findsOneWidget);
      expect(find.text('Show all'), findsOneWidget);
      expect(find.text('Check again'), findsNothing);
      expect(find.text('Check Again'), findsNothing);

      // Reset filter
      await tester.tap(find.text('Show all'));
      await tester.pump();

      expect(find.text('Approved Salon'), findsOneWidget);
    });
  });

  group('CollaboratorDashboardScreen Integration', () {
    testWidgets('mounts Assigned as the 3rd tab in bottom navigation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CollaboratorDashboardScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Home'), findsWidgets);
      expect(find.text('My Salons'), findsWidgets);
      expect(find.text('Assigned'), findsWidgets);
      expect(find.text('Profile'), findsWidgets);

      // Verify 3rd tab has 'Assigned' title in app bar when selected
      await tester.tap(find.text('Assigned').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Assigned'), findsWidgets);
      expect(find.text('Salons waiting to be onboarded'), findsOneWidget);
      OnboardingDraftStore.instance.cancelTimerForTesting();
    });
  });
}
