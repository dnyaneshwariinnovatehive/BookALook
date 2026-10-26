import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'live_sync.dart';

/// Manages lifecycle-aware, visibility-aware periodic polling for Partner App screens.
///
/// Guarantees:
/// 1. Polls periodically (default 12s) only while the screen is active and the app
///    is in the foreground (resumed).
/// 2. Stops timers immediately when the app is paused, inactive, hidden, or backgrounded.
/// 3. Resumes polling and immediately fires a silent refresh when the app returns
///    to the foreground or when the screen becomes active.
/// 4. Prevents overlapping async requests with an in-flight guard ([isFetching]).
/// 5. Catches and logs errors during background silent polls without crashing or
///    interrupting future polling ticks.
/// 6. Cleans up timers and observers upon [dispose].
class LifecyclePoller with WidgetsBindingObserver {
  final Future<void> Function({bool silent}) onPoll;
  final Duration interval;
  final String debugLabel;

  Timer? _timer;
  StreamSubscription<void>? _liveSync;
  bool _isActive;
  bool _isDisposed = false;
  bool _isFetching = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  LifecyclePoller({
    required this.onPoll,
    this.interval = const Duration(seconds: 12),
    this.debugLabel = 'LifecyclePoller',
    bool autoStart = true,
  }) : _isActive = autoStart {
    WidgetsBinding.instance.addObserver(this);
    if (_isActive) {
      _startTimer();
    }
    // A booking changed somewhere: refresh now rather than at the next tick.
    // poll() already skips hidden screens and a backgrounded app.
    _liveSync = LiveSync.changes.listen((_) => poll(silent: true));
  }

  /// Whether this poller is currently considered visible/active by its screen/shell.
  bool get isActive => _isActive;

  /// Whether the periodic timer is currently armed.
  bool get isPolling => _timer != null && _timer!.isActive;

  /// Whether an async poll operation is currently in flight.
  bool get isFetching => _isFetching;

  /// Current app lifecycle state tracked by this poller.
  AppLifecycleState get lifecycleState => _lifecycleState;

  /// Sets whether the host tab/screen is visible to the user.
  ///
  /// When true, arms the periodic timer and triggers an immediate silent poll.
  /// When false, disarms the timer so background tabs do not consume battery or network.
  void setActive(bool active) {
    if (_isDisposed || _isActive == active) return;
    _isActive = active;

    if (_isActive) {
      _startTimer();
      poll(silent: true);
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _stopTimer();
    if (_isDisposed || !_isActive || _lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _timer = Timer.periodic(interval, (_) {
      poll(silent: true);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Executes a poll.
  ///
  /// Skips execution if a request is already in-flight ([isFetching]), or if
  /// running silently while inactive or not in foreground.
  Future<void> poll({bool silent = true}) async {
    if (_isDisposed || _isFetching) return;
    if (!_isActive && silent) return;
    if (_lifecycleState != AppLifecycleState.resumed && silent) return;

    _isFetching = true;
    try {
      await onPoll(silent: silent);
    } catch (e, stack) {
      debugPrint('[$debugLabel] Polling error: $e');
      if (kDebugMode) {
        debugPrint('[$debugLabel] Stack: $stack');
      }
    } finally {
      _isFetching = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleState(state);
  }

  /// Allows explicit lifecycle testing and handles platform lifecycle updates.
  @visibleForTesting
  void handleLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      if (_isActive && !_isDisposed) {
        _startTimer();
        poll(silent: true);
      }
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive ||
               state == AppLifecycleState.hidden) {
      _stopTimer();
    }
  }

  /// Disarms timer and unregisters observer.
  void dispose() {
    _isDisposed = true;
    _stopTimer();
    _liveSync?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
