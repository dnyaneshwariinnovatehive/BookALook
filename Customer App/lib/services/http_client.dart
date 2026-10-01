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
  // copy must not be stacked on top of it.
  final alreadyOnLogin = ModalRoute.of(context)?.settings.name == loginRouteName;

  await AuthService().logout();

  if (alreadyOnLogin) return;

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

Future<http_real.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final response = await _client.post(url, headers: headers, body: body, encoding: encoding);
  await _handle401(response);
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
