import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/services/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> signedIn() async {
    SharedPreferences.setMockInitialValues({'auth_token': 't', 'role': 'admin', 'auth_state': '{}'});
    return SharedPreferences.getInstance();
  }

  test('an expired login (401) is cleared', () async {
    final prefs = await signedIn();
    expect(await AuthSession.clearIfExpired(probe: () async => 401), isTrue);
    expect(prefs.getString('auth_token'), isNull);
    expect(prefs.getString('auth_state'), isNull);
  });

  test('a working login stays', () async {
    final prefs = await signedIn();
    expect(await AuthSession.clearIfExpired(probe: () async => 200), isFalse);
    expect(prefs.getString('auth_token'), 't');
  });

  test('being offline does not sign the partner out', () async {
    final prefs = await signedIn();
    expect(await AuthSession.clearIfExpired(probe: () async => throw Exception('offline')), isFalse);
    expect(prefs.getString('auth_token'), 't');
  });

  test('nobody signed in: nothing is asked', () async {
    SharedPreferences.setMockInitialValues({});
    var asked = false;
    expect(await AuthSession.clearIfExpired(probe: () async { asked = true; return 401; }), isFalse);
    expect(asked, isFalse);
  });
}
