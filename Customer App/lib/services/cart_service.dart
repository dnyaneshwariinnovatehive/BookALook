import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CartConflictException implements Exception {
  final String message;
  final String otherSalonName;
  CartConflictException(this.message, this.otherSalonName);
}

class CartService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  Future<Map<String, dynamic>?> getGlobalCart() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null) return null;

    final response = await http.get(
      Uri.parse('$baseUrl/customer/cart'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['cart'];
    } else {
      return null;
    }
  }

  Future<void> clearGlobalCart() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.delete(
      Uri.parse('$baseUrl/customer/cart'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to clear global cart');
    }
  }

  Future<Map<String, dynamic>?> getCart(String salonId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.get(
      Uri.parse('$baseUrl/customer/salons/$salonId/cart'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['cart'];
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Failed to load cart');
    }
  }

  Future<Map<String, dynamic>?> addItem(String salonId, String serviceId, {int quantity = 1}) =>
      _addToCart(salonId, {'service_id': serviceId, 'quantity': quantity});

  /// Adds a whole combo package. The backend explodes it into its constituent
  /// services when the appointment is booked.
  Future<Map<String, dynamic>?> addCombo(String salonId, String comboId, {int quantity = 1}) =>
      _addToCart(salonId, {'combo_id': comboId, 'quantity': quantity});

  /// Returns the cart as it stands after the add, so the caller can show what
  /// the customer just unlocked — a completed package, or what to add next.
  Future<Map<String, dynamic>?> _addToCart(String salonId, Map<String, dynamic> body) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/customer/salons/$salonId/cart/items'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 409) {
      final json = jsonDecode(response.body);
      if (json['different_salon'] == true) {
        throw CartConflictException(json['message'], json['current_salon_name']);
      }
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to add item to cart');
    }

    return jsonDecode(response.body)['cart'] as Map<String, dynamic>?;
  }

  Future<void> removeItem(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.delete(
      Uri.parse('$baseUrl/customer/cart/items/$itemId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove item');
    }
  }
}
