import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/main.dart' show themeNotifier;
import 'package:partner_app/screens/dashboard/collaborator_dashboard.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_approved_tab.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_onboarded_tab.dart';
import 'package:partner_app/services/collaborator_badges.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/collaborator/collaborator_card.dart';
import 'package:partner_app/widgets/collaborator/collaborator_empty_state.dart';

void main() {
  tearDown(() {
    themeNotifier.value = ThemeMode.light;
  });

  group('3rd Tab — CollaboratorApprovedTab', () {
    testWidgets('shows empty state without "Check Again" when no salons are approved', (tester) async {
      var navigatedToMySalons = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CollaboratorApprovedTab(
              onGoToMySalons: () => navigatedToMySalons = true,
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<CollaboratorApprovedTabState>(
        find.byType(CollaboratorApprovedTab),
      );
      state.seedForTest([]);
      await tester.pumpAndSettle();

      expect(find.text('No approved salons yet'), findsOneWidget);
      expect(find.text('View My Salons'), findsOneWidget);
      expect(find.text('Check again'), findsNothing);
      expect(find.text('Check Again'), findsNothing);

      await tester.tap(find.text('View My Salons'));
      expect(navigatedToMySalons, isTrue);
    });

    testWidgets('displays approved salon card with all details and live status', (tester) async {
      final badges = CollaboratorBadges();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CollaboratorApprovedTab(badges: badges),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<CollaboratorApprovedTabState>(
        find.byType(CollaboratorApprovedTab),
      );
      state.seedForTest([
        {
          'id': 'salon-1',
          'name': 'Glow & Glamour',
          'status': 'active',
          'is_approved': true,
          'approved_at': '2026-10-15T12:00:00Z',
          'city': 'Mumbai',
          'address': 'Bandra West',
          'services_count': 8,
          'plan_name': 'Pro Plan',
          'days_left': 25,
          'owner_name': 'Aarav Sharma',
          'owner_phone': '9876543210',
        },
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Glow & Glamour'), findsOneWidget);
      expect(find.text('Bandra West, Mumbai'), findsOneWidget);
      expect(find.text('Approved & live'), findsOneWidget);
      expect(find.text('8 services'), findsOneWidget);
      expect(find.text('Plan: Pro Plan'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Call Aarav Sharma'), findsOneWidget);
      expect(badges.approvedCount, 1);
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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      // Tap 'Pending' filter
      await tester.tap(find.textContaining('Pending'));
      await tester.pumpAndSettle();

      expect(find.text('No pending salons'), findsOneWidget);
      expect(find.text('Show all'), findsOneWidget);
      expect(find.text('Check again'), findsNothing);
      expect(find.text('Check Again'), findsNothing);

      // Reset filter
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.text('Approved Salon'), findsOneWidget);
    });
  });

  group('CollaboratorDashboardScreen Integration', () {
    testWidgets('mounts Approved Salons as the 3rd tab in bottom navigation', (tester) async {
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
      expect(find.text('Approved Salons'), findsWidgets);
      expect(find.text('Profile'), findsWidgets);

      // Verify 3rd tab has 'Approved Salons' title in app bar when selected
      await tester.tap(find.text('Approved Salons').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Approved Salons'), findsWidgets);
      expect(find.text('Salons explicitly approved by Super Admin'), findsOneWidget);
    });
  });
}
