import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppointmentService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  /// Staff of the salon, each flagged with `is_eligible` against the services
  /// currently in the cart. Ineligible staff are returned too, so the UI can
  /// grey them out instead of hiding them.
  Future<Map<String, dynamic>> getSalonProviders(String salonId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.get(
      Uri.parse('$baseUrl/customer/salons/$salonId/providers'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load service providers');
    }
  }

  /// 30-minute blocks for [date]. Every block is returned; unavailable ones
  /// carry `available: false` and a `reason`.
  /// [providerId] null means "Any Available".
  Future<Map<String, dynamic>> getAvailableSlots(String salonId, String date, {String? providerId}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final query = {
      'date': date,
      if (providerId != null) 'provider_id': providerId,
    };

    final response = await http.get(
      Uri.parse('$baseUrl/customer/salons/$salonId/availability').replace(queryParameters: query),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to load slots');
    }
  }

  Future<Map<String, dynamic>> bookAppointment(String salonId, String date, String time, {String? providerId}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/customer/salons/$salonId/appointments/book'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'date': date,
        'time': time,
        if (providerId != null) 'provider_id': providerId,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to book appointment');
    }
  }

  Future<Map<String, dynamic>> getMyBookings() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.get(
      Uri.parse('$baseUrl/customer/appointments'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load bookings');
    }
  }

  /// Cancels a booking. Returns the refund breakdown the server computed from
  /// each service's own refund setting.
  Future<Map<String, dynamic>> cancelAppointment(String id, {String? reason}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/customer/appointments/$id/cancel'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({if (reason != null) 'reason': reason}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to cancel appointment');
    }
  }

  /// Providers and (when [date] is given) the slot grid for moving an existing
  /// booking. The booking's own slot does not block itself.
  Future<Map<String, dynamic>> getRescheduleOptions(String appointmentId, {String? date, String? providerId}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final query = {
      if (date != null) 'date': date,
      if (providerId != null) 'provider_id': providerId,
    };

    final response = await http.get(
      Uri.parse('$baseUrl/customer/appointments/$appointmentId/reschedule-options')
          .replace(queryParameters: query.isEmpty ? null : query),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to load reschedule options');
    }
  }

  Future<Map<String, dynamic>> rescheduleAppointment(
    String appointmentId,
    String date,
    String time, {
    String? providerId,
    String? reason,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/customer/appointments/$appointmentId/reschedule'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'date': date,
        'time': time,
        if (providerId != null) 'provider_id': providerId,
        if (reason != null) 'reason': reason,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to reschedule appointment');
    }
  }

  Future<Map<String, dynamic>> generateQr(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/customer/appointments/$id/generate-qr'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to generate QR');
    }
  }
  Future<Map<String, dynamic>> demoPay(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/customer/appointments/$id/payment/demo-pay'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to complete demo payment');
    }
  }

  Future<Map<String, dynamic>> confirmPayment(String id, String paymentId, String signature) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/customer/appointments/$id/payment/confirm'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to confirm payment');
    }
  }

  Future<Map<String, dynamic>> abandonPayment(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/customer/appointments/$id/payment/abandon'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to abandon payment');
    }
  }
}
