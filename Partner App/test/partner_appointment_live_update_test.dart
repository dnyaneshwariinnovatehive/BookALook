import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/main.dart' show themeNotifier;
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/utils/lifecycle_poller.dart';
import 'package:partner_app/screens/dashboard/tabs/appointments_tab.dart';
import 'package:partner_app/screens/dashboard/tabs/home_tab.dart';
import 'package:partner_app/screens/dashboard/tabs/provider_home_tab.dart';
import 'package:partner_app/screens/provider_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'mock-test-token'});
    themeNotifier.value = ThemeMode.light;
  });

  tearDown(() {
    themeNotifier.value = ThemeMode.light;
  });

  group('LifecyclePoller Unit & Lifecycle Tests', () {
    test('starts periodic timer at specified interval when active', () async {
      int pollCount = 0;
      final poller = LifecyclePoller(
        interval: const Duration(seconds: 12),
        onPoll: ({bool silent = true}) async {
          pollCount++;
        },
      );

      expect(poller.isActive, isTrue);
      expect(poller.isPolling, isTrue);

      poller.dispose();
      expect(poller.isPolling, isFalse);
    });

    test('setActive(false) pauses polling; setActive(true) resumes and fires immediate poll', () async {
      int pollCount = 0;
      final poller = LifecyclePoller(
        interval: const Duration(seconds: 12),
        autoStart: true,
        onPoll: ({bool silent = true}) async {
          pollCount++;
        },
      );

      expect(poller.isPolling, isTrue);

      // Deactivate tab
      poller.setActive(false);
      expect(poller.isActive, isFalse);
      expect(poller.isPolling, isFalse);

      final countBefore = pollCount;

      // Reactivate tab
      poller.setActive(true);
      expect(poller.isActive, isTrue);
      expect(poller.isPolling, isTrue);
      expect(pollCount, countBefore + 1, reason: 'Immediate poll should run on activation');

      poller.dispose();
    });

    test('pauses polling when app lifecycle is paused/inactive and resumes on resumed', () async {
      int pollCount = 0;
      final poller = LifecyclePoller(
        interval: const Duration(seconds: 12),
        autoStart: true,
        onPoll: ({bool silent = true}) async {
          pollCount++;
        },
      );

      expect(poller.isPolling, isTrue);

      // Background app
      poller.handleLifecycleState(AppLifecycleState.paused);
      expect(poller.isPolling, isFalse);

      poller.handleLifecycleState(AppLifecycleState.inactive);
      expect(poller.isPolling, isFalse);

      // Foreground app
      final countBefore = pollCount;
      poller.handleLifecycleState(AppLifecycleState.resumed);
      expect(poller.isPolling, isTrue);
      expect(pollCount, countBefore + 1, reason: 'Should immediately poll upon returning to foreground');

      poller.dispose();
    });

    test('prevents overlapping async requests while a fetch is in-flight', () async {
      final completer = Completer<void>();
      int pollExecutions = 0;

      final poller = LifecyclePoller(
        interval: const Duration(seconds: 12),
        autoStart: true,
        onPoll: ({bool silent = true}) async {
          pollExecutions++;
          await completer.future;
        },
      );

      // Trigger first poll
      final future1 = poller.poll();
      expect(poller.isFetching, isTrue);

      // Trigger second concurrent poll while first is still awaiting completer
      final future2 = poller.poll();
      expect(pollExecutions, 1, reason: 'Second poll must be dropped while first is in-flight');

      // Complete first poll
      completer.complete();
      await future1;
      await future2;
      expect(poller.isFetching, isFalse);

      poller.dispose();
    });

    test('catches errors gracefully during background poll and does not crash', () async {
      int pollAttempts = 0;
      final poller = LifecyclePoller(
        interval: const Duration(seconds: 12),
        autoStart: true,
        onPoll: ({bool silent = true}) async {
          pollAttempts++;
          throw Exception('Simulated Network Socket Timeout');
        },
      );

      // Must not throw unhandled exception
      await expectLater(poller.poll(silent: true), completes);
      expect(pollAttempts, 1);
      expect(poller.isFetching, isFalse);

      poller.dispose();
    });
  });

  group('AppointmentsTab Lifecycle & Visibility Widget Tests', () {
    testWidgets('mounts with LifecyclePoller armed and handles setActive flips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppointmentsTab(salonId: 'test-salon-123'),
          ),
        ),
      );

      // Settle initial build
      await tester.pump();

      final state = tester.state<AppointmentsTabState>(find.byType(AppointmentsTab));
      expect(state.isPolling, isTrue);

      // Tab switcher deactivates tab
      state.setActive(false);
      await tester.pump();
      expect(state.isPolling, isFalse);

      // Tab switcher reactivates tab
      state.setActive(true);
      await tester.pump();
      expect(state.isPolling, isTrue);
    });

    testWidgets('unmounting tab cancels timer without leaking callbacks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppointmentsTab(salonId: 'test-salon-123'),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<AppointmentsTabState>(find.byType(AppointmentsTab));
      expect(state.isPolling, isTrue);

      // Replace with another widget to trigger dispose
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pump(const Duration(seconds: 15));

      // Timer should not fire against disposed state
    });

    testWidgets('RefreshIndicator is present for pull-to-refresh on appointments list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppointmentsTab(salonId: 'test-salon-123'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('HomeTab Lifecycle & Visibility Widget Tests', () {
    testWidgets('mounts with LifecyclePoller armed and handles setActive flips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: HomeTab(salonId: 'test-salon-123', salonName: 'Test Salon'),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<HomeTabState>(find.byType(HomeTab));
      expect(state.isPolling, isTrue);

      state.setActive(false);
      await tester.pump();
      expect(state.isPolling, isFalse);

      state.setActive(true);
      await tester.pump();
      expect(state.isPolling, isTrue);
    });
  });

  group('Provider Screens Lifecycle & Visibility Widget Tests', () {
    testWidgets('ProviderHomeTab mounts with LifecyclePoller armed and handles setActive flips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: ProviderHomeTab(
              salon: {'id': 1, 'name': 'Test Salon'},
              provider: {'id': 1, 'name': 'Test Provider', 'working_hours': []},
              user: {'id': 1, 'name': 'Staff User'},
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<ProviderHomeTabState>(find.byType(ProviderHomeTab));
      expect(state.isPolling, isTrue);

      state.setActive(false);
      await tester.pump();
      expect(state.isPolling, isFalse);

      state.setActive(true);
      await tester.pump();
      expect(state.isPolling, isTrue);
    });

    testWidgets('ProviderDashboardScreen mounts with LifecyclePoller armed and handles setActive flips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: ProviderDashboardScreen(salonId: 'test-salon-123'),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<ProviderDashboardScreenState>(find.byType(ProviderDashboardScreen));
      expect(state.isPolling, isTrue);

      state.setActive(false);
      await tester.pump();
      expect(state.isPolling, isFalse);

      state.setActive(true);
      await tester.pump();
      expect(state.isPolling, isTrue);
    });
  });
}
