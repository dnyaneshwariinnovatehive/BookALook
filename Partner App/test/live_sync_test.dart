import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/utils/lifecycle_poller.dart';
import 'package:partner_app/utils/live_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a live-sync ping refreshes an open screen straight away', () async {
    var polls = 0;
    final poller = LifecyclePoller(
      onPoll: ({bool silent = true}) async => polls++,
      interval: const Duration(hours: 1),
    );

    LiveSync.ping();
    await Future<void>.delayed(Duration.zero);

    expect(polls, 1);
    poller.dispose();
  });

  test('a hidden screen ignores the ping', () async {
    var polls = 0;
    final poller = LifecyclePoller(
      onPoll: ({bool silent = true}) async => polls++,
      interval: const Duration(hours: 1),
      autoStart: false,
    );

    LiveSync.ping();
    await Future<void>.delayed(Duration.zero);

    expect(polls, 0);
    poller.dispose();
  });

  test('a backgrounded app ignores the ping', () async {
    var polls = 0;
    final poller = LifecyclePoller(
      onPoll: ({bool silent = true}) async => polls++,
      interval: const Duration(hours: 1),
    );
    poller.handleLifecycleState(AppLifecycleState.paused);

    LiveSync.ping();
    await Future<void>.delayed(Duration.zero);

    expect(polls, 0);
    poller.dispose();
  });

  test('a disposed poller stops listening', () async {
    var polls = 0;
    final poller = LifecyclePoller(
      onPoll: ({bool silent = true}) async => polls++,
      interval: const Duration(hours: 1),
    );
    poller.dispose();

    LiveSync.ping();
    await Future<void>.delayed(Duration.zero);

    expect(polls, 0);
  });
}
