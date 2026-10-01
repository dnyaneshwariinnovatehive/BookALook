import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:partner_app/theme/app_colors.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/utils/auth_motion.dart';
import 'package:partner_app/widgets/auth/otp_boxes.dart';

Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    ),
  );
}

LinearGradient _gradientOf(WidgetTester tester) {
  final ink = tester.widget<Ink>(find.descendant(
    of: find.byType(SweepButton),
    matching: find.byType(Ink),
  ));
  return (ink.decoration! as BoxDecoration).gradient! as LinearGradient;
}

void main() {
  group('SweepButton', () {
    testWidgets('paints the brand gradient while idle', (tester) async {
      await tester.pumpWidget(_wrap(SweepButton(label: 'Continue', onPressed: () {})));
      await tester.pump();

      expect(
        _gradientOf(tester).colors.map((c) => c.toARGB32()),
        containsAll(<int>[
          AppTheme.accentGradientStart.toARGB32(),
          AppTheme.accentGradientEnd.toARGB32(),
        ]),
      );
    });

    testWidgets('runs a sheen while loading and stops when idle', (tester) async {
      Widget button(bool loading) =>
          _wrap(SweepButton(label: 'Continue', loading: loading, onPressed: () {}));

      await tester.pumpWidget(button(true));
      await tester.pump();
      final a = _gradientOf(tester).begin;
      await tester.pump(const Duration(milliseconds: 300));
      final b = _gradientOf(tester).begin;
      expect(a, isNot(equals(b)), reason: 'the sheen should be moving');
      // The label stays put rather than being swapped for a spinner.
      expect(find.text('Continue'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(button(false));
      await tester.pump();
      final c = _gradientOf(tester).begin;
      await tester.pump(const Duration(milliseconds: 300));
      expect(_gradientOf(tester).begin, equals(c), reason: 'idle must be still');
    });

    testWidgets('holds still while loading under reduced motion', (tester) async {
      await tester.pumpWidget(_wrap(
        SweepButton(label: 'Continue', loading: true, onPressed: () {}),
        disableAnimations: true,
      ));
      await tester.pump();
      final a = _gradientOf(tester).begin;
      await tester.pump(const Duration(milliseconds: 300));
      expect(_gradientOf(tester).begin, equals(a));
    });

    testWidgets('ignores taps while loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
          _wrap(SweepButton(label: 'Continue', loading: true, onPressed: () => taps++)));
      await tester.tap(find.byType(SweepButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('is announced as a button and meets the touch target', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(SweepButton(label: 'Continue', onPressed: () {})));
      await tester.pump();

      expect(
        tester.getSemantics(find.byType(SweepButton)),
        containsSemantics(
          label: 'Continue',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(find.byType(SweepButton)).height,
          greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('grows instead of clipping at 2x text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SweepButton(label: 'Continue', leading: Icons.arrow_forward, onPressed: () {}),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Shake', () {
    Future<double> dxAfter(WidgetTester tester, Duration d) async {
      await tester.pump(d);
      final t = tester.widget<Transform>(find.descendant(
        of: find.byType(Shake),
        matching: find.byType(Transform),
      ));
      return t.transform.getTranslation().x;
    }

    testWidgets('is still until the token changes, then displaces and returns',
        (tester) async {
      Widget shake(int token, {bool reduce = false}) => _wrap(
            Shake(token: token, child: const SizedBox(width: 10, height: 10)),
            disableAnimations: reduce,
          );

      await tester.pumpWidget(shake(0));
      expect(await dxAfter(tester, Duration.zero), 0);

      await tester.pumpWidget(shake(1));
      expect((await dxAfter(tester, const Duration(milliseconds: 60))).abs(),
          greaterThan(0));
      expect(await dxAfter(tester, const Duration(milliseconds: 600)), 0);
    });

    testWidgets('does not move under reduced motion', (tester) async {
      await tester.pumpWidget(_wrap(
        const Shake(token: 0, child: SizedBox(width: 10, height: 10)),
        disableAnimations: true,
      ));
      await tester.pumpWidget(_wrap(
        const Shake(token: 1, child: SizedBox(width: 10, height: 10)),
        disableAnimations: true,
      ));
      expect(await dxAfter(tester, const Duration(milliseconds: 60)), 0);
    });
  });

  group('StaggeredReveal', () {
    double opacityOf(WidgetTester tester, String text) {
      final opacity = tester.widget<Opacity>(find
          .ancestor(of: find.text(text), matching: find.byType(Opacity))
          .first);
      return opacity.opacity;
    }

    testWidgets('children appear in order, not all at once', (tester) async {
      await tester.pumpWidget(_wrap(const StaggeredReveal(
        children: [Text('first'), Text('second'), Text('third')],
      )));
      await tester.pump(const Duration(milliseconds: 150));
      expect(opacityOf(tester, 'first'), greaterThan(opacityOf(tester, 'third')));

      await tester.pump(const Duration(seconds: 1));
      expect(opacityOf(tester, 'third'), 1);
    });

    testWidgets('shows everything at once under reduced motion', (tester) async {
      await tester.pumpWidget(_wrap(
        const StaggeredReveal(children: [Text('first'), Text('third')]),
        disableAnimations: true,
      ));
      await tester.pump();
      expect(
        find.ancestor(of: find.text('third'), matching: find.byType(Opacity)),
        findsNothing,
      );
    });
  });

  group('OtpBoxes', () {
    Finder field() => find.byKey(OtpBoxes.fieldKey);

    testWidgets('typing fills boxes in order and fires completed once',
        (tester) async {
      final controller = TextEditingController();
      var completed = 0;
      await tester.pumpWidget(_wrap(
        OtpBoxes(controller: controller, onCompleted: () => completed++),
      ));
      await tester.pump();

      await tester.enterText(field(), '123');
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(completed, 0);

      await tester.enterText(field(), '123456');
      await tester.pump();
      expect(completed, 1);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('rejects non-digits and caps at six', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrap(OtpBoxes(controller: controller)));
      await tester.pump();

      await tester.enterText(field(), '12ab34567890');
      await tester.pump();
      expect(controller.text, '123456');
    });

    testWidgets('the boxes are hidden from screen readers; the field is labelled',
        (tester) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController(text: '12');
      await tester.pumpWidget(_wrap(OtpBoxes(controller: controller)));
      await tester.pump();

      expect(find.bySemanticsLabel(RegExp('One-time code, 6 digits')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('error state paints the danger token from the theme',
        (tester) async {
      final controller = TextEditingController(text: '12');
      await tester.pumpWidget(_wrap(
        OtpBoxes(controller: controller, hasError: true, autofocus: false),
        brightness: Brightness.dark,
      ));
      await tester.pump();

      final boxes = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      final border = ((boxes.first.decoration! as BoxDecoration).border! as Border).top;
      expect(border.color, AppColors.dark.danger);
    });
  });

  group('SuccessTick', () {
    testWidgets('uses the success token and is announced', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(const SuccessTick()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Verified'), findsOneWidget);
      handle.dispose();
    });
  });

  group('ResendCountdown', () {
    testWidgets('offers no action during the countdown, then a live one',
        (tester) async {
      var resent = 0;
      await tester.pumpWidget(_wrap(ResendCountdown(seconds: 24, onResend: () => resent++)));
      expect(find.text('Resend in 0:24'), findsOneWidget);
      expect(find.byKey(ResendCountdown.actionKey), findsNothing);
      await tester.tap(find.text('Resend in 0:24'));
      expect(resent, 0);

      await tester.pumpWidget(_wrap(ResendCountdown(onResend: () => resent++)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(ResendCountdown.actionKey));
      expect(resent, 1);
    });
  });

  group('StatusNote', () {
    testWidgets('renders the message as a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(StatusNote(
        text: 'That code is not right.',
        tone: AppColors.light.danger,
        background: AppColors.light.dangerBg,
        icon: Icons.error_outline_rounded,
      )));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('That code is not right.'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('That code is not right.')),
        containsSemantics(label: 'That code is not right.', isLiveRegion: true),
      );
      handle.dispose();
    });
  });

  group('AuthShell', () {
    for (final brightness in Brightness.values) {
      testWidgets('paints an opaque ${brightness.name} base from the theme tokens',
          (tester) async {
        await tester.pumpWidget(_wrap(
          const AuthShell(child: Text('content')),
          brightness: brightness,
        ));
        await tester.pump();

        final base = tester.widget<ColoredBox>(find.descendant(
          of: find.byType(AuthShell),
          matching: find.byType(ColoredBox),
        ).first);
        final expected = brightness == Brightness.dark
            ? AppColors.dark.surfaceMuted
            : AppColors.light.surfaceMuted;
        expect(base.color, expected);
        expect(base.color.a, 1.0);
        expect(find.text('content'), findsOneWidget);
      });
    }
  });

  group('authRoute', () {
    testWidgets('covers the outgoing route on the very first frame', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Text('old screen')),
      ));

      navigator.currentState!.push(authRoute<void>(
        builder: (_) => const Scaffold(body: Text('new screen')),
      ));
      await tester.pump();

      final backdrop = tester.widget<ColoredBox>(find.byKey(AuthMotion.routeBackdropKey));
      expect(backdrop.color, AppColors.light.surfaceMuted);
      expect(backdrop.color.a, 1.0);

      await tester.pumpAndSettle();
      expect(find.text('new screen'), findsOneWidget);
    });
  });
}
