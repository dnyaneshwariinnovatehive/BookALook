import 'dart:async';

/// App-wide "the salon's bookings just changed" signal.
///
/// The backend sends a silent push to every partner-app phone at a salon when a
/// booking is made, cancelled, moved, started or finished. The push service
/// turns it into a [ping], and every [LifecyclePoller] listening refreshes its
/// screen straight away instead of waiting for its next tick.
class LiveSync {
  LiveSync._();

  static final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires once per change notice.
  static Stream<void> get changes => _changes.stream;

  /// Announce that bookings changed and open screens should reload.
  static void ping() => _changes.add(null);
}
