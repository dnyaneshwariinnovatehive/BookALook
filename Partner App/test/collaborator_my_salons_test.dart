import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/main.dart' show themeNotifier;
import 'package:partner_app/screens/collaborator/onboard_salon_screen.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_onboarded_tab.dart';
import 'package:partner_app/theme/app_colors.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/collaborator/collaborator_card.dart';

/// An approved salon used to be a dead end: nothing on it did anything, so a
/// collaborator could see a salon was live and had no way to find out what state
/// its plan was in or how to reach the owner. Two things changed because of that
/// — the card unfolds, and it carries a renewal capsule that goes red at five
/// days. Both are decisions made entirely from the server payload, so they are
/// driven here by seeding that payload.
void main() {
  Map<String, dynamic> salon({
    String status = 'active',
    bool canEdit = false,
    int? daysLeft = 30,
    bool lapsed = false,
    bool needsPlan = false,
    String? plan = 'Growth',
  }) => {
    'id': '1',
    'name': 'Aurora Spa',
    'status': status,
    'can_edit': canEdit,
    'rejection_reason': null,
    'cover_photo_url': null,
    'address': '12 Ridge Road',
    'city': 'Pune',
    'services_count': 4,
    'owner_name': 'Meera',
    'owner_phone': '9999999999',
    'submitted_at': '2026-09-01T10:00:00Z',
    'plan_name': plan,
    'days_left': daysLeft,
    'renews_on': '2026-11-01',
    'lapsed': lapsed,
    'needs_plan': needsPlan,
  };

  Future<void> pumpTab(WidgetTester tester, List<Map<String, dynamic>> rows) async {
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
        .seedForTest(rows);
    await tester.pumpAndSettle();
  }

  /// The tint of the one card on screen, or null when it is left neutral.
  Color? cardTint(WidgetTester tester) =>
      tester.widget<CollaboratorCard>(find.byType(CollaboratorCard).first).color;

  tearDown(() {
    themeNotifier.value = ThemeMode.light;
  });

  group('renewal capsule', () {
    testWidgets('counts down on an approved salon', (tester) async {
      await pumpTab(tester, [salon(daysLeft: 30)]);

      expect(find.text('Ends in 30 days'), findsOneWidget);
      // The approval capsule has to survive alongside the new one.
      expect(find.text('Approved & live'), findsOneWidget);
    });

    testWidgets('reddens the whole card at five days', (tester) async {
      await pumpTab(tester, [salon(daysLeft: 5)]);

      expect(find.text('Ends in 5 days'), findsOneWidget);
      expect(cardTint(tester), AppColors.light.dangerBg);
    });

    testWidgets('leaves the card alone one day earlier', (tester) async {
      // The threshold is a boundary, and a boundary is exactly where an
      // off-by-one hides: six days has to stay neutral or the red means nothing.
      await pumpTab(tester, [salon(daysLeft: 6)]);

      expect(cardTint(tester), isNull);
    });

    testWidgets('counts a plan ending today as today, not as zero days', (
      tester,
    ) async {
      await pumpTab(tester, [salon(daysLeft: 0)]);

      expect(find.text('Ends today'), findsOneWidget);
      expect(find.text('Ends in 0 days'), findsNothing);
      expect(cardTint(tester), AppColors.light.dangerBg);
    });

    testWidgets('says expired rather than counting into the past', (
      tester,
    ) async {
      await pumpTab(tester, [salon(daysLeft: null, lapsed: true)]);

      expect(find.text('Plan expired'), findsOneWidget);
      expect(find.textContaining('days'), findsNothing);
      expect(cardTint(tester), AppColors.light.dangerBg);
    });

    testWidgets('says nothing at all about a salon still in the queue', (
      tester,
    ) async {
      // A salon waiting on SuperAdmin has no plan running, so a countdown here
      // would be inventing a deadline nobody set.
      await pumpTab(tester, [
        salon(status: 'pending_approval', canEdit: true, daysLeft: null),
      ]);

      expect(find.text('Waiting on SuperAdmin'), findsOneWidget);
      expect(find.text('Ends in 30 days'), findsNothing);
      expect(find.text('Plan expired'), findsNothing);
      expect(cardTint(tester), isNull);
    });

    testWidgets('still reports a lapsed plan against a calm salon otherwise', (
      tester,
    ) async {
      await pumpTab(tester, [salon(daysLeft: 200)]);

      expect(find.text('Ends in 200 days'), findsOneWidget);
      expect(cardTint(tester), isNull);
    });
  });

  group('expanding an approved card', () {
    testWidgets('stays shut until tapped', (tester) async {
      await pumpTab(tester, [salon()]);

      expect(find.text('Renews'), findsNothing);
      expect(find.text('Handed over'), findsOneWidget);
    });

    testWidgets('opens in place and shows the details', (tester) async {
      await pumpTab(tester, [salon()]);

      await tester.tap(find.byType(CollaboratorCard).first);
      await tester.pumpAndSettle();

      expect(find.text('Renews'), findsOneWidget);
      // Twice, because the header still shows it — which is the point of the
      // detail row being worth opening.
      expect(find.text('12 Ridge Road, Pune'), findsNWidgets(2));
      expect(find.text('Growth'), findsOneWidget);
      expect(find.text('4 services priced'), findsOneWidget);
      // The one thing a collaborator can actually do about a renewal.
      expect(find.text('Call Meera'), findsOneWidget);
      // And it did not navigate into the edit form, which an approved salon
      // cannot be saved from anyway.
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('closes again on a second tap', (tester) async {
      await pumpTab(tester, [salon()]);

      await tester.tap(find.byType(CollaboratorCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Renews'), findsOneWidget);

      await tester.tap(find.byType(CollaboratorCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Renews'), findsNothing);
    });

    testWidgets('keeps an editable salon on its tap-to-edit behaviour', (
      tester,
    ) async {
      // Pending and sent-back cards already had somewhere useful to go on tap.
      // Changing that to an accordion would take away the shortest route to
      // fixing a salon for no gain.
      await pumpTab(tester, [
        salon(status: 'pending_approval', canEdit: true, daysLeft: null),
      ]);

      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.byType(CollaboratorCard).first);
      // Not pumpAndSettle: the form autofocuses a text field, and a blinking
      // cursor never lets the tree go quiet.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(OnboardSalonScreen), findsOneWidget);
      expect(find.text('Renews'), findsNothing);
    });
  });
}
