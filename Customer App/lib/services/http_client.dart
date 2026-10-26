import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http_real;
import 'app_version_service.dart';
import 'auth_service.dart';
import 'deep_link_service.dart';
import '../screens/mandatory_update_screen.dart';
import '../screens/phone_screen.dart';

/// Route name of the full-screen login page.
const String loginRouteName = 'auth-login';

/// Route name of the full-screen mandatory update page.
const String mandatoryUpdateRouteName = 'mandatory-update';

/// Client used for every request, replaceable in tests.
http_real.Client _client = http_real.Client();

/// Swaps the client used by [get], [post], [put] and [delete].
void debugSetClient(http_real.Client client) => _client = client;

/// Tracks the route on top of the root navigator, so an expiring session can
/// tell whether the customer is already looking at the login page.
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
    if (identical(route, _top)) _top = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (identical(oldRoute, _top)) _top = newRoute;
  }
}

/// Registered on the app's root navigator in main.dart.
final TopRouteObserver topRouteObserver = TopRouteObserver();

/// Injects app version and client headers to identify the mobile client for backend version enforcement.
Future<Map<String, String>> _mergeAppVersionHeaders(Map<String, String>? headers) async {
  final merged = Map<String, String>.from(headers ?? {});
  try {
    final installed = await AppVersionService.instance.getInstalledVersion();
    merged.putIfAbsent('X-App-Id', () => AppVersionService.appId);
    merged.putIfAbsent('X-App-Version', () => installed['version'] as String);
    merged.putIfAbsent('X-App-Build', () => (installed['build_number'] as int).toString());
  } catch (_) {}
  return merged;
}

/// Routes user to non-dismissible MandatoryUpdateScreen if backend returns HTTP 426 Upgrade Required.
Future<void> _handle426(http_real.Response response) async {
  if (response.statusCode != 426) return;

  final navigator = DeepLinkService.navigatorKey.currentState;
  final context = DeepLinkService.navigatorKey.currentContext;

  if (navigator == null || context == null) return;
  if (topRouteObserver.topRouteName == mandatoryUpdateRouteName) return;

  Map<String, dynamic>? decoded;
  try {
    decoded = jsonDecode(response.body) as Map<String, dynamic>?;
  } catch (_) {}

  final installed = await AppVersionService.instance.getInstalledVersion();
  final currentVer = installed['version'] as String;
  final currentBld = installed['build_number'] as int;

  final minVer = decoded?['minimum_version'] as String? ?? '2.0.0';
  final minBld = (decoded?['minimum_build'] as num?)?.toInt() ?? 1;
  final msg = decoded?['update_message'] as String? ?? decoded?['message'] as String?;
  final storeUrls = decoded?['store_urls'] as Map<String, dynamic>?;

  String? storeUrl;
  if (storeUrls != null) {
    try {
      storeUrl = Platform.isIOS ? storeUrls['ios'] as String? : storeUrls['android'] as String?;
    } catch (_) {
      storeUrl = storeUrls['android'] as String?;
    }
  }

  final info = AppUpdateInfo(
    type: UpdateType.mandatory,
    currentVersion: currentVer,
    currentBuild: currentBld,
    targetVersion: minVer,
    targetBuild: minBld,
    message: msg,
    storeUrl: storeUrl,
  );

  navigator.pushAndRemoveUntil(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: mandatoryUpdateRouteName),
      builder: (_) => MandatoryUpdateScreen(updateInfo: info),
    ),
    (route) => false,
  );
}

/// Sends the customer to the login screen when a request comes back unauthorised.
Future<void> _handle401(http_real.Response response, Map<String, String> sentHeaders) async {
  if (response.statusCode != 401) return;

  // Only a request that carried a session can mean the session expired. A
  // guest browsing without an account gets a 401 from anything that needs
  // one, and throwing them to the login screen for it took over the app on
  // first launch, right on top of the location prompt.
  final authorization = sentHeaders.entries
      .where((h) => h.key.toLowerCase() == 'authorization')
      .map((h) => h.value)
      .join();
  if (authorization.trim().isEmpty) return;

  if (!AuthService.beginSessionExpiryRedirect()) return;

  final navigator = DeepLinkService.navigatorKey.currentState;
  final context = DeepLinkService.navigatorKey.currentContext;

  if (navigator == null || context == null) {
    AuthService.cancelSessionExpiryRedirect();
    return;
  }

  final alreadyOnLogin = topRouteObserver.topRouteName == loginRouteName;

  await AuthService().logout();

  if (alreadyOnLogin) {
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

Future<http_real.Response> get(Uri url, {Map<String, String>? headers, bool redirectOn401 = true}) async {
  final effectiveHeaders = await _mergeAppVersionHeaders(headers);
  final response = await _client.get(url, headers: effectiveHeaders);
  await _handle426(response);
  if (redirectOn401) await _handle401(response, effectiveHeaders);
  return response;
}

Future<http_real.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  bool redirectOn401 = true,
}) async {
  final effectiveHeaders = await _mergeAppVersionHeaders(headers);
  final response = await _client.post(url, headers: effectiveHeaders, body: body, encoding: encoding);
  await _handle426(response);
  if (redirectOn401) await _handle401(response, effectiveHeaders);
  return response;
}

Future<http_real.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final effectiveHeaders = await _mergeAppVersionHeaders(headers);
  final response = await _client.put(url, headers: effectiveHeaders, body: body, encoding: encoding);
  await _handle426(response);
  await _handle401(response, effectiveHeaders);
  return response;
}

Future<http_real.Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final effectiveHeaders = await _mergeAppVersionHeaders(headers);
  final response = await _client.patch(url, headers: effectiveHeaders, body: body, encoding: encoding);
  await _handle426(response);
  await _handle401(response, effectiveHeaders);
  return response;
}

Future<http_real.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final effectiveHeaders = await _mergeAppVersionHeaders(headers);
  final response = await _client.delete(url, headers: effectiveHeaders, body: body, encoding: encoding);
  await _handle426(response);
  await _handle401(response, effectiveHeaders);
  return response;
}
