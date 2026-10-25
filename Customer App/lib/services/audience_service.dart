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

  /// The customer's profile gender (`male`, `female`, `other`,
  /// `unspecified`), or null for a guest.
  static Future<String?> profileGender() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_key);
      if (cached != null) return cached;

      if (prefs.getString('auth_token') == null) return null;

      final data = await ProfileService().getProfile();
      final gender = (data['user']?['gender'] ?? 'unspecified').toString();
      await prefs.setString(_key, gender);
      return gender;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remember(String? gender) async {
    final prefs = await SharedPreferences.getInstance();
    if (gender == null || gender.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, gender);
    }
  }

  static Future<void> forget() => remember(null);

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
