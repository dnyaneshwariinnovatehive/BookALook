import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// What happened when we asked Google Play to run an update.
enum PlayUpdateOutcome {
  /// Play took over: the immediate update screen ran, or a flexible download
  /// started in the background.
  started,

  /// Play showed its update prompt and the user said no.
  declined,

  /// Play can't do it here — not Android, the app wasn't installed from Play
  /// (debug / sideloaded builds), Play doesn't see a newer version for this
  /// user yet (staged rollout), or the API errored. Callers fall back to
  /// opening the store link.
  unavailable,
}

/// Google Play In-App Updates, on top of the server-driven update policy.
///
/// The backend (SuperAdmin → App Versions) still decides *whether* an update
/// is optional or mandatory. This only changes *how* the update is delivered:
///
/// * mandatory → Play's **immediate** flow (full-screen, Play installs and
///   restarts the app);
/// * optional → Play's **flexible** flow (downloads in the background while
///   the app stays usable, then a "Restart" snackbar installs it).
///
/// Every method is safe to call anywhere: on anything other than a
/// Play-installed Android build it reports [PlayUpdateOutcome.unavailable]
/// instead of throwing.
class PlayUpdateService {
  PlayUpdateService._();

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<AppUpdateInfo?> _check() async {
    if (!_supported) return null;
    try {
      return await InAppUpdate.checkForUpdate();
    } catch (e) {
      // Thrown for builds not installed from Play (ERROR_APP_NOT_OWNED),
      // devices without Play services, or no network.
      if (kDebugMode) debugPrint('[PlayUpdateService] checkForUpdate failed: $e');
      return null;
    }
  }

  /// Run Play's full-screen immediate update. Used for mandatory updates.
  static Future<PlayUpdateOutcome> startImmediate() async {
    final info = await _check();
    if (info == null) return PlayUpdateOutcome.unavailable;

    final inProgress = info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress;
    final available =
        info.updateAvailability == UpdateAvailability.updateAvailable && info.immediateUpdateAllowed;
    if (!inProgress && !available) return PlayUpdateOutcome.unavailable;

    try {
      final result = await InAppUpdate.performImmediateUpdate();
      switch (result) {
        case AppUpdateResult.success:
          return PlayUpdateOutcome.started;
        case AppUpdateResult.userDeniedUpdate:
          return PlayUpdateOutcome.declined;
        case AppUpdateResult.inAppUpdateFailed:
          return PlayUpdateOutcome.unavailable;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PlayUpdateService] performImmediateUpdate failed: $e');
      return PlayUpdateOutcome.unavailable;
    }
  }

  /// Google requires an immediate update that the user left (home button,
  /// app switch) to be resumed when the app comes back. Call on resume.
  static Future<void> resumeImmediateIfInProgress() async {
    final info = await _check();
    if (info?.updateAvailability != UpdateAvailability.developerTriggeredUpdateInProgress) return;
    try {
      await InAppUpdate.performImmediateUpdate();
    } catch (e) {
      if (kDebugMode) debugPrint('[PlayUpdateService] resume immediate failed: $e');
    }
  }

  /// Start Play's flexible update. Used for optional updates.
  ///
  /// Returns as soon as Play has accepted the request; the download carries on
  /// in the background and [onDownloaded] fires when it is ready to install.
  static Future<PlayUpdateOutcome> startFlexible({required VoidCallback onDownloaded}) async {
    final info = await _check();
    if (info == null) return PlayUpdateOutcome.unavailable;

    if (info.installStatus == InstallStatus.downloaded) {
      onDownloaded();
      return PlayUpdateOutcome.started;
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable || !info.flexibleUpdateAllowed) {
      return PlayUpdateOutcome.unavailable;
    }

    // startFlexibleUpdate() only completes once the download has finished, so
    // it is not awaited here — the caller's dialog has already closed.
    unawaited(
      InAppUpdate.startFlexibleUpdate().then((result) {
        if (result == AppUpdateResult.success) onDownloaded();
      }).catchError((Object e) {
        if (kDebugMode) debugPrint('[PlayUpdateService] flexible download failed: $e');
      }),
    );
    return PlayUpdateOutcome.started;
  }

  /// Whether a flexible update finished downloading earlier (for example in a
  /// previous session) and is waiting to be installed.
  static Future<bool> isFlexibleDownloaded() async {
    final info = await _check();
    return info?.installStatus == InstallStatus.downloaded;
  }

  /// Install a downloaded flexible update. Play restarts the app.
  static Future<void> completeFlexible() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      if (kDebugMode) debugPrint('[PlayUpdateService] completeFlexibleUpdate failed: $e');
    }
  }

  /// The "update ready" prompt Google recommends after a flexible download.
  /// Takes the messenger rather than a context because the dialog that
  /// started the download has usually closed by the time it finishes.
  static void showRestartSnackBar(ScaffoldMessengerState? messenger) {
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Update downloaded. Restart to finish installing.'),
        duration: const Duration(minutes: 10),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'RESTART',
          onPressed: () => unawaited(completeFlexible()),
        ),
      ),
    );
  }
}
