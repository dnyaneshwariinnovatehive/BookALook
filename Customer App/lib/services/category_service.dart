import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/category.dart';

class CategoryService {
  static String get baseUrl => '${dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api'}/customer/categories';

  Future<List<ServiceCategory>> fetchCategories() async {
    try {
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        final List<dynamic> data = jsonResponse['categories'];
        return data.map((json) => ServiceCategory.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Fetch categories error: $e');
      return [];
    }
  }
}
