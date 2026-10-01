import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:partner_app/screens/dashboard/collaborator_dashboard.dart';
import 'package:partner_app/screens/dashboard/salon_selection_screen.dart';
import 'package:partner_app/screens/dashboard/service_provider_dashboard.dart';
import 'package:partner_app/screens/otp_screen.dart';
import 'package:partner_app/screens/partner_home.dart';
import 'package:partner_app/services/auth_service.dart';
import 'package:partner_app/services/auth_session.dart';
import 'package:partner_app/theme/app_colors.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/utils/auth_motion.dart';
import 'package:partner_app/widgets/auth/otp_boxes.dart';

class _FakeAuth extends AuthService {
  Map<String, dynamic> verifyResult = {'success': false, 'message': 'Invalid OTP'};
  String sendResult = 'success';
  Completer<void>? gate;
  final verified = <String>[];
  int sends = 0;

  @override
  Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    verified.add(otp);
    if (gate != null) await gate!.future;
    return verifyResult;
  }

  @override
  Future<String> sendOtp(String phone) async {
    sends++;
    return sendResult;
  }
}

class _FakeSession extends AuthSession {
  _FakeSession() : super(registerPush: () async {});

  Map<String, dynamic>? saved;

  @override
  Future<void> save(Map<String, dynamic> response) async => saved = response;
}

/// Records what the real role mapping decided, then stands in for it with a
/// marker. The dashboards themselves start API calls the moment they mount,
/// so the test asserts the decision without building them.
class _HomeSpy {
  Widget? decided;

  Widget? call(Map<String, dynamic> response) {
    decided = partnerHomeFor(response);
    return decided == null ? null : Text('home:${response['role']}');
  }
}

class _Harness {
  final auth = _FakeAuth();
  final session = _FakeSession();
  final home = _HomeSpy();
  String? registeredPhone;
  Map<String, dynamic>? registeredEnquiry;

  Widget screen() => OtpScreen(
        phone: '9876543210',
        authService: auth,
        session: session,
        homeFor: home.call,
        registrationBuilder: (phone, enquiry) {
          registeredPhone = phone;
          registeredEnquiry = enquiry;
          return const Text('registration wizard');
        },
      );

  /// The OTP screen pushed on top of a stand-in phone screen, so "Change
  /// number" and stack clearing have something to act on.
  ///
  /// The text scale goes on MaterialApp.builder, above the Navigator, so it
  /// reaches pushed routes too — a MediaQuery under `home` would not.
  Widget app({ThemeData? theme, double textScale = 1}) => MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => screen()),
                ),
                child: const Text('phone screen'),
              ),
            ),
          ),
        ),
      );
}

Finder get _field => find.byKey(OtpBoxes.fieldKey);

Future<void> _open(WidgetTester tester, _Harness h, {ThemeData? theme, double textScale = 1}) async {
  await tester.pumpWidget(h.app(theme: theme, textScale: textScale));
  await tester.tap(find.text('phone screen'));
  await tester.pump();
  // Route transition plus the entrance reveal. Not pumpAndSettle: the ambient
  // backdrop drifts forever by design.
  await tester.pump(const Duration(seconds: 1));
}

/// The digits currently painted in the six boxes, in order.
List<String> _paintedDigits(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(AnimatedContainer),
      matching: find.byType(Text),
    ))
    .map((t) => t.data ?? '')
    .toList();

void main() {
  testWidgets('shows the formatted number, the boxes and a locked resend', (tester) async {
    final h = _Harness();
    await _open(tester, h);

    expect(find.textContaining('+91 98765 43210'), findsOneWidget);
    expect(find.byType(OtpBoxes), findsOneWidget);
    expect(find.text('Verify & continue'), findsOneWidget);
    // The countdown started when the screen mounted; _open has let one second
    // pass.
    expect(find.text('Resend in 0:29'), findsOneWidget);
    expect(find.byKey(ResendCountdown.actionKey), findsNothing);
  });

  group('entering the code', () {
    testWidgets('a pasted code fills all six boxes and verifies once', (tester) async {
      final h = _Harness()..auth.gate = Completer<void>();
      await _open(tester, h);

      // enterText replaces the whole value in one edit, which is what a paste
      // or an SMS autofill does.
      await tester.enterText(_field, '482913');
      await tester.pump();

      expect(_paintedDigits(tester), ['4', '8', '2', '9', '1', '3']);
      expect(h.auth.verified, ['482913']);
      h.auth.gate!.complete();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('backspace walks back one box at a time', (tester) async {
      final h = _Harness();
      await _open(tester, h);

      await tester.enterText(_field, '123');
      await tester.pump();
      expect(_paintedDigits(tester), ['1', '2', '3', '', '', '']);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(_paintedDigits(tester), ['1', '2', '', '', '', '']);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(_paintedDigits(tester), ['1', '', '', '', '', '']);
      expect(h.auth.verified, isEmpty);
    });

    testWidgets('an incomplete code is reported inline, never via SnackBar', (tester) async {
      final h = _Harness();
      await _open(tester, h);

      await tester.enterText(_field, '12');
      await tester.tap(find.text('Verify & continue'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Enter all 6 digits to continue.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(h.auth.verified, isEmpty);
    });
  });

  group('a wrong code', () {
    testWidgets('shakes, explains inline and clears the boxes', (tester) async {
      final h = _Harness();
      await _open(tester, h);

      await tester.enterText(_field, '000000');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final shake = tester.widget<Transform>(find.descendant(
        of: find.byType(Shake),
        matching: find.byType(Transform),
      ).first);
      expect(shake.transform.getTranslation().x, isNot(0));

      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('That code is not right. Check the digits and try again.'),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(_paintedDigits(tester), everyElement(''));
      expect(h.session.saved, isNull);
    });

    testWidgets('typing again clears the error', (tester) async {
      final h = _Harness();
      await _open(tester, h);

      await tester.enterText(_field, '000000');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(_field, '1');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('That code is not right'), findsNothing);
    });

    testWidgets('a dropped connection is reworded, never shown raw', (tester) async {
      final h = _Harness();
      h.auth.verifyResult = {'success': false, 'message': 'Network error: SocketException'};
      await _open(tester, h);

      await tester.enterText(_field, '123456');
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('Could not reach BookALook. Check your connection and try again.'),
          findsOneWidget);
    });

    testWidgets('a slow check says so instead of looking hung', (tester) async {
      final h = _Harness()..auth.gate = Completer<void>();
      await _open(tester, h);

      await tester.enterText(_field, '123456');
      await tester.pump(const Duration(seconds: 7));
      expect(find.textContaining('taking longer than usual'), findsOneWidget);

      h.auth.gate!.complete();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('resend', () {
    testWidgets('is unavailable during the countdown, then sends and relocks',
        (tester) async {
      final h = _Harness();
      await _open(tester, h);

      await tester.tap(find.text('Resend in 0:29'), warnIfMissed: false);
      await tester.pump();
      expect(h.auth.sends, 0);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Resend in 0:24'), findsOneWidget);

      await tester.pump(const Duration(seconds: 24));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(ResendCountdown.actionKey), findsOneWidget);

      await tester.tap(find.byKey(ResendCountdown.actionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(h.auth.sends, 1);
      expect(find.text('A new code is on its way.'), findsOneWidget);
      expect(find.text('Resend in 0:30'), findsOneWidget);
    });

    testWidgets('a failed resend is shown inline and can be retried at once',
        (tester) async {
      final h = _Harness();
      h.auth.sendResult = 'Network error: timeout';
      await _open(tester, h);

      await tester.pump(const Duration(seconds: 31));
      await tester.tap(find.byKey(ResendCountdown.actionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Could not reach BookALook. Check your connection and try again.'),
          findsOneWidget);
      // The countdown is not restarted, so trying again needs no waiting.
      expect(find.byKey(ResendCountdown.actionKey), findsOneWidget);
    });
  });

  group('a verified code', () {
    final roles = <String, Map<String, dynamic>>{
      'admin': {
        'role': 'admin',
        'salons': [
          {'id': 's1'},
        ],
      },
      'service_provider': {
        'role': 'service_provider',
        'salon': {'id': 's1'},
        'provider': {'id': 'p1'},
        'user': {'id': 'u1'},
      },
      'collaborator': {'role': 'collaborator'},
    };
    final expectedHome = <String, Type>{
      'admin': SalonSelectionScreen,
      'service_provider': ServiceProviderDashboard,
      'collaborator': CollaboratorDashboardScreen,
    };

    for (final role in roles.keys) {
      testWidgets('shows the tick, saves the session and routes a $role home',
          (tester) async {
        final h = _Harness();
        h.auth.verifyResult = {
          'success': true,
          'status': 'existing_user',
          'token': 'tok',
          ...roles[role]!,
        };
        await _open(tester, h);

        await tester.enterText(_field, '123456');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Held on the verified state before handing off.
        expect(find.byType(SuccessTick), findsOneWidget);
        expect(find.text('home:$role'), findsNothing);
        expect(h.session.saved?['token'], 'tok');

        await tester.pump(OtpScreen.verifiedHold);
        await tester.pump(const Duration(seconds: 1));

        expect(h.home.decided.runtimeType, expectedHome[role]);
        expect(find.text('home:$role'), findsOneWidget);
        // The auth stack is gone: back cannot return to the OTP or phone screen.
        expect(find.byType(OtpScreen), findsNothing);
        expect(find.text('phone screen'), findsNothing);
      });
    }

    testWidgets('a new number goes to registration with the phone and enquiry',
        (tester) async {
      final h = _Harness();
      h.auth.verifyResult = {
        'success': true,
        'status': 'new_user',
        'enquiry': {'owner_name': 'Asha', 'salon_name': 'Glow'},
      };
      await _open(tester, h);

      await tester.enterText(_field, '123456');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SuccessTick), findsOneWidget);
      expect(find.text('Let’s set up your salon…'), findsOneWidget);

      await tester.pump(OtpScreen.verifiedHold);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('registration wizard'), findsOneWidget);
      expect(h.registeredPhone, '9876543210');
      expect(h.registeredEnquiry?['owner_name'], 'Asha');
      // No session for someone who has not registered yet.
      expect(h.session.saved, isNull);
    });

    testWidgets('a role the app does not serve is explained, not left hanging',
        (tester) async {
      final h = _Harness();
      h.auth.verifyResult = {
        'success': true,
        'status': 'existing_user',
        'role': 'customer',
        'token': 'tok',
      };
      await _open(tester, h);

      await tester.enterText(_field, '123456');
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('cannot sign in to the Partner App'), findsOneWidget);
      expect(find.byType(SuccessTick), findsNothing);
      expect(h.session.saved, isNull);
    });
  });

  testWidgets('Change number returns to the phone screen', (tester) async {
    final h = _Harness();
    await _open(tester, h);

    await tester.tap(find.text('Change number'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(OtpScreen), findsNothing);
    expect(find.text('phone screen'), findsOneWidget);
  });

  group('themes and text size', () {
    testWidgets('dark mode draws the error state from AppColors', (tester) async {
      final h = _Harness();
      await _open(tester, h, theme: AppTheme.darkTheme);

      await tester.enterText(_field, '000000');
      await tester.pump(const Duration(milliseconds: 600));

      final note = tester.widget<StatusNote>(find.byType(StatusNote));
      expect(note.tone, AppColors.dark.danger);
      expect(note.background, AppColors.dark.dangerBg);
    });

    testWidgets('lays out without overflow at 200% text', (tester) async {
      final h = _Harness();
      await _open(tester, h, textScale: 2);
      expect(tester.takeException(), isNull);

      await tester.enterText(_field, '000000');
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('every control meets the 48dp touch target', (tester) async {
      final h = _Harness();
      await _open(tester, h);
      await tester.pump(const Duration(seconds: 31));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });

  test('the resend window is 30 seconds', () {
    expect(OtpScreen.resendSeconds, 30);
  });
}
