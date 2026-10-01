import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http_real;
import 'auth_service.dart';
import 'deep_link_service.dart';
import '../screens/phone_screen.dart';

/// Route name of the full-screen login page.
///
/// Named so an expiring session can recognise that the customer is already
/// looking at it instead of pushing a second copy on top.
const String loginRouteName = 'auth-login';

/// Client used for every request, replaceable in tests.
http_real.Client _client = http_real.Client();

/// Swaps the client used by [get], [post], [put] and [delete].
void debugSetClient(http_real.Client client) => _client = client;

/// Tracks the route on top of the root navigator, so an expiring session can
/// tell whether the customer is already looking at the login page.
///
/// It has to be an observer. The obvious check —
/// `ModalRoute.of(navigatorKey.currentContext)` — always returns null: the
/// navigator's own context sits above every route it hosts. That check used to
/// be here, never fired, and only looked correct because the redirect clears
/// the whole stack anyway, which also threw away whatever the customer had
/// typed on the login page.
class TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? _top;

  /// Name of the route currently on top, or null if it has none.
  String? get topRouteName => _top?.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _top = route;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _top)) _top = previousRoute;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // pushAndRemoveUntil reports the new route first and then removes the old
    // ones underneath it; only a removal of the top route moves the top.
    if (identical(route, _top)) _top = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (identical(oldRoute, _top)) _top = newRoute;
  }
}

/// Registered on the app's root navigator in main.dart.
final TopRouteObserver topRouteObserver = TopRouteObserver();

/// Sends the customer to the login screen when a request comes back unauthorised.
///
/// An expired token fails every request that is in flight at the same moment,
/// so without this guard each of those responses would push the login screen
/// again and the page would appear several times in a row. Only the first
/// response of an expiry burst may navigate.
Future<void> _handle401(http_real.Response response) async {
  if (response.statusCode != 401) return;

  if (!AuthService.beginSessionExpiryRedirect()) return;

  final navigator = DeepLinkService.navigatorKey.currentState;
  final context = DeepLinkService.navigatorKey.currentContext;

  if (navigator == null || context == null) {
    // Nothing to navigate yet. Release the claim so a later 401 can redirect.
    AuthService.cancelSessionExpiryRedirect();
    return;
  }

  // If the login screen is already what the customer is looking at, another
  // copy must not replace it — that would also wipe the number they typed.
  final alreadyOnLogin = topRouteObserver.topRouteName == loginRouteName;

  await AuthService().logout();

  if (alreadyOnLogin) {
    // They are where the redirect would have taken them. Release the claim so
    // the session that follows can still be redirected when it expires.
    AuthService.cancelSessionExpiryRedirect();
    return;
  }

  navigator.pushAndRemoveUntil(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: loginRouteName),
      builder: (context) => const PhoneScreen(isModal: false, returnIndex: 0),
    ),
    (route) => false,
  );
}

Future<http_real.Response> get(Uri url, {Map<String, String>? headers}) async {
  final response = await _client.get(url, headers: headers);
  await _handle401(response);
  return response;
}

/// [redirectOn401] is false only for the auth endpoints themselves. Signing in
/// is not something a session can expire out of, and logging out with an
/// already-expired token answers 401 by design — redirecting then would race
/// the logout's own navigation to the login page.
Future<http_real.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  bool redirectOn401 = true,
}) async {
  final response = await _client.post(url, headers: headers, body: body, encoding: encoding);
  if (redirectOn401) await _handle401(response);
  return response;
}

Future<http_real.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final response = await _client.put(url, headers: headers, body: body, encoding: encoding);
  await _handle401(response);
  return response;
}

Future<http_real.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final response = await _client.delete(url, headers: headers, body: body, encoding: encoding);
  await _handle401(response);
  return response;
}
