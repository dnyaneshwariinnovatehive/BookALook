import 'package:flutter/material.dart';

class AuthService {
  // Dummy API call for now
  Future<String> sendOtp(String phone) async {
    await Future.delayed(const Duration(seconds: 1));
    return 'success';
  }

  // Dummy OTP verify
  Future<bool> verifyOtp(String phone, String otp) async {
    await Future.delayed(const Duration(seconds: 1));
    return otp == '123456';
  }
}
