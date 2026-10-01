import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:partner_app/screens/otp_screen.dart';
import 'package:partner_app/screens/phone_screen.dart';
import 'package:partner_app/services/auth_service.dart';
import 'package:partner_app/theme/app_colors.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/utils/auth_motion.dart';

/// Answers sendOtp without a network. [gate] holds the answer back so a test
/// can look at the screen while the request is in flight.
class _FakeAuth extends AuthService {
  _FakeAuth({this.result = 'success'});

  String result;
  Completer<void>? gate;
  int calls = 0;
  String? lastPhone;

  @override
  Future<String> sendOtp(String phone) async {
    calls++;
    lastPhone = phone;
    if (gate != null) await gate!.future;
    return result;
  }
}

Widget _app(
  _FakeAuth auth, {
  ThemeData? theme,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: theme ?? AppTheme.lightTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: PhoneScreen(authService: auth),
      ),
    ),
  );
}

/// Lets the entrance reveal finish. Not pumpAndSettle: the ambient backdrop
/// drifts forever by design.
Future<void> _settle(WidgetTester tester) => tester.pump(const Duration(seconds: 1));

Finder get _knob => find.byKey(PhoneScreen.modeKnobKey);
Finder get _rail => find.byKey(PhoneScreen.modeRailKey);
Finder get _phone => find.byKey(PhoneScreen.phoneFieldKey);

Finder _tab(String label) =>
    find.descendant(of: _rail, matching: find.text(label));

void main() {
  testWidgets('renders the login form with the +91 chip and the register link',
      (tester) async {
    await tester.pumpWidget(_app(_FakeAuth()));
    await _settle(tester);

    expect(find.text('+91'), findsOneWidget);
    expect(_phone, findsOneWidget);
    expect(find.text('Get OTP'), findsOneWidget);
    expect(find.text('Register your salon'), findsOneWidget);
    expect(find.byType(SweepButton), findsOneWidget);
  });

  group('mode switch', () {
    testWidgets('starts on Login with the knob painted on the left', (tester) async {
      await tester.pumpWidget(_app(_FakeAuth()));
      await _settle(tester);

      expect(tester.getCenter(_knob).dx, lessThan(tester.getCenter(_rail).dx));
    });

    testWidgets('Register slides the knob right through intermediate positions',
        (tester) async {
      await tester.pumpWidget(_app(_FakeAuth()));
      await _settle(tester);

      final railRect = tester.getRect(_rail);
      final start = tester.getCenter(_knob).dx;

      await tester.tap(_tab('Register'));
      await tester.pump();
      await tester.pump(AuthMotion.base ~/ 2);
      final mid = tester.getCenter(_knob).dx;

      await tester.pump(AuthMotion.base);
      final end = tester.getCenter(_knob).dx;

      // Measured on the painted knob: a jump would show mid == end.
      expect(mid, greaterThan(start));
      expect(mid, lessThan(end));
      expect(end, greaterThan(railRect.center.dx));
      expect(find.text('Start registration'), findsOneWidget);
      expect(_phone, findsNothing);
    });

    testWidgets('the link and the segment lead to the same Register mode',
        (tester) async {
      await tester.pumpWidget(_app(_FakeAuth()));
      await _settle(tester);

      await tester.tap(find.text('Register your salon'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getCenter(_knob).dx, greaterThan(tester.getCenter(_rail).dx));
      expect(find.text('Start registration'), findsOneWidget);

      // And back, from the link phrased for this mode.
      await tester.tap(find.text('Log in'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getCenter(_knob).dx, lessThan(tester.getCenter(_rail).dx));
      expect(_phone, findsOneWidget);
    });

    testWidgets('jumps straight to the target under reduced motion', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: PhoneScreen(authService: _FakeAuth()),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(_tab('Register'));
      await tester.pump();
      await tester.pump();
      expect(tester.getCenter(_knob).dx, greaterThan(tester.getCenter(_rail).dx));
    });

    testWidgets('tabs report which one is selected to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_FakeAuth()));
      await _settle(tester);

      expect(
        tester.getSemantics(_tab('Login')),
        containsSemantics(label: 'Login', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(_tab('Register')),
        containsSemantics(label: 'Register', isButton: true, isSelected: false),
      );
      handle.dispose();
    });
  });

  group('phone field', () {
    testWidgets('a pasted +91 number is cleaned to the 10 digits that are sent',
        (tester) async {
      final auth = _FakeAuth();
      await tester.pumpWidget(_app(auth));
      await _settle(tester);

      await tester.enterText(_phone, '+91 98765-43210');
      await tester.pump();
      expect(tester.widget<TextField>(_phone).controller!.text, '9876543210');

      await tester.tap(find.text('Get OTP'));
      await tester.pump();
      expect(auth.lastPhone, '9876543210');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a short number is rejected inline, never via SnackBar', (tester) async {
      final auth = _FakeAuth();
      await tester.pumpWidget(_app(auth));
      await _settle(tester);

      await tester.enterText(_phone, '98765');
      await tester.tap(find.text('Get OTP'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Enter your 10-digit mobile number.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(auth.calls, 0);

      // Editing clears the error rather than leaving it stale.
      await tester.enterText(_phone, '987654');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Enter your 10-digit mobile number.'), findsNothing);
    });
  });

  group('sending the code', () {
    testWidgets('a network failure is reworded, never shown raw', (tester) async {
      final auth = _FakeAuth(result: 'Network error: SocketException: Failed host lookup');
      await tester.pumpWidget(_app(auth));
      await _settle(tester);

      await tester.enterText(_phone, '9876543210');
      await tester.tap(find.text('Get OTP'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('Could not reach BookALook. Check your connection and try again.'),
          findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
    });

    testWidgets('a slow request says so instead of looking hung', (tester) async {
      final auth = _FakeAuth()..gate = Completer<void>();
      await tester.pumpWidget(_app(auth));
      await _settle(tester);

      await tester.enterText(_phone, '9876543210');
      await tester.tap(find.text('Get OTP'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('taking longer than usual'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('taking longer than usual'), findsOneWidget);

      auth.gate!.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('taking longer than usual'), findsNothing);
    });

    testWidgets('success moves on to the OTP screen for that number', (tester) async {
      await tester.pumpWidget(_app(_FakeAuth()));
      await _settle(tester);

      await tester.enterText(_phone, '9876543210');
      await tester.tap(find.text('Get OTP'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(OtpScreen), findsOneWidget);
      expect(tester.widget<OtpScreen>(find.byType(OtpScreen)).phone, '9876543210');
    });
  });

  group('themes and text size', () {
    testWidgets('dark mode resolves the switch and field from AppColors',
        (tester) async {
      await tester.pumpWidget(_app(_FakeAuth(), theme: AppTheme.darkTheme));
      await _settle(tester);

      final track = tester.widget<Container>(find.ancestor(
        of: _rail,
        matching: find.byType(Container),
      ).first);
      expect((track.decoration! as BoxDecoration).color, AppColors.dark.accentSoft);

      final knob = tester.widget<Container>(_knob);
      expect((knob.decoration! as BoxDecoration).color, AppColors.dark.surface);

      final field = tester.widget<TextField>(_phone);
      expect(field.decoration!.fillColor, AppColors.dark.surface);
    });

    testWidgets('lays out without overflow at 200% text', (tester) async {
      await tester.pumpWidget(_app(_FakeAuth(), textScale: 2));
      await _settle(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(_tab('Register'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });
  });
}
