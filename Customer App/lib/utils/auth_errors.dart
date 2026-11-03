import 'dart:convert';

/// Turns what [AuthService.sendOtp] returns on failure into a sentence a
/// customer can act on.
///
/// The service reports failures as diagnostics — "HTTP Error 422: {json}" or
/// "Network Exception: SocketException…" — which are right for a log and wrong
/// for a screen: they show status codes, response bodies, sometimes an HTML
/// error page. This is the one place that translates them, at the UI edge, so
/// the service keeps returning everything a developer needs.
String friendlyAuthError(String? raw) {
  const generic = 'We could not send a code right now. Please try again.';
  if (raw == null || raw.isEmpty) return generic;

  if (raw.startsWith('Network Exception')) {
    return 'Could not reach BookALook. Check your connection and try again.';
  }

  final match = RegExp(r'^HTTP Error (\d{3}): ?(.*)$', dotAll: true).firstMatch(raw);
  if (match == null) return generic;

  final status = int.parse(match.group(1)!);
  // Too many tries, or codes cannot be sent: the server says how long to wait
  // or what is wrong, in words written for people.
  if (status == 429) {
    return _messageFrom(match.group(2)) ?? 'Too many attempts. Please wait a few minutes and try again.';
  }
  if (status == 503) {
    return _messageFrom(match.group(2)) ?? 'Login codes cannot be sent right now. Please try again later.';
  }
  if (status >= 500) {
    return 'Something went wrong on our side. Please try again in a moment.';
  }

  // A 4xx usually carries a message written for people — a validation error
  // on the phone number, most often. Use it if there is one.
  return _messageFrom(match.group(2)) ?? generic;
}

String? _messageFrom(String? body) {
  if (body == null || body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final errors = decoded['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty && value.first is String) {
          return value.first as String;
        }
        if (value is String && value.isNotEmpty) return value;
      }
    }

    final message = decoded['message'];
    if (message is String && message.isNotEmpty) return message;
  } catch (_) {
    // Not JSON — an HTML error page from a proxy, say. Never show that.
  }
  return null;
}
