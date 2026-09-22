import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'location_service.dart';

/// One search across services and salons.
///
/// Scoped to the chosen city, because a haircut two cities away is not a
/// result — it is a dead end the customer has to work out for themselves.
class CustomerSearchService {
  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  static Future<SearchResults> search(String query) async {
    final cityId = LocationService.instance.city?.id;

    final uri = Uri.parse('$_baseUrl/customer/search').replace(queryParameters: {
      'q': query,
      if (cityId != null) 'city_id': cityId,
    });

    final response = await http.get(uri, headers: {'Accept': 'application/json'});

    if (response.statusCode == 200) {
      return SearchResults.fromJson(jsonDecode(response.body));
    }

    throw Exception('Search is unavailable right now.');
  }
}

class SearchResults {
  final List<ServiceHit> services;
  final List<SalonHit> salons;
  final List<CategoryHit> categories;

  /// The spelling the server thinks was meant, when the query was a near miss.
  final String? didYouMean;

  SearchResults({
    required this.services,
    required this.salons,
    required this.categories,
    this.didYouMean,
  });

  bool get isEmpty => services.isEmpty && salons.isEmpty && categories.isEmpty;

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        services: ((json['services'] ?? []) as List)
            .map((r) => ServiceHit.fromJson(r))
            .toList(),
        salons:
            ((json['salons'] ?? []) as List).map((r) => SalonHit.fromJson(r)).toList(),
        categories: ((json['categories'] ?? []) as List)
            .map((r) => CategoryHit.fromJson(r))
            .toList(),
        didYouMean: json['did_you_mean'],
      );
}

/// A service at a particular salon — the unit a customer is actually shopping
/// for, which is why it carries the salon rather than pointing at one.
class ServiceHit {
  final String serviceId;
  final String name;
  final String? category;
  final double price;
  final int durationMinutes;
  final SalonHit salon;

  ServiceHit({
    required this.serviceId,
    required this.name,
    required this.price,
    required this.durationMinutes,
    required this.salon,
    this.category,
  });

  factory ServiceHit.fromJson(Map<String, dynamic> json) => ServiceHit(
        serviceId: json['service_id'].toString(),
        name: json['name'] ?? '',
        category: json['category'],
        price: (json['price'] as num?)?.toDouble() ?? 0,
        durationMinutes: json['duration_minutes'] ?? 0,
        salon: SalonHit.fromJson(json['salon'] ?? {}),
      );
}

class SalonHit {
  final String id;
  final String name;
  final String? area;
  final double avgRating;
  final int reviewCount;

  SalonHit({
    required this.id,
    required this.name,
    this.area,
    this.avgRating = 0,
    this.reviewCount = 0,
  });

  factory SalonHit.fromJson(Map<String, dynamic> json) => SalonHit(
        id: json['id']?.toString() ?? '',
        name: json['name'] ?? '',
        area: json['area'],
        avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0,
        reviewCount: json['review_count'] ?? 0,
      );

  bool get hasRating => reviewCount > 0 && avgRating > 0;
}

class CategoryHit {
  final String id;
  final String name;
  final String? iconUrl;

  CategoryHit({required this.id, required this.name, this.iconUrl});

  factory CategoryHit.fromJson(Map<String, dynamic> json) => CategoryHit(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        iconUrl: json['icon_url'],
      );
}
