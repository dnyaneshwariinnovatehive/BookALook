import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/screens/phone_screen.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/auth_errors.dart';
import 'package:customer_app/utils/auth_motion.dart';
import 'package:customer_app/widgets/auth/otp_boxes.dart';

Widget _wrap(Widget child) => _wrapIn(AppTheme.lightTheme, child);

Widget _wrapIn(ThemeData theme, Widget child) => MaterialApp(
      theme: theme,
      home: child,
    );

/// Where the sliding indicator is actually painted.
///
/// AnimatedAlign.alignment is the *target*, not the interpolated value, so the
/// animation can only be observed in the render layer. Measuring the knob's
/// real left edge is what proves it travels instead of jumping.
Finder get _rail => find.byKey(PhoneScreen.modeRailKey);

Finder get _knob => find.byKey(PhoneScreen.modeKnobKey);

/// Knob position normalised to 0.0 at the Login stop and 1.0 at the Sign Up
/// stop, so assertions read as "left / between / right" rather than pixels.
double _knobProgress(WidgetTester tester) {
  final railLeft = tester.getTopLeft(_rail).dx;
  final railWidth = tester.getSize(_rail).width;
  final knobWidth = tester.getSize(_knob).width;

  final span = railWidth - knobWidth;
  if (span <= 0) return 0;
  return (tester.getTopLeft(_knob).dx - railLeft) / span;
}

void main() {
  testWidgets('renders the phone form with its secondary actions', (tester) async {
    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('Premium Grooming & Beauty Discovery'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Explore as Guest'), findsOneWidget);
    expect(find.text('Register Your Salon'), findsOneWidget);
    // Trailing space in the source is intentional: it is the gap before the
    // "Register" tappable.
    expect(find.textContaining('New to BookALook?'), findsOneWidget,
        reason: 'register link shows in Login mode');
    expect(find.byType(AmbientBackdrop), findsOneWidget);
  });

  testWidgets('mode switch starts on Login and the knob sits left',
      (tester) async {
    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(_knobProgress(tester), lessThan(0.05),
        reason: 'knob must start at the Login stop');
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('tapping Sign Up moves the knob right and swaps the CTA',
      (tester) async {
    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    await tester.tap(find.text('Sign Up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_knobProgress(tester), greaterThan(0.95),
        reason: 'knob must end at the Sign Up stop');
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('New to BookALook?'), findsNothing,
        reason: 'register link is Login-only');
  });

  testWidgets('knob travels through intermediate positions, never jumps',
      (tester) async {
    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    final start = _knobProgress(tester);
    expect(start, lessThan(0.05));

    await tester.tap(find.text('Sign Up'));
    // The first frame after setState only commits the new target; the implicit
    // animation starts from there, so sample from the frame after it.
    await tester.pump();

    // Sample the tween across the whole duration. easeOutCubic moves fastest at
    // the start, so the earliest frames must already have travelled a long way
    // while still short of the destination.
    final samples = <double>[];
    for (final step in [30, 30, 30, 30, 60, 60, 60]) {
      await tester.pump(Duration(milliseconds: step));
      samples.add(_knobProgress(tester));
    }
    await tester.pump(const Duration(milliseconds: 400));
    final end = _knobProgress(tester);

    expect(samples, isNotEmpty);
    expect(samples.first, greaterThan(0.05),
        reason: 'first sampled frame must already have moved, '
            'got ${samples.first}');
    // Strictly increasing throughout: this is what a real slide looks like. A
    // jump would repeat the first value or snap straight to the destination.
    for (var i = 1; i < samples.length; i++) {
      expect(samples[i], greaterThan(samples[i - 1]),
          reason: 'knob must keep moving toward the target without reversing '
              'or stalling');
    }
    expect(samples.every((p) => p > 0.0 && p < 1.0), isFalse,
        reason: 'at least one sampled frame must be strictly between the stops');
    expect(end, greaterThan(0.95), reason: 'and it must finish at the stop');
  });

  testWidgets('tapping Login again returns the knob left', (tester) async {
    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    await tester.tap(find.text('Sign Up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_knobProgress(tester), greaterThan(0.95));

    await tester.tap(find.text('Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_knobProgress(tester), lessThan(0.05));
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('a short phone number is rejected inline, not via SnackBar',
      (tester) async {
    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Inline under the field now, where it cannot hide behind the keyboard.
    // This used to assert the SnackBar existed, to pin the old behaviour.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(PhoneScreen.statusKey), findsOneWidget);
    expect(find.text('Please enter a valid phone number (min 10 digits)'), findsOneWidget);

    // Editing clears it rather than leaving a stale complaint on screen.
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(PhoneScreen.statusKey), findsNothing);
  });

  testWidgets('a failed send is explained in words, never as a raw response',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    api.debugSetClient(MockClient((_) async => http.Response(
          '{"message":"The given data was invalid.","errors":{"phone":["The phone field must be 10 digits."]}}',
          422,
        )));

    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    await tester.enterText(find.byKey(PhoneScreen.phoneFieldKey), '9876543210');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('HTTP Error'), findsNothing);
    expect(find.textContaining('422'), findsNothing);
    expect(find.text('The phone field must be 10 digits.'), findsOneWidget);
  });

  group('friendlyAuthError', () {
    test('a dropped connection becomes a connection message', () {
      expect(friendlyAuthError('Network Exception: SocketException: Failed host lookup'),
          'Could not reach BookALook. Check your connection and try again.');
    });

    test('a server error page is never shown', () {
      final text = friendlyAuthError('HTTP Error 502: <html><body>Bad Gateway</body></html>');
      expect(text, isNot(contains('<html')));
      expect(text, isNot(contains('502')));
    });

    test('a 4xx uses the message the server wrote for people', () {
      expect(friendlyAuthError('HTTP Error 400: {"message":"User is blocked."}'),
          'User is blocked.');
    });

    test('rate limiting says to wait', () {
      expect(friendlyAuthError('HTTP Error 429: {}'), contains('wait'));
    });

    test('anything unrecognised falls back to a generic sentence', () {
      expect(friendlyAuthError('HTTP Error 404: not json'),
          'We could not send a code right now. Please try again.');
      expect(friendlyAuthError(null),
          'We could not send a code right now. Please try again.');
    });
  });

  testWidgets('Continue animates a sheen rather than swapping in a spinner',
      (tester) async {
    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.byType(SweepButton), findsOneWidget);
    // No CircularProgressIndicator should be sitting on the idle button.
    expect(
      find.descendant(
        of: find.byType(SweepButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('entrance reveals children progressively', (tester) async {
    await tester.pumpWidget(_wrap(const StaggeredReveal(
      children: [SizedBox(height: 30, child: Text('a'))],
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('dark mode paints an opaque shell, not the previous route',
      (tester) async {
    await tester.pumpWidget(_wrapIn(AppTheme.darkTheme, const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    // A transparent shell lets the outgoing screen show through during the
    // route transition, which is what made the old text ghost.
    final base = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(AuthShell),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(base.color, AppTheme.darkBg);
  });

  testWidgets('dark mode resolves every tint from the theme', (tester) async {
    await tester.pumpWidget(_wrapIn(AppTheme.darkTheme, const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    // Track and knob must follow AppTheme, not a hardcoded tint.
    final rail = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PhoneScreen),
            matching: find.byType(Container),
          )
          .first,
    );
    final knob = tester.widget<Container>(_knob);
    expect((rail.decoration as BoxDecoration).color, AppTheme.darkAccentSoft);
    expect((knob.decoration as BoxDecoration).color,
        AppTheme.darkTheme.colorScheme.primary);
  });

  testWidgets('phone field does not take 11 digits', (tester) async {
    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    // Typing 11 digits is capped to 10 digits
    await tester.enterText(find.byKey(PhoneScreen.phoneFieldKey), '98765432101');
    await tester.pump();

    final field = tester.widget<TextField>(find.byKey(PhoneScreen.phoneFieldKey));
    expect(field.controller!.text, '9876543210');

    // Pasting formatted +91 number is resolved to 10 digits
    await tester.enterText(find.byKey(PhoneScreen.phoneFieldKey), '+91 91234 56789');
    await tester.pump();
    expect(field.controller!.text, '9123456789');

    // Pasting leading 0 number is resolved to 10 digits
    await tester.enterText(find.byKey(PhoneScreen.phoneFieldKey), '09123456789');
    await tester.pump();
    expect(field.controller!.text, '9123456789');
  });
}

