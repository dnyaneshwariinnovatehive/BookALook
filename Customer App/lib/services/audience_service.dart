import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_service.dart';

/// Who the customer is browsing for, by default: themselves.
///
/// Their profile gender decides what discovery shows first — a woman sees
/// Unisex and Women Only services, with a chip that says so and lets her
/// switch to everything. "Other" and "prefer not to say" see everything.
///
/// The gender is cached on the device so the home screen does not wait on a
/// profile request, and refreshed whenever the profile is saved.
class AudienceService {
  AudienceService._();

  static const _key = 'profile_gender';

  /// What the customer picked in a gender filter during this run of the app:
  /// `men`, `women` or `all`. Null until they pick one, which means "follow
  /// the profile". Held in memory only, so it lasts until the app is closed
  /// and every screen — home, categories, Explore, search, a salon's menu —
  /// browses for the same people.
  static String? _sessionChoice;

  /// The profile gender as last read, so a widget can draw without waiting.
  static String? _profileCache;

  /// Ticks whenever the browsing audience changes, so open screens can reload.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// The customer's profile gender (`male`, `female`, `other`,
  /// `unspecified`), or null for a guest.
  static Future<String?> profileGender() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_key);
      if (cached != null) return _profileCache = cached;

      if (prefs.getString('auth_token') == null) return null;

      final data = await ProfileService().getProfile();
      final gender = (data['user']?['gender'] ?? 'unspecified').toString();
      await prefs.setString(_key, gender);
      return _profileCache = gender;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remember(String? gender) async {
    final before = browsingGenderNow;
    _profileCache = (gender == null || gender.isEmpty) ? null : gender;
    if (browsingGenderNow != before) changes.value++;

    final prefs = await SharedPreferences.getInstance();
    if (gender == null || gender.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, gender);
    }
  }

  /// Signing out: the next person starts from their own profile again.
  static Future<void> forget() {
    _sessionChoice = null;
    return remember(null);
  }

  /// Who discovery is for right now: the filter picked this session, else
  /// the profile gender. Returned as a profile gender (`male`, `female`,
  /// `unspecified`) so it plugs into [homeFilterFor], [focusFilterFor] and
  /// [serves]; null for a guest who has not picked.
  static Future<String?> browsingGender() async {
    if (_sessionChoice != null) return browsingGenderNow;
    return profileGender();
  }

  /// [browsingGender] without waiting, from what is already known.
  static String? get browsingGenderNow => switch (_sessionChoice) {
        'men' => 'male',
        'women' => 'female',
        'all' => 'unspecified',
        _ => _profileCache,
      };

  /// The `gender` query parameter for the current audience, or null for all.
  static Future<String?> browsingApiParam() async => apiParam(homeFilterFor(await browsingGender()));

  /// Record a gender picked in any filter (`All`, `Men`, `Women Only`, ...).
  /// It holds for the rest of this app session, everywhere.
  static void choose(String filter) {
    final before = browsingGenderNow;
    _sessionChoice = apiParam(filter) ?? 'all';
    if (browsingGenderNow != before) changes.value++;
  }

  /// For tests: back to following the profile.
  @visibleForTesting
  static void resetSession() {
    _sessionChoice = null;
    _profileCache = null;
  }

  /// The home screen's filter value for a profile gender: Men, Women or All.
  static String homeFilterFor(String? gender) => switch (gender) {
        'male' => 'Men',
        'female' => 'Women',
        _ => 'All',
      };

  /// The category screen's filter value: Men Only, Women Only or All.
  static String focusFilterFor(String? gender) => switch (gender) {
        'male' => 'Men Only',
        'female' => 'Women Only',
        _ => 'All',
      };

  /// The `gender` query parameter the API takes for any of those filter
  /// values, or null when the filter means everyone.
  static String? apiParam(String? filter) => switch (filter?.toLowerCase()) {
        'men' || 'men only' || 'male' => 'men',
        'women' || 'women only' || 'female' => 'women',
        _ => null,
      };

  /// The service focus ("Men Only"/"Women Only") a person of this gender is
  /// served by, or null when every service is for them.
  static String? focusOf(String? gender) => switch (gender) {
        'male' => 'Men Only',
        'female' => 'Women Only',
        _ => null,
      };

  /// Whether a service whose effective audience is [audience] is meant for
  /// someone of [gender]. Unisex, mixed combos and unknowns always are.
  static bool serves(String? audience, String? gender) {
    final focus = focusOf(gender);
    if (focus == null) return true;
    if (audience == null || audience == 'Unisex' || audience == 'Mixed') return true;
    return audience == focus;
  }

  static String genderLabel(String? gender) => switch (gender) {
        'male' => 'Male',
        'female' => 'Female',
        'other' => 'Other',
        _ => 'Not specified',
      };
}
