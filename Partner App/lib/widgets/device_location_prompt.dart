import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/salon_location_api.dart';
import '../theme/app_theme.dart';

/// Read where the phone is, walking the user through whatever is in the way.
///
/// GPS switched off used to end in a bare "could not read the location". Now
/// it says so, opens the phone's Location settings, and tries again by itself
/// as soon as the user comes back to the app. A refused permission gets the
/// same treatment through the app's settings page.
///
/// Returns null when the user backs out or the position still cannot be read;
/// [onMessage] is told why, so the caller can show it its own way.
Future<Position?> captureDevicePosition(
  BuildContext context, {
  required void Function(String message) onMessage,
  @visibleForTesting Future<Position> Function()? readPosition,
  @visibleForTesting Future<bool> Function()? isGpsOn,
  @visibleForTesting Future<void> Function()? openLocationSettings,
  @visibleForTesting Future<void> Function()? openAppSettings,
  @visibleForTesting Future<void> Function()? waitForReturn,
}) async {
  final read = readPosition ?? SalonLocationApi.requireDevicePosition;
  final gpsOn = isGpsOn ?? Geolocator.isLocationServiceEnabled;
  final wait = waitForReturn ?? _nextResume;

  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      return await read();
    } on LocationDisabledException {
      if (!context.mounted) return null;
      final go = await _explain(
        context,
        icon: Icons.location_off_rounded,
        title: 'Turn on location (GPS)',
        body:
            'Your phone\'s location is switched off. Turn it on and come back — '
            'the salon will be pinned automatically.',
        action: 'Open location settings',
      );
      if (go != true) {
        onMessage('Location is off. You can pin the salon later.');
        return null;
      }
      final back = wait();
      await (openLocationSettings ?? SalonLocationApi.openLocationSettings)();
      await back;
      if (!await gpsOn()) {
        onMessage(
          'Location is still off. Turn it on and tap the button again.',
        );
        return null;
      }
      // Loop round once: GPS is on now, so read again.
    } on LocationPermissionDeniedException {
      onMessage(
        'Location permission was not given. Tap the button again to allow it.',
      );
      return null;
    } on LocationPermissionPermanentlyDeniedException {
      if (!context.mounted) return null;
      final go = await _explain(
        context,
        icon: Icons.lock_outline_rounded,
        title: 'Allow location access',
        body:
            'Location access for BookALook Partner is turned off. Allow it in the '
            'app settings and come back — the salon will be pinned automatically.',
        action: 'Open app settings',
      );
      if (go != true) {
        onMessage('Location access is off. You can pin the salon later.');
        return null;
      }
      final back = wait();
      await (openAppSettings ?? SalonLocationApi.openAppSettings)();
      await back;
    } catch (e) {
      onMessage(e.toString().replaceFirst('Exception: ', ''));
      return null;
    }
  }

  onMessage('Could not read the location. Try again in a moment.');
  return null;
}

/// Completes the next time the app comes back to the foreground (or after a
/// few minutes, so a forgotten settings trip never hangs the caller).
Future<void> _nextResume() {
  final done = Completer<void>();
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onResume: () {
      if (!done.isCompleted) done.complete();
      listener.dispose();
    },
  );
  return done.future.timeout(
    const Duration(minutes: 5),
    onTimeout: listener.dispose,
  );
}

Future<bool?> _explain(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String action,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: AppTheme.accentColor),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppTheme.lightTextBody,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('location-prompt-go'),
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(action),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
