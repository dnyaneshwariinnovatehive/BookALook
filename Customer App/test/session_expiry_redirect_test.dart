import 'package:customer_app/screens/phone_screen.dart';
import 'package:customer_app/services/auth_service.dart';
import 'package:customer_app/services/deep_link_service.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// How many login pages are on the stack.
int _loginPages(WidgetTester tester) => find.byType(PhoneScreen).evaluate().length;

void main() {
  setUp(() {
    // Start every test from a clean single-flight claim.
    AuthService.cancelSessionExpiryRedirect();
    api.debugSetClient(MockClient((_) async => http.Response('{}', 401)));
  });

  Widget app() {
    return MaterialApp(
      navigatorKey: DeepLinkService.navigatorKey,
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: Center(child: Text('content'))),
    );
  }

  group('session expiry redirect', () {
    testWidgets('concurrent 401s push the login screen only once', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      // Every in-flight request fails together when a token expires.
      await Future.wait([
        api.get(Uri.parse('http://localhost/a')),
        api.get(Uri.parse('http://localhost/b')),
        api.get(Uri.parse('http://localhost/c')),
        api.get(Uri.parse('http://localhost/d')),
      ]);
      await tester.pump(const Duration(milliseconds: 600));

      expect(_loginPages(tester), 1);
    });

    testWidgets('a 401 after login expires again redirects', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      await api.get(Uri.parse('http://localhost/a'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_loginPages(tester), 1);

      // Storing a new token makes the next expiry a genuine new event.
      AuthService.markSessionAuthenticated();

      await api.get(Uri.parse('http://localhost/b'));
      await tester.pump(const Duration(milliseconds: 600));

      expect(_loginPages(tester), 1);
    });

    testWidgets('expiring while already on login does not stack a second copy',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      await api.get(Uri.parse('http://localhost/a'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_loginPages(tester), 1);

      AuthService.markSessionAuthenticated();

      await api.get(Uri.parse('http://localhost/b'));
      await tester.pump(const Duration(milliseconds: 600));

      expect(_loginPages(tester), 1);
    });

    testWidgets('a non-401 response never redirects', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      api.debugSetClient(MockClient((_) async => http.Response('{}', 500)));

      await api.get(Uri.parse('http://localhost/a'));
      await tester.pump(const Duration(milliseconds: 600));

      expect(_loginPages(tester), 0);
    });
  });

  group('single-flight claim', () {
    test('only the first caller may redirect', () {
      expect(AuthService.beginSessionExpiryRedirect(), isTrue);
      expect(AuthService.beginSessionExpiryRedirect(), isFalse);
      expect(AuthService.beginSessionExpiryRedirect(), isFalse);

      AuthService.cancelSessionExpiryRedirect();
      expect(AuthService.beginSessionExpiryRedirect(), isTrue);
    });

    test('authenticating releases the claim', () {
      expect(AuthService.beginSessionExpiryRedirect(), isTrue);
      AuthService.markSessionAuthenticated();
      expect(AuthService.beginSessionExpiryRedirect(), isTrue);
    });
  });
}
