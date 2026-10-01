import 'dart:async';

import 'package:http/http.dart' as http;

/// A sentence a customer can act on, for an error caught in the UI.
///
/// Screens used to print `'Failed: $e'`, which shows "Exception: ..." or a
/// SocketException's internals. Connection problems get one plain message;
/// an Exception the app threw itself has its message kept, because services
/// throw those with copy written for people; everything else gets [fallback].
///
/// Socket and TLS errors are recognised by type name rather than by importing
/// dart:io, which the web build cannot use.
String describeError(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  final type = error.runtimeType.toString();
  if (error is TimeoutException ||
      error is http.ClientException ||
      type == 'SocketException' ||
      type == 'HandshakeException') {
    return 'Could not reach BookALook. Check your connection and try again.';
  }

  final text = error.toString();
  const prefix = 'Exception: ';
  if (error is Exception && text.startsWith(prefix)) {
    final message = text.substring(prefix.length).trim();
    // A raw response body or a stack of internals is not a message.
    if (message.isNotEmpty &&
        message.length <= 160 &&
        !message.contains('{') &&
        !message.contains('<')) {
      return message;
    }
  }
  return fallback;
}
