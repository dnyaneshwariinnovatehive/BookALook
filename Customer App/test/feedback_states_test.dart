import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:customer_app/theme/app_colors.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/error_text.dart';
import 'package:customer_app/widgets/feedback_states.dart';
import 'package:customer_app/widgets/skeleton.dart';

Widget _app(Widget child, {ThemeData? theme, bool reduceMotion = false}) => MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  group('InlineStatus', () {
    testWidgets('shows the message and retries from its own button', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_app(InlineStatus(
        message: 'Could not load your bookings.',
        onRetry: () => retries++,
      )));

      expect(find.text('Could not load your bookings.'), findsOneWidget);
      await tester.tap(find.byKey(InlineStatus.retryKey));
      expect(retries, 1);
    });

    testWidgets('has no retry or dismiss unless asked for', (tester) async {
      await tester.pumpWidget(_app(const InlineStatus(message: 'Saved', kind: StatusKind.success)));
      expect(find.byKey(InlineStatus.retryKey), findsNothing);
      expect(find.byKey(InlineStatus.dismissKey), findsNothing);
    });

    testWidgets('is announced when it appears', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const InlineStatus(message: 'Offline')));
      expect(
        tester.getSemantics(find.text('Offline')),
        containsSemantics(label: 'Offline', isLiveRegion: true),
      );
      handle.dispose();
    });

    testWidgets('each kind takes its colours from the theme, in dark mode too', (tester) async {
      for (final (kind, tone) in [
        (StatusKind.error, AppColors.dark.danger),
        (StatusKind.warning, AppColors.dark.warning),
        (StatusKind.info, AppColors.dark.info),
        (StatusKind.success, AppColors.dark.success),
      ]) {
        await tester.pumpWidget(_app(InlineStatus(message: kind.name, kind: kind),
            theme: AppTheme.darkTheme));
        final text = tester.widget<Text>(find.text(kind.name));
        expect(text.style?.color, tone, reason: kind.name);
      }
    });
  });

  group('ErrorState', () {
    testWidgets('offers a retry that calls back', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_app(ErrorState(onRetry: () => retries++)));

      expect(find.text('Something went wrong'), findsOneWidget);
      await tester.tap(find.byKey(ErrorState.retryKey));
      expect(retries, 1);
    });

    testWidgets('the retry button meets the touch target', (tester) async {
      await tester.pumpWidget(_app(ErrorState(onRetry: () {})));
      expect(tester.getSize(find.byKey(ErrorState.retryKey)).height, greaterThanOrEqualTo(48));
    });
  });

  group('EmptyState', () {
    testWidgets('shows its next action and calls it', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(EmptyState(
        icon: Icons.calendar_today_outlined,
        title: 'No bookings yet',
        message: 'Find a salon near you.',
        actionLabel: 'Explore salons',
        onAction: () => taps++,
      )));

      expect(find.text('No bookings yet'), findsOneWidget);
      await tester.tap(find.byKey(EmptyState.actionKey));
      expect(taps, 1);
    });

    testWidgets('has no button without an action', (tester) async {
      await tester.pumpWidget(_app(const EmptyState(icon: Icons.inbox, title: 'Nothing here')));
      expect(find.byKey(EmptyState.actionKey), findsNothing);
    });
  });

  group('ScrollableState', () {
    testWidgets('lets pull-to-refresh work on an empty screen', (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(_app(RefreshIndicator(
        onRefresh: () async => refreshes++,
        child: const ScrollableState(
          child: EmptyState(icon: Icons.inbox, title: 'Nothing here'),
        ),
      )));

      await tester.fling(find.text('Nothing here'), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(refreshes, 1);
    });
  });

  group('Skeleton', () {
    testWidgets('is announced once as Loading', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(SkeletonList(itemBuilder: (_) => const SalonCardSkeleton())));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(find.byType(SalonCardSkeleton), findsWidgets);
      handle.dispose();
    });

    testWidgets('shimmers, but holds still under reduced motion', (tester) async {
      await tester.pumpWidget(_app(const Skeleton(child: SkeletonBox(height: 20))));
      expect(find.byType(ShaderMask), findsOneWidget);

      await tester.pumpWidget(_app(const Skeleton(child: SkeletonBox(height: 20)), reduceMotion: true));
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('every shape lays out in both themes', (tester) async {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(_app(
          const Skeleton(
            child: SingleChildScrollView(
              child: Column(children: [
                SalonCardSkeleton(),
                BookingCardSkeleton(),
                ResultRowSkeleton(),
                SizedBox(width: 100, child: CategoryTileSkeleton()),
              ]),
            ),
          ),
          theme: theme,
        ));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(_app(const SalonDetailSkeleton()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });

  group('describeError', () {
    test('connection failures become one plain sentence', () {
      const offline = 'Could not reach BookALook. Check your connection and try again.';
      expect(describeError(TimeoutException('slow')), offline);
      expect(describeError(http.ClientException('Connection closed')), offline);
    });

    test('a message the app wrote for people is kept', () {
      expect(describeError(Exception('This slot was just taken.')), 'This slot was just taken.');
    });

    test('raw bodies and unknown errors fall back', () {
      expect(describeError(Exception('{"message":"Server Error"}')),
          'Something went wrong. Please try again.');
      expect(describeError(StateError('bad state')), 'Something went wrong. Please try again.');
      expect(describeError(StateError('x'), fallback: 'Could not save.'), 'Could not save.');
    });
  });
}
