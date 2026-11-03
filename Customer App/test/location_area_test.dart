import 'package:customer_app/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pune = ServiceCity(id: 'c-pune', name: 'Pune', state: 'Maharashtra', salonCount: 12, latitude: 18.52, longitude: 73.85);
const mumbai = ServiceCity(id: 'c-mum', name: 'Mumbai', state: 'Maharashtra', salonCount: 40);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final location = LocationService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    location.debugSet();
    LocationService.areaResolver = (lat, lng) async => null;
  });

  group('header', () {
    test('with an area: area in bold, "City, State" under it', () {
      location.debugSet(city: pune, area: 'Kothrud');

      expect(location.headline, 'Kothrud');
      expect(location.subline, 'Pune, Maharashtra');
      expect(location.label, 'Kothrud, Pune');
    });

    test('without an area: the city is the headline, the state under it', () {
      location.debugSet(city: pune);

      expect(location.headline, 'Pune');
      expect(location.subline, 'Maharashtra');
      expect(location.label, 'Pune');
    });

    test('nothing chosen yet', () {
      expect(location.headline, 'Select location');
      expect(location.subline, isNull);
    });
  });

  group('choosing a place', () {
    test('an area is kept with its city and cleared when only a city is chosen', () async {
      await location.setCity(pune, area: 'Baner');
      expect(location.area, 'Baner');

      await location.setCity(mumbai);
      expect(location.city?.id, 'c-mum');
      expect(location.area, isNull, reason: 'a whole-city choice drops the old area');
    });

    test('recent places: newest first, no duplicates, at most four', () async {
      await location.setCity(pune, area: 'Kothrud');
      await location.setCity(mumbai);
      await location.setCity(pune, area: 'Baner');
      await location.setCity(pune, area: 'Kothrud'); // again: moves to the top
      await location.setCity(pune, area: 'Aundh');
      await location.setCity(pune, area: 'Wakad');

      final recent = await location.recentPlaces();
      expect(recent.map((p) => p.title).toList(), ['Wakad', 'Aundh', 'Kothrud', 'Baner']);
      expect(recent.first.subtitle, 'Pune, Maharashtra');
    });
  });

  group('area from the phone position', () {
    test('a city the server placed them in gets its area named from the fix', () async {
      LocationService.areaResolver = (lat, lng) async => 'Kothrud';
      location.debugSet(deviceLat: 18.50, deviceLng: 73.81);

      location.adoptResolvedCity({'id': pune.id, 'name': pune.name, 'state': pune.state});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(location.city?.id, pune.id);
      expect(location.area, 'Kothrud');
      expect(location.headline, 'Kothrud');
    });

    test('a "locality" that is just the city name is not shown twice', () async {
      LocationService.areaResolver = (lat, lng) async => 'Pune';
      location.debugSet(deviceLat: 18.50, deviceLng: 73.81);

      location.adoptResolvedCity({'id': pune.id, 'name': pune.name, 'state': pune.state});
      await Future<void>.delayed(Duration.zero);

      expect(location.area, isNull);
      expect(location.headline, 'Pune');
    });

    test('no fix: nothing is guessed', () async {
      var asked = false;
      LocationService.areaResolver = (lat, lng) async {
        asked = true;
        return 'Somewhere';
      };

      location.adoptResolvedCity({'id': pune.id, 'name': pune.name, 'state': pune.state});
      await Future<void>.delayed(Duration.zero);

      expect(asked, isFalse);
      expect(location.area, isNull);
    });
  });
}
