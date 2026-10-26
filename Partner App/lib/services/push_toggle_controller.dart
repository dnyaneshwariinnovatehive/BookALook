import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

/// What the phone itself allows.
enum PushOsState {
  /// Notifications are allowed for the app.
  allowed,

  /// Never asked yet — the system prompt can still be shown.
  notAsked,

  /// Turned off in the phone's settings; only the settings screen can undo it.
  blocked,
}

/// The Push Notifications switch, as real apps do it.
///
/// Two things must both be on for a push to arrive: the account's preference
/// on the server (which the push job checks before sending) and the phone's own
/// permission. The switch shows on only when both are. Turning it on asks the
/// phone first — the system prompt if it has never been asked, otherwise an
/// offer to open the phone's notification settings — and when the person comes
/// back from those settings with notifications allowed, the switch finishes
/// turning on by itself. Turning it off only needs the server.
class PushToggleController extends ChangeNotifier with WidgetsBindingObserver {
  final Future<bool> Function() loadServer;
  final Future<void> Function(bool enabled) saveServer;
  final Future<PushOsState> Function() _osState;
  final Future<PushOsState> Function() _requestOs;
  final Future<void> Function() _openSettings;
  final Future<void> Function()? _registerDevice;

  PushToggleController({
    required this.loadServer,
    required this.saveServer,
    Future<PushOsState> Function()? osState,
    Future<PushOsState> Function()? requestOs,
    Future<void> Function()? openSettings,
    Future<void> Function()? registerDevice,
  })  : _osState = osState ?? _firebaseState,
        _requestOs = requestOs ?? _firebaseRequest,
        _openSettings = openSettings ?? _openNotificationSettings,
        _registerDevice = registerDevice;

  bool loading = true;
  bool saving = false;
  bool serverEnabled = true;
  PushOsState os = PushOsState.allowed;

  /// The person went to the phone's settings to turn notifications on.
  bool _pendingEnable = false;
  bool _disposed = false;

  /// What the switch shows.
  bool get enabled => serverEnabled && os == PushOsState.allowed;

  /// They want notifications, but the phone is not letting them through.
  bool get blockedByPhone => serverEnabled && os == PushOsState.blocked;

  String get statusText {
    if (loading) return '';
    if (enabled) return 'On';
    if (blockedByPhone) return 'Blocked in phone settings';
    return 'Off';
  }

  /// Start listening for the app coming back to the front, and load.
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await load();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([loadServer(), _osState()]);
      serverEnabled = results[0] as bool;
      os = results[1] as PushOsState;
    } catch (_) {
      // Unknown: keep the defaults rather than showing an error on a settings row.
    }
    loading = false;
    _notify();
  }

  /// Turn the switch on or off. Returns an error message to show, or null.
  ///
  /// [askToOpenSettings] is asked when the phone is blocking notifications;
  /// it returns true when the person chose to open the settings.
  Future<String?> setEnabled(bool value, {required Future<bool> Function() askToOpenSettings}) async {
    if (saving) return null;

    if (!value) return _save(false);

    var state = await _osState();
    if (state == PushOsState.notAsked) {
      state = await _requestOs();
    }
    os = state;

    if (state != PushOsState.allowed) {
      _notify();
      if (await askToOpenSettings()) {
        _pendingEnable = true;
        await _openSettings();
      }
      return null;
    }

    return _save(true);
  }

  Future<String?> _save(bool value) async {
    final before = serverEnabled;
    serverEnabled = value;
    saving = true;
    _notify();

    try {
      await saveServer(value);
      saving = false;
      _notify();
      if (value && _registerDevice != null) {
        // Make sure this phone's token is on file now that pushes are wanted.
        unawaited(_registerDevice().catchError((_) {}));
      }
      return null;
    } catch (_) {
      serverEnabled = before;
      saving = false;
      _notify();
      return 'Could not update notifications. Check your connection and try again.';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshFromPhone());
  }

  /// Re-read the phone's permission, e.g. on returning from its settings.
  Future<void> refreshFromPhone() async {
    os = await _osState();
    if (_pendingEnable && os == PushOsState.allowed) {
      _pendingEnable = false;
      await _save(true);
      return;
    }
    _pendingEnable = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ------------------------------------------------------------- platform

  static PushOsState _fromSettings(NotificationSettings s) => switch (s.authorizationStatus) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushOsState.allowed,
        AuthorizationStatus.notDetermined => PushOsState.notAsked,
        _ => PushOsState.blocked,
      };

  static Future<PushOsState> _firebaseState() async =>
      _fromSettings(await FirebaseMessaging.instance.getNotificationSettings());

  static Future<PushOsState> _firebaseRequest() async =>
      _fromSettings(await FirebaseMessaging.instance.requestPermission());

  static Future<void> _openNotificationSettings() =>
      AppSettings.openAppSettings(type: AppSettingsType.notification);
}

/// "Notifications are off for BookALook" with Not now / Open settings.
Future<bool> showOpenNotificationSettingsDialog(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Notifications are turned off'),
      content: const Text(
        'Notifications for BookALook are turned off in your phone settings. '
        'Open settings and allow notifications to turn them on.',
      ),
      actions: [
        TextButton(key: const ValueKey('push_settings_not_now'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        TextButton(key: const ValueKey('push_settings_open'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Open settings')),
      ],
    ),
  );
  return open == true;
}
