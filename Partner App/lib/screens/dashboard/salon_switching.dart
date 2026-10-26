import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import 'dashboard_screen.dart';
import 'salon_selection_screen.dart';

/// Which of an owner's salons the app is working on, across launches.
///
/// An owner with several branches comes back to the one they used last; the
/// list is only for choosing another. The list itself is re-read from the
/// server whenever it is shown, so a salon approved since sign-in is not
/// still shown as pending.
class SalonSession {
  SalonSession._();

  static const lastSalonKey = 'last_salon_id';

  /// Statuses that open the dashboard. The others explain themselves from
  /// the list instead (pending, corrections, rejected, deactivated).
  static const _openable = {'active', 'approved', 'suspended'};

  static bool canOpen(dynamic salon) =>
      salon is Map && _openable.contains(salon['status']?.toString());

  static Future<void> remember(String salonId) async {
    if (salonId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastSalonKey, salonId);
  }

  static Future<String?> lastSalonId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastSalonKey);
  }

  /// The salons saved at sign-in (or last refresh).
  static Future<List<dynamic>> cachedSalons() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('auth_state');
    if (raw == null) return const [];
    try {
      final state = jsonDecode(raw);
      return state is Map && state['salons'] is List ? List<dynamic>.from(state['salons']) : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Fresh salons from the server, saved for next time. Null when offline or
  /// the server did not answer in [timeout] — callers fall back to the cache.
  static Future<List<dynamic>?> refresh({
    Duration timeout = const Duration(seconds: 5),
    Future<List<dynamic>?> Function()? fetch,
  }) async {
    List<dynamic>? fresh;
    try {
      fresh = await (fetch ?? ApiService.getMySalons)().timeout(timeout);
    } catch (_) {
      return null;
    }
    if (fresh == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('auth_state');
    if (raw != null) {
      try {
        final state = Map<String, dynamic>.from(jsonDecode(raw));
        state['salons'] = fresh;
        await prefs.setString('auth_state', jsonEncode(state));
      } catch (_) {}
    }
    return fresh;
  }

  /// The salon to open straight away: the last one used, else the only one.
  /// Null when the owner should choose from the list.
  static Map<String, dynamic>? startSalon(List<dynamic> salons, String? lastId) {
    if (lastId != null) {
      for (final salon in salons) {
        if (salon is Map && salon['id']?.toString() == lastId && canOpen(salon)) {
          return Map<String, dynamic>.from(salon);
        }
      }
    }
    if (salons.length == 1 && canOpen(salons.first)) {
      return Map<String, dynamic>.from(salons.first as Map);
    }
    return null;
  }

  /// Where a signed-in owner lands: their last salon, or the list.
  static Widget homeFor(List<dynamic> salons, {String? lastSalonId}) {
    final start = startSalon(salons, lastSalonId);
    return start != null ? DashboardScreen(salonData: start) : SalonSelectionScreen(salons: salons);
  }

  /// Open the salon list to switch to another branch, from anywhere.
  static Future<void> openPicker(BuildContext context) async {
    final salons = await cachedSalons();
    if (!context.mounted) return;
    unawaited(Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SalonSelectionScreen(salons: salons)),
      (route) => false,
    ));
  }
}
