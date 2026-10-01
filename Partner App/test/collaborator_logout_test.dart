import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/main.dart' show themeNotifier;
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_profile_tab.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/tab_navigator.dart';

/// Every collaborator tab lives inside its own [Navigator], so that a page
/// pushed from inside a tab renders in the tab's body instead of covering the
/// bottom bar. See [TabNavigator].
///
/// That nesting is exactly what the Log out dialog was up against: [showDialog]
/// puts its route on the *root* navigator by default, so a dialog button that
/// pops using the tab's own context does not pop the dialog. It pops the tab's
/// only route instead — leaving the dialog on screen and the tab gone.
void main() {
  final profileKey = GlobalKey<NavigatorState>();

  Future<void> pumpProfileTab(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: TabNavigator(
            navigatorKey: profileKey,
            root: const CollaboratorProfileTab(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(() {
    themeNotifier.value = ThemeMode.light;
  });

  testWidgets('the confirm dialog dismisses when you log out', (tester) async {
    await pumpProfileTab(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    // The button inside the dialog, not the one that opened it.
    await tester.tap(find.widgetWithText(TextButton, 'Log out').last);
    await tester.pumpAndSettle();

    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'Confirming must dismiss the dialog it was shown in.',
    );
  });

  testWidgets('confirming does not tear down the tab underneath', (
    tester,
  ) async {
    // Popping the tab's route instead of the dialog's leaves the TabNavigator
    // with no route at all — a black panel under a dialog nobody can dismiss.
    await pumpProfileTab(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Log out').last);
    await tester.pump();

    expect(find.byType(CollaboratorProfileTab), findsOneWidget);
  });

  testWidgets('staying signed in dismisses the dialog and keeps the tab', (
    tester,
  ) async {
    await pumpProfileTab(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Stay'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CollaboratorProfileTab), findsOneWidget);
  });
}
