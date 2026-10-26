import 'package:customer_app/screens/phone_screen.dart';
import 'package:customer_app/services/auth_service.dart';
import 'package:customer_app/services/deep_link_service.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The splash checks a stored token before opening the app, so an expired
/// session goes straight to sign-in instead of flashing the location prompt
/// first. Only a clear rejection may end a session.
void main() {
  setUp(() {
    AuthService.cancelSessionExpiryRedirect();
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
  });

  test('a token the server accepts is kept', () async {
    api.debugSetClient(MockClient((_) async => http.Response('{}', 200)));
    expect(await AuthService.checkSession('t'), isTrue);
  });

  test('a token the server rejects is reported as expired', () async {
    api.debugSetClient(MockClient((_) async => http.Response('{}', 401)));
    expect(await AuthService.checkSession('t'), isFalse);
  });

  test('a server error or no network cannot tell, so nobody is signed out', () async {
    api.debugSetClient(MockClient((_) async => http.Response('{}', 500)));
    expect(await AuthService.checkSession('t'), isNull);

    api.debugSetClient(MockClient((_) async => throw http.ClientException('offline')));
    expect(await AuthService.checkSession('t'), isNull);
  });

  test('the check asks with the stored token', () async {
    String? sent;
    api.debugSetClient(MockClient((request) async {
      sent = request.headers['Authorization'];
      return http.Response('{}', 200);
    }));

    await AuthService.checkSession('abc');
    expect(sent, 'Bearer abc');
  });

  testWidgets('the check itself never pushes the login screen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: DeepLinkService.navigatorKey,
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: Text('splash')),
    ));
    api.debugSetClient(MockClient((_) async => http.Response('{}', 401)));

    await tester.runAsync(() => AuthService.checkSession('t'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(PhoneScreen), findsNothing);
  });

  test('a stale session is forgotten', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'old'});
    await AuthService.clearStaleSession();
    expect(await AuthService.getToken(), isNull);
  });
}
