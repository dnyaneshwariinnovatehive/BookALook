import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/banner.dart';

class BannerService {
  static String get baseUrl => '${dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api'}/customer/banners';

  /// Fetches active banners.
  /// [city] to fetch city-specific banners alongside platform banners.
  /// [salonId] to fetch salon-specific banners alongside platform banners.
  Future<List<PromoBanner>> fetchBanners({String? city, String? salonId}) async {
    try {
      final queryParams = <String, String>{};
      if (city != null) queryParams['target_city'] = city;
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
