import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/services/collaborator_badges.dart';
import 'package:partner_app/theme/app_colors.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/collaborator/collaborator_pill_nav_bar.dart';

/// These cover the two pieces of the collaborator rework that have no widget in
/// them and so would otherwise only be exercised by hand: the colour extension
/// that carries light/dark semantics, and the badge counters the tabs report
/// into.
void main() {
  group('AppColors', () {
    testWidgets('resolves light and dark from the ambient brightness', (
      tester,
    ) async {
      late AppColors light;
      late AppColors dark;

      // Distinct keys: a second pumpWidget over the same element tree rebuilds
      // the Builder, which would quietly overwrite the first reading.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            key: const ValueKey('light'),
            builder: (context) {
              light = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );
      final lightText = light.textPrimary;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            key: const ValueKey('dark'),
            builder: (context) {
              dark = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );
      // MaterialApp changes theme through an AnimatedTheme. Reading straight
      // after pumpWidget samples the interpolation at t=0, which is still the
      // outgoing light theme — so a dark-mode assertion here has to let the
      // transition finish first.
      await tester.pumpAndSettle();

      expect(lightText, AppColors.light.textPrimary);
      expect(dark.textPrimary, AppColors.dark.textPrimary);
      expect(lightText, isNot(dark.textPrimary));
    });

    test('surfaces a distinct colour per semantic role in dark mode', () {
      final dark = AppColors.dark;

      // The point of the extension: a rejected salon, a suspended one and a
      // live one must not collapse to the same ink on a dark card.
      final semantics = {
        'success': dark.success,
        'danger': dark.danger,
        'warning': dark.warning,
        'textPrimary': dark.textPrimary,
        'textSecondary': dark.textSecondary,
      };

      expect(semantics.values.toSet().length, semantics.length);
    });

    test('keeps body and muted text apart in both modes', () {
      for (final palette in [AppColors.light, AppColors.dark]) {
        expect(palette.textPrimary, isNot(palette.textSecondary));
        expect(palette.textSecondary, isNot(palette.textTertiary));
      }
    });

    test('is registered on both theme variants', () {
      // An extension that is declared but not registered silently falls back to
      // light values everywhere, which is the exact bug this guards against.
      expect(AppTheme.lightTheme.extension<AppColors>(), isNotNull);
      expect(AppTheme.darkTheme.extension<AppColors>(), isNotNull);
    });

    testWidgets('fails loudly when the extension is not registered', (
      tester,
    ) async {
      // A widget reaching for context.colors under a ThemeData that never
      // registered the extension is a wiring mistake, not a runtime condition.
      // The release-mode fallback would hide it as "everything is just light
      // mode" everywhere, so the assert is what catches it.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Builder(
            builder: (context) {
              context.colors;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(tester.takeException(), isAssertionError);
    });
  });

  group('CollaboratorBadges', () {
    test('My Salons counts what is waiting and what was sent back', () {
      final badges = CollaboratorBadges();

      expect(badges.mySalonsCount, 0);

      badges.reportMySalons(awaitingApproval: 3, sentBack: 2);
      expect(badges.mySalonsCount, 5);
      expect(badges.awaitingApproval, 3);
      expect(badges.sentBack, 2);
    });

    test('notifies only when a count actually changes', () {
      final badges = CollaboratorBadges();
      var notifications = 0;
      badges.addListener(() => notifications++);

      badges.reportMySalons(awaitingApproval: 1, sentBack: 0);
      expect(notifications, 1);

      // The tabs rebuild on every poll, so most reports are the same number.
      // Notifying regardless would repaint the nav bar every 20 seconds for
      // no change.
      badges.reportMySalons(awaitingApproval: 1, sentBack: 0);
      expect(notifications, 1);

      badges.reportMySalons(awaitingApproval: 1, sentBack: 1);
      expect(notifications, 2);
    });

    test('tracks assigned separately from My Salons', () {
      final badges = CollaboratorBadges();

      badges.reportAssigned(4);
      expect(badges.assignedCount, 4);
      // Assigned work has not been submitted yet, so it must not leak into the
      // My Salons badge.
      expect(badges.mySalonsCount, 0);
    });

    test('an assigned count of zero still notifies the first time', () {
      final badges = CollaboratorBadges();
      var notifications = 0;
      badges.addListener(() => notifications++);

      badges.reportAssigned(0);
      expect(notifications, 0, reason: 'no change from the initial value');

      badges.reportAssigned(2);
      badges.reportAssigned(0);
      expect(notifications, 2);
    });
  });

  group('CollaboratorPillNavBar', () {
    testWidgets('caps a runaway badge instead of overflowing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CollaboratorPillNavBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                CollaboratorNavItem(
                  label: 'Assigned',
                  icon: Icons.inbox_outlined,
                  activeIcon: Icons.inbox,
                  badge: 4213,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('taps report the index that was pressed', (tester) async {
      final tapped = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CollaboratorPillNavBar(
              currentIndex: 0,
              onTap: tapped.add,
              items: const [
                CollaboratorNavItem(
                  label: 'Home',
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                ),
                CollaboratorNavItem(
                  label: 'My Salons',
                  icon: Icons.storefront_outlined,
                  activeIcon: Icons.storefront,
                ),
                CollaboratorNavItem(
                  label: 'Assigned',
                  icon: Icons.inbox_outlined,
                  activeIcon: Icons.inbox,
                ),
                CollaboratorNavItem(
                  label: 'Profile',
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Assigned'));
      await tester.pump();

      expect(tapped, [2]);
    });
  });
}
