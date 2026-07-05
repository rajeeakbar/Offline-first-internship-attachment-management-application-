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
  }) async {
    try {
      print('Attempting signup for $email');
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'role': role},
      );

      if (response.user != null) {
        print('Signup successful for ${response.user!.id}, creating profile...');
        // Create a profile record in the public.profiles table
        await _client.from('profiles').upsert({
          'id': response.user!.id,
          'full_name': fullName,
          'role': role,
          'status': 'pending',
          'updated_at': DateTime.now().toIso8601String(),
        });
        print('Profile created successfully');
      }

      return response;
    } on AuthException catch (e) {
      print('Auth error during signup: ${e.message} (Status: ${e.statusCode})');
      rethrow;
    } catch (e) {
      print('Unexpected error during signup: $e');
      rethrow;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      print('Attempting signin for $email');
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      print('Signin successful for ${response.user?.id}');
      return response;
    } on AuthException catch (e) {
      print('Auth error during signin: ${e.message} (Status: ${e.statusCode})');
      rethrow;
    } catch (e) {
      print('Unexpected error during signin: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
