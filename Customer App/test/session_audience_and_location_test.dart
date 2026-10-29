import 'package:customer_app/services/audience_service.dart';
import 'package:customer_app/services/location_service.dart';
import 'package:customer_app/widgets/audience_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pune = ServiceCity(id: 'pune', name: 'Pune', state: 'MH', salonCount: 3, latitude: 18.5204, longitude: 73.8567);
const mumbai = ServiceCity(id: 'mumbai', name: 'Mumbai', state: 'MH', salonCount: 5, latitude: 19.0760, longitude: 72.8777);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'profile_gender': 'female'});
    AudienceService.resetSession();
  });

  group('gender picked in a filter', () {
    test('follows the profile until the customer picks one', () async {
      expect(await AudienceService.browsingGender(), 'female');
      expect(await AudienceService.browsingApiParam(), 'women');
    });

    test('a pick on one screen holds for every screen this session', () async {
      var ticks = 0;
      void listener() => ticks++;
      AudienceService.changes.addListener(listener);
      addTearDown(() => AudienceService.changes.removeListener(listener));

      AudienceService.choose('Men'); // home's vocabulary
      expect(ticks, 1);
      expect(await AudienceService.browsingGender(), 'male');
      expect(AudienceService.focusFilterFor(AudienceService.browsingGenderNow), 'Men Only');
      expect(await AudienceService.browsingApiParam(), 'men');

      AudienceService.choose('All');
      expect(await AudienceService.browsingApiParam(), isNull);
      expect(AudienceService.homeFilterFor(AudienceService.browsingGenderNow), 'All');

      // Re-picking what is already shown is not a change.
      AudienceService.choose('All');
      expect(ticks, 2);
    });

    test('is not saved to the device, and sign-out forgets it', () async {
      AudienceService.choose('Women Only');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k != 'profile_gender'), isEmpty);

      AudienceService.choose('Men');
      await AudienceService.forget();
      SharedPreferences.setMockInitialValues({'profile_gender': 'female'});
      expect(await AudienceService.browsingGender(), 'female');
    });

    testWidgets('the banner names the audience and Show all clears it', (tester) async {
      AudienceService.choose('Women');
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AudienceBanner())));

      expect(find.text('Showing salons and services for women'), findsOneWidget);
      await tester.tap(find.text('Show all'));
      await tester.pump();

      expect(find.byKey(const ValueKey('audience-banner')), findsNothing);
      expect(await AudienceService.browsingApiParam(), isNull);
    });
  });

  group('where distances are measured from', () {
    final location = LocationService.instance;

    test('picking the city you are in keeps your own position', () {
      location.debugSet(city: pune, deviceLat: 18.50, deviceLng: 73.80); // Kothrud
      expect(location.latitude, 18.50);
      expect(location.usingDevicePosition, isTrue);
    });

    test('browsing another city measures from that city, not 150 km away', () {
      location.debugSet(city: mumbai, deviceLat: 18.50, deviceLng: 73.80);
      expect(location.latitude, mumbai.latitude);
      expect(location.usingDevicePosition, isFalse);
    });

    test('no fix falls back to the city centre, and nothing at all to none', () {
      location.debugSet(city: pune);
      expect(location.latitude, pune.latitude);

      location.debugSet();
      expect(location.hasPosition, isFalse);
    });

    test('distance maths is sane', () {
      final km = LocationService.distanceKm(pune.latitude!, pune.longitude!, mumbai.latitude!, mumbai.longitude!);
      expect(km, inInclusiveRange(115, 125));
    });
  });
}
