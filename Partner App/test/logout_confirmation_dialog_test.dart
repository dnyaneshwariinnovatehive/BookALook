import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/widgets/logout_confirmation_dialog.dart';
import 'package:partner_app/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_state':
          '{"user":{"name":"Rajesh Admin","phone":"+91 9123456789"},"role":"admin"}',
    });
  });

  Widget buildTestableDialog({
    String? name,
    String? phone,
    String? explanation,
    String? secondaryNote,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
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
        buildTestableDialog(
          name: 'Sunita Rao',
          phone: '+91 9876543210',
          secondaryNote:
              'Your bookings and salon data stay saved to your account.',
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Log out of BookALook?'), findsOneWidget);
      expect(find.text('Sunita Rao'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(
        find.text(
          'You will need to sign in again with +91 9876543210 to access your bookings, wallet and profile on this device.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Your bookings and salon data stay saved to your account.'),
        findsOneWidget,
      );
      expect(find.text('Stay signed in'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    },
  );

  testWidgets(
    'automatically reads name and phone from active auth_state session when omitted',
    (tester) async {
      await tester.pumpWidget(
        buildTestableDialog(
          secondaryNote:
              'Your bookings and salon data stay saved to your account.',
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Log out of BookALook?'), findsOneWidget);
      // Name and phone read from the mock session
      expect(find.text('Rajesh Admin'), findsOneWidget);
      expect(find.text('+91 9123456789'), findsOneWidget);
      expect(
        find.text(
          'You will need to sign in again with +91 9123456789 to access your bookings, wallet and profile on this device.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'gracefully handles missing name and missing phone without fabricating data',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        buildTestableDialog(
          name: null,
          phone: null,
          secondaryNote:
              'Your appointments and schedule stay saved to your account.',
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Log out of BookALook?'), findsOneWidget);
      // Generic explanation without fabricated phone number
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

  testWidgets('handles long provider name gracefully without layout overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestableDialog(
        name:
            'Senior Stylist Maximillian Montgomery-Vanderbilt of Kensington Studios',
        phone: '+91 9876543210',
      ),
    );

    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Senior Stylist Maximillian Montgomery-Vanderbilt of Kensington Studios',
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
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await LogoutConfirmationDialog.show(
                  context,
                  name: 'Vikram',
                  phone: '9876543210',
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
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await LogoutConfirmationDialog.show(
                  context,
                  name: 'Vikram',
                  phone: '9876543210',
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
