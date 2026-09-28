import 'dart:convert';

import 'package:customer_app/services/http_client.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'location_service.dart';

class DiscoveryService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  /// The distinct catalogue services a category genuinely offers, scoped to
  /// the customer's city. Backed by real active offerings only — never a
  /// templated guess.
  Future<List<DiscoveryServiceItem>> fetchCategoryServices(String categoryId) async {
    final queryParams = <String, dynamic>{
      'city_id': LocationService.instance.city?.id,
    }..removeWhere((k, v) => v == null || v.isEmpty);

    final location = LocationService.instance;
    if (location.hasPosition) {
      queryParams['lat'] = location.latitude!.toString();
      queryParams['lng'] = location.longitude!.toString();
    }

    final uri = Uri.parse('$baseUrl/customer/categories/$categoryId/services')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final body = await _get(uri);
    final list = (body['services'] as List<dynamic>? ?? [])
        .map((e) => DiscoveryServiceItem.fromJson(e as Map<String, dynamic>))
        .toList();
    LocationService.instance.adoptResolvedCity(body['city'] as Map<String, dynamic>?);
    return list;
  }

  /// Every combo package name in the city, once, with how many salons offer it
  /// and the cheapest price across them.
  Future<List<DiscoveryComboItem>> fetchCombos() async {
    final queryParams = <String, dynamic>{
      'city_id': LocationService.instance.city?.id,
    }..removeWhere((k, v) => v == null || v.isEmpty);

    final location = LocationService.instance;
    if (location.hasPosition) {
      queryParams['lat'] = location.latitude!.toString();
      queryParams['lng'] = location.longitude!.toString();
    }

    final uri = Uri.parse('$baseUrl/customer/combos')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final body = await _get(uri);
    final list = (body['combos'] as List<dynamic>? ?? [])
        .map((e) => DiscoveryComboItem.fromJson(e as Map<String, dynamic>))
        .toList();
    LocationService.instance.adoptResolvedCity(body['city'] as Map<String, dynamic>?);
    return list;
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load discovery data');
  }
}

/// A real, bookable catalogue service that some salon in the city offers.
class DiscoveryServiceItem {
  final String serviceId;
  final String name;
  final int durationMinutes;
  final double minPrice;
  final int salonCount;
  final double? rating;

  DiscoveryServiceItem({
    required this.serviceId,
    required this.name,
    required this.durationMinutes,
    required this.minPrice,
    required this.salonCount,
    this.rating,
  });

  factory DiscoveryServiceItem.fromJson(Map<String, dynamic> json) {
    return DiscoveryServiceItem(
      serviceId: json['service_id'] as String,
      name: json['name'] as String,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      minPrice: (json['min_price'] as num?)?.toDouble() ?? 0,
      salonCount: (json['salon_count'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }
}

/// A combo package, grouped by its exact name across salons.
class DiscoveryComboItem {
  final String name;
  final int salonCount;
  final double startingPrice;
  final double? rating;

  DiscoveryComboItem({
    required this.name,
    required this.salonCount,
    required this.startingPrice,
    this.rating,
  });

  factory DiscoveryComboItem.fromJson(Map<String, dynamic> json) {
    return DiscoveryComboItem(
      name: json['name'] as String,
      salonCount: (json['salon_count'] as num?)?.toInt() ?? 0,
      startingPrice: (json['starting_price'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }
}