import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/screens/otp_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/auth/otp_boxes.dart';

Widget _wrap(Widget child) => _wrapIn(AppTheme.lightTheme, child);

Widget _wrapIn(ThemeData theme, Widget child) => MaterialApp(
      theme: theme,
      home: child,
    );

/// ResendCountdown cross-fades, so the outgoing and incoming labels are both in
/// the tree mid-transition. Join them and let assertions look for a substring.
String _resendLabel(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((d) => d.startsWith('Resend'))
    .join(' | ');

void main() {
  testWidgets('OTP screen shows the boxes, a verify button and a resend countdown',
      (tester) async {
    await tester.pumpWidget(_wrap(const OtpScreen(phone: '9876543210')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.byType(OtpBoxes), findsOneWidget);
    expect(find.text('Verify & Login'), findsOneWidget);
    expect(find.textContaining('9876543210'), findsOneWidget);
    // Resend must be locked behind a countdown rather than immediately live.
    expect(_resendLabel(tester), contains('Resend in'));

    // It must actually count down, then unlock.
    await tester.pump(const Duration(seconds: 5));
    expect(_resendLabel(tester), contains('Resend in 0:24'));
    await tester.pump(const Duration(seconds: 24));
    expect(_resendLabel(tester), contains('Resend OTP'));
  });

  testWidgets('entering six digits is rejected with an inline message, no SnackBar',
      (tester) async {
    await tester.pumpWidget(_wrap(const OtpScreen(phone: '9876543210')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    await tester.enterText(find.byType(TextField), '1');
    await tester.pump();
    // A partial code must not fire verification on its own.
    expect(find.byType(SnackBar), findsNothing);

    // Pressing Verify with an incomplete code reports inline rather than in a
    // SnackBar, so nothing covers the keyboard or the boxes.
    await tester.tap(find.text('Verify & Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Enter all 6 digits to continue.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Change number returns to the previous screen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OtpScreen(phone: '9876543210'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    // pumpAndSettle cannot be used here: the ambient backdrop and the caret
    // repeat forever, so the tree never reaches a settled frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OtpScreen), findsOneWidget);

    await tester.tap(find.text('Change number'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OtpScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the stale test-code hint is not shown to users',
      (tester) async {
    await tester.pumpWidget(_wrap(const OtpScreen(phone: '9876543210')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    // The old screen printed "(For testing, use 123456)" to everyone.
    expect(find.textContaining('123456'), findsNothing);
  });

  testWidgets('dark mode resolves the OTP boxes from the theme',
      (tester) async {
    await tester.pumpWidget(_wrapIn(
      AppTheme.darkTheme,
      const OtpScreen(phone: '9876543210'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    // Idle boxes used to carry hardcoded light-mode border and label colours.
    final boxes = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .toList();
    expect(boxes, isNotEmpty);

    final idle = boxes
        .map((b) => b.decoration as BoxDecoration)
        .firstWhere((d) => d.border != null);
    expect((idle.border as Border).top.color, AppTheme.darkBorder,
        reason: 'idle box border must follow the dark theme');
  });
}
