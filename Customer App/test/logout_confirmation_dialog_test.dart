import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/widgets/logout_confirmation_dialog.dart';
import 'package:customer_app/theme/app_colors.dart';

void main() {
  Widget buildTestableDialog({
    String? name,
    String? phone,
    String? explanation,
    String? secondaryNote,
  }) {
    return MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [AppColors.light]),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => LogoutConfirmationDialog.show(
              context,
              name: name,
              phone: phone,
              explanation: explanation,
              secondaryNote: secondaryNote,
            ),
            child: const Text('Show Dialog'),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'renders title, authenticated account info, explanation and secondary note',
    (tester) async {
      await tester.pumpWidget(
        buildTestableDialog(name: 'Rohan Sharma', phone: '+91 9876543210'),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Log out of BookALook?'), findsOneWidget);
      expect(find.text('Rohan Sharma'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(
        find.text(
          'You will need to sign in again with +91 9876543210 to access your bookings, wallet and profile on this device.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Your bookings and cart stay saved to your account.'),
        findsOneWidget,
      );
      expect(find.text('Stay signed in'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    },
  );

  testWidgets(
    'gracefully handles missing name and missing phone without fabricating data',
    (tester) async {
      await tester.pumpWidget(buildTestableDialog(name: null, phone: null));

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Log out of BookALook?'), findsOneWidget);
      // Generic explanation without fabricated phone
      expect(
        find.text(
          'You will need to sign in again to access your bookings, wallet and profile on this device.',
        ),
        findsOneWidget,
      );
      expect(find.text('Stay signed in'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    },
  );

  testWidgets('handles long user name gracefully without layout overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestableDialog(
        name:
            'Dr. Alexander Bartholomew Montgomery III of Grand Valley Meadows',
        phone: '+91 9988776655',
      ),
    );

    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Dr. Alexander Bartholomew Montgomery III of Grand Valley Meadows',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Stay signed in dismisses the dialog with false', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [AppColors.light]),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await LogoutConfirmationDialog.show(
                  context,
                  name: 'Priya Patel',
                  phone: '9876501234',
                );
              },
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stay signed in'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isFalse);
  });

  testWidgets('tapping Log out confirms the dialog with true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [AppColors.light]),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await LogoutConfirmationDialog.show(
                  context,
                  name: 'Priya Patel',
                  phone: '9876501234',
                );
              },
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isTrue);
  });
}
