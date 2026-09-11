import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/banner.dart';
import 'location_service.dart';

class BannerService {
  static String get baseUrl => '${dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api'}/customer/banners';

  /// Fetches active banners.
  ///
  /// [cityId] defaults to the customer's chosen city, so a campaign SuperAdmin
  /// aimed at one city actually reaches it. The app used to send `target_city`,
  /// which the API does not read — city banners were silently never shown.
  Future<List<PromoBanner>> fetchBanners({String? cityId, String? salonId}) async {
    try {
      final queryParams = <String, String>{};

      final city = cityId ?? LocationService.instance.city?.id;
      if (city != null && city.isNotEmpty) queryParams['target_city_id'] = city;
      if (salonId != null) queryParams['target_salon_id'] = salonId;

      final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => PromoBanner.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Fetch banners error: $e');
      return [];
    }
  }
}
