import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider((ref) => AuthRepository(Supabase.instance.client));

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserProvider = Provider((ref) {
  return ref.watch(authRepositoryProvider).currentUser;
});

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? studentId,
    String? level,
  }) async {
    try {
      debugPrint('Attempting signup for $email');
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': role,
          'student_id_number': studentId,
          'level': level,
        },
      );

      if (response.user != null) {
        debugPrint('Signup successful for ${response.user!.id}, creating profile...');
        // Create a profile record in the public.profiles table
        await _client.from('profiles').upsert({
          'id': response.user!.id,
          'full_name': fullName,
          'role': role,
          'student_id_number': studentId,
          'level': level,
          'status': 'approved',
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('Profile created successfully');
      }

      return response;
    } on AuthException catch (e) {
      debugPrint('Auth error during signup: ${e.message} (Status: ${e.statusCode})');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during signup: $e');
      rethrow;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('Attempting signin for $email');
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      debugPrint('Signin successful for ${response.user?.id}');

      return response;
    } on AuthException catch (e) {
      debugPrint('Auth error during signin: ${e.message} (Status: ${e.statusCode})');
      rethrow;
    } on Exception catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('Connection failed')) {
        throw 'Network connection error. Please ensure you have internet access for the initial sign-in.';
      }
      debugPrint('Unexpected error during signin: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<int> getPendingCount() async {
    try {
      final response = await _client
          .from('profiles')
          .select('id')
          .eq('status', 'pending');
      return response.length;
    } catch (e) {
      debugPrint('Error fetching pending count: $e');
      return 0;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } catch (e) {
      debugPrint('Password reset error: $e');
      rethrow;
    }
  }
}
