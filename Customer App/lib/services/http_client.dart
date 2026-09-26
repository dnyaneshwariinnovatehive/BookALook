import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http_real;
import 'auth_service.dart';
import 'deep_link_service.dart';
import '../screens/phone_screen.dart';

Future<void> _handle401(http_real.Response response) async {
  if (response.statusCode == 401) {
    await AuthService().logout();
    final context = DeepLinkService.navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const PhoneScreen(isModal: false, returnIndex: 0)),
        (route) => false,
      );
    }
  }
}

Future<http_real.Response> get(Uri url, {Map<String, String>? headers}) async {
  final response = await http_real.get(url, headers: headers);
  await _handle401(response);
  return response;
}

Future<http_real.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final response = await http_real.post(url, headers: headers, body: body, encoding: encoding);
  await _handle401(response);
  return response;
}

Future<http_real.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final response = await http_real.put(url, headers: headers, body: body, encoding: encoding);
  await _handle401(response);
  return response;
}

Future<http_real.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  final response = await http_real.delete(url, headers: headers, body: body, encoding: encoding);
  await _handle401(response);
  return response;
}
