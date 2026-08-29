// lib/services/reset_password_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> sendOTP(String email) async {
    try {
      final response = await supabase.functions.invoke(
        'send-reset-otp',
        body: {
          'email': email,
          'action': 'send',
        },
      );

      return {
        'success': true,
        'data': response.data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> resetPassword(
      String email,
      String otp,
      String newPassword,
      ) async {
    try {
      final response = await supabase.functions.invoke(
        'send-reset-otp',
        body: {
          'email': email,
          'action': 'reset',
          'otp': otp,
          'newPassword': newPassword,
        },
      );

      return {
        'success': true,
        'data': response.data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}