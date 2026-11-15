import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' as app;
import '../screens/appointment_details_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/provider_appointment_details_screen.dart';
import 'appointment_service.dart';
import 'notification_service.dart';

/// Decides what a tapped push notification opens.
///
/// * A booking notice (it carries `appointment_id` and `salon_id`) opens that
///   booking: the owner's booking screen for an owner, the staff booking
///   screen for a staff member.
/// * Anything else opens the Notifications list for an owner. Staff and
///   collaborators simply land in the app.
/// * The notification is marked read either way, as tapping it in the list
///   would.
///
/// A tap that launches the app from closed arrives before the splash screen
/// has decided where to go, and the splash then *replaces* whatever is on top.
/// So taps are held until the splash calls [markAppReady].
class NotificationRouter {
  NotificationRouter._();

  static Map<String, dynamic>? _pending;
  static bool _appReady = false;

  /// Called by the splash screen once it has moved on to the first real
  /// screen. Opens a tap that arrived while the app was starting.
  static void markAppReady() {
    _appReady = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      // Let the splash → home fade (500 ms) finish before pushing on top.
      Future.delayed(const Duration(milliseconds: 650), () => unawaited(_open(pending)));
    }
  }

  /// Entry point for every tap: system tray, in-app banner, or cold start.
  static void handleTap(Map<String, dynamic> data) {
    if (!_appReady) {
      _pending = Map<String, dynamic>.from(data);
      return;
    }
    unawaited(_open(data));
  }

  static Future<void> _open(Map<String, dynamic> data) async {
    final notificationId = (data['notification_id'] ?? '').toString();
    if (notificationId.isNotEmpty) {
      unawaited(PartnerNotificationService.markRead(notificationId).catchError((Object _) {}));
    }

    final role = await _signedInRole();
    if (role == null || role == 'collaborator') return;

    final appointmentId = (data['appointment_id'] ?? '').toString();
    final salonId = (data['salon_id'] ?? '').toString();

    if (appointmentId.isNotEmpty && salonId.isNotEmpty) {
      Map<String, dynamic>? appointment;
      try {
        appointment = await PartnerAppointmentService().getAppointment(salonId, appointmentId);
      } catch (e) {
        debugPrint('Could not load booking from notification: $e');
      }

      final nav = app.navigatorKey.currentState;
      if (nav == null) return;

      if (appointment != null) {
        final booking = appointment;
        unawaited(nav.push(MaterialPageRoute(
          builder: (_) => role == 'service_provider'
              ? ProviderAppointmentDetailsScreen(appointment: booking, salonId: salonId)
              : AppointmentDetailsScreen(appointment: booking, salonId: salonId),
        )));
        return;
      }
      _snack('That booking is no longer available.');
    }

    if (role == 'admin') {
      unawaited(app.navigatorKey.currentState
          ?.push(MaterialPageRoute(builder: (_) => const NotificationsScreen())));
    }
  }

  /// `admin`, `service_provider`, `collaborator`, or null when signed out.
  static Future<String?> _signedInRole() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final state = prefs.getString('auth_state');
    if (token == null || token.isEmpty || state == null) return null;
    try {
      final role = jsonDecode(state)['role'];
      return role is String ? role : null;
    } catch (_) {
      return null;
    }
  }

  static void _snack(String message) {
    final context = app.navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }
}
