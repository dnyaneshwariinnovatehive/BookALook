import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:partner_app/screens/dashboard/collaborator_dashboard.dart';
import 'package:partner_app/screens/dashboard/salon_selection_screen.dart';
import 'package:partner_app/screens/dashboard/service_provider_dashboard.dart';
import 'package:partner_app/screens/partner_home.dart';
import 'package:partner_app/services/auth_session.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AuthSession.save', () {
    final response = <String, dynamic>{
      'success': true,
      'status': 'existing_user',
      'role': 'admin',
      'token': 'tok-123',
      'salons': [
        {'id': 's1', 'name': 'Glow Studio'},
      ],
      'user': {'name': 'Asha', 'phone': '9876543210'},
    };

    test('writes the same three keys the app has always read', () async {
      await AuthSession(registerPush: () async {}).save(response);
      final prefs = await SharedPreferences.getInstance();

      // These names are read by the splash screen, the salon picker and every
      // API service. Renaming one signs every installed partner out.
      expect(prefs.getString('auth_token'), 'tok-123');
      expect(prefs.getString('role'), 'admin');
      expect(jsonDecode(prefs.getString('auth_state')!), response);
    });

    test('stores auth_state in the shape the splash screen routes on', () async {
      await AuthSession(registerPush: () async {}).save(response);
      final prefs = await SharedPreferences.getInstance();

      // Mirrors splash_screen.dart: decode, then branch on role.
      final state = jsonDecode(prefs.getString('auth_state')!);
      expect(state['role'], 'admin');
      expect(state['salons'], isA<List>());
      // And salon_selection_screen.dart reads the owner's phone from it.
      expect(state['user']['phone'], '9876543210');
    });

    test('registers for push, and a push failure does not fail the sign-in',
        () async {
      var pushed = 0;
      await AuthSession(registerPush: () async {
        pushed++;
        throw Exception('firebase unavailable');
      }).save(response);
      await Future<void>.delayed(Duration.zero);

      expect(pushed, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'tok-123');
    });
  });

  group('partnerHomeFor', () {
    test('an admin lands on the salon picker with their salons', () {
      final home = partnerHomeFor({
        'role': 'admin',
        'salons': [
          {'id': 's1'},
        ],
      });
      expect(home, isA<SalonSelectionScreen>());
      expect((home! as SalonSelectionScreen).salons, hasLength(1));
    });

    test('an admin with no salons still gets an empty list, not null', () {
      final home = partnerHomeFor({'role': 'admin'}) as SalonSelectionScreen;
      expect(home.salons, isEmpty);
    });

    test('a service provider lands on their dashboard with salon, provider, user',
        () {
      final home = partnerHomeFor({
        'role': 'service_provider',
        'salon': {'id': 's1'},
        'provider': {'id': 'p1'},
        'user': {'id': 'u1'},
      }) as ServiceProviderDashboard;
      expect(home.salon['id'], 's1');
      expect(home.provider['id'], 'p1');
      expect(home.user['id'], 'u1');
    });

    test('a collaborator lands on the collaborator dashboard', () {
      expect(partnerHomeFor({'role': 'collaborator'}), isA<CollaboratorDashboardScreen>());
    });

    test('an unknown role has no home', () {
      expect(partnerHomeFor({'role': 'customer'}), isNull);
      expect(partnerHomeFor({}), isNull);
    });
  });
}
