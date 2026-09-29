import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/main.dart' show themeNotifier;
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_assigned_tab.dart';
import 'package:partner_app/theme/app_theme.dart';

/// The Assigned tab used to stop polling for the simple reason that switching
/// tabs threw its State away. It no longer does, so the poll has to be told when
/// to stop instead — and a regression there is invisible on screen: the only
/// symptom is battery, and it only shows up once someone leaves the app on
/// another tab.
void main() {
  Future<CollaboratorAssignedTabState> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: CollaboratorAssignedTab()),
      ),
    );
    // Let the first fetch settle and arm or not arm the poll.
    await tester.pump();
    return tester.state<CollaboratorAssignedTabState>(
      find.byType(CollaboratorAssignedTab),
    );
  }

  tearDown(() {
    themeNotifier.value = ThemeMode.light;
  });

  testWidgets('does not poll before the shell says the tab is visible', (
    tester,
  ) async {
    final state = await pumpTab(tester);

    // Assigned is the third tab, so on a normal first paint it is behind Home.
    // It must be silent until told otherwise, or it polls the API for the whole
    // session for a list nobody opened.
    expect(state.isPolling, isFalse);
  });

  testWidgets('polls once told it is visible', (tester) async {
    final state = await pumpTab(tester);

    state.setActive(true);
    await tester.pump();

    expect(state.isPolling, isTrue);
  });

  testWidgets('stops polling the moment it loses visibility', (tester) async {
    final state = await pumpTab(tester);

    state.setActive(true);
    await tester.pump();
    expect(state.isPolling, isTrue);

    state.setActive(false);
    await tester.pump();

    expect(state.isPolling, isFalse);
  });

  testWidgets('survives repeated visibility flips without double-arming', (
    tester,
  ) async {
    final state = await pumpTab(tester);

    // The shell calls this on every build. A naive implementation that started
    // a new Timer per call would leave several running at once — the same drain,
    // multiplied.
    for (var i = 0; i < 5; i++) {
      state.setActive(true);
      await tester.pump();
      expect(state.isPolling, isTrue, reason: 'flip $i should stay armed');
    }

    for (var i = 0; i < 5; i++) {
      state.setActive(false);
      await tester.pump();
      expect(state.isPolling, isFalse, reason: 'flip $i should stay silent');
    }
  });

  testWidgets('cancels the poll when disposed', (tester) async {
    final state = await pumpTab(tester);
    state.setActive(true);
    await tester.pump();

    // Replaced rather than popped, so the old State's dispose runs while the
    // timer is armed. If dispose did not cancel it, the callback would fire
    // against an unmounted State.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pump(const Duration(seconds: 30));

    expect(tester.takeException(), isNull);
  });
}
