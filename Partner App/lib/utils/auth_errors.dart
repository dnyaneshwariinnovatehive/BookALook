/// Turns raw [AuthService] failures into something a person can act on.
///
/// The service passes through the server's own message, which is written for
/// users, but on a dropped connection or a timeout it returns "Network error: "
/// plus the exception text — that must never reach the screen.
String friendlyAuthError(String? message, {required String fallback}) {
  if (message == null || message.trim().isEmpty) return fallback;
  if (message.startsWith('Network error')) {
    return 'Could not reach BookALook. Check your connection and try again.';
  }
  return message;
}
