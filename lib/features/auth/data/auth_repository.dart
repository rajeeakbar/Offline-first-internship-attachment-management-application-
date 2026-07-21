import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/local_database.dart';

final authRepositoryProvider = Provider((ref) => AuthRepository(Supabase.instance.client));

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserProvider = Provider((ref) {
  // Watch authStateProvider to force re-evaluation of currentUser on state changes
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUser;
});

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? studentId,
    String? level,
  }) async {
    final now = DateTime.now().toIso8601String();
    final passwordHash = _hashPassword(password);

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
        final profileData = {
          'id': response.user!.id,
          'full_name': fullName,
          'role': role,
          'student_id_number': studentId,
          'level': level,
          'status': 'approved',
          'updated_at': now,
        };
        await _client.from('profiles').upsert(profileData);

        // Also cache locally with password hash and email for offline login
        final db = await LocalDatabase.instance.database;
        await db.insert('profiles', {
          ...profileData,
          'email': email,
          'password_hash': passwordHash,
          'is_dirty': 0,
          'is_deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        debugPrint('Profile created successfully and cached.');
      }

      return response;
    } catch (e) {
      debugPrint('Signup error: $e');
      final errStr = e.toString().toLowerCase();
      // Broad check for connection-related errors
      if (errStr.contains('socketexception') ||
          errStr.contains('connection') ||
          errStr.contains('clientexception') ||
          errStr.contains('handshakeexception') ||
          errStr.contains('network') ||
          errStr.contains('unreachable') ||
          errStr.contains('no address') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('not connected') ||
          errStr.contains('disconnected')) {

        // Offline signup - create a local pending user
        final db = await LocalDatabase.instance.database;
        final tempId = 'temp_${const Uuid().v4()}';

        await db.insert('profiles', {
          'id': tempId,
          'email': email,
          'password_hash': passwordHash,
          'full_name': fullName,
          'role': role,
          'student_id_number': studentId,
          'level': level,
          'status': 'pending_sync',
          'updated_at': now,
          'is_dirty': 1,
          'is_deleted': 0,
        });

        // Store offline email so provider can "log in" the user
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('offline_user_email', email);
        await prefs.setString('user_role_temp', role);
        await prefs.setString('user_name_temp', fullName);
        if (studentId != null) {
          await prefs.setString('user_student_id_number_temp', studentId);
        }
        if (level != null) {
          await prefs.setString('user_level_temp', level);
        }

        throw 'OFFLINE_MODE_RECOVERED';
      }
      rethrow;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('Attempting signin for $email');
      // Tightened timeout to trigger offline fallback faster
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 5));
      debugPrint('Signin successful for ${response.user?.id}');

      // Cache profile and password hash in local DB for offline login
      if (response.user != null) {
        try {
          final db = await LocalDatabase.instance.database;
          final passwordHash = _hashPassword(password);

          // Fetch full profile from cloud to ensure local cache is complete
          final remoteProfile = await _client
              .from('profiles')
              .select()
              .eq('id', response.user!.id)
              .maybeSingle();

          if (remoteProfile != null) {
            final Map<String, dynamic> localData = Map<String, dynamic>.from(remoteProfile);
            localData['password_hash'] = passwordHash;
            localData['is_dirty'] = 0;
            localData['is_deleted'] = 0;

            await db.insert('profiles', localData, conflictAlgorithm: ConflictAlgorithm.replace);
            debugPrint('Cloud profile cached locally for offline use.');

            // Cache in SharedPreferences for instant 0ms startup
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_role_${response.user!.id}', remoteProfile['role']?.toString() ?? 'student');
            await prefs.setString('user_name_${response.user!.id}', remoteProfile['full_name']?.toString() ?? 'User');
            if (remoteProfile['student_id_number'] != null) {
              await prefs.setString('user_student_id_number_${response.user!.id}', remoteProfile['student_id_number'].toString());
            }
            if (remoteProfile['level'] != null) {
              await prefs.setString('user_level_${response.user!.id}', remoteProfile['level'].toString());
            }
          } else {
            // Fallback: just update email and hash if remote profile isn't found yet
            await db.update(
              'profiles',
              {'email': email, 'password_hash': passwordHash},
              where: 'id = ?',
              whereArgs: [response.user!.id]
            );
          }
        } catch (e) {
          debugPrint('Failed to cache profile: $e');
        }
      }

      return response;
    } on AuthException catch (e) {
      debugPrint('Auth error during signin: ${e.message} (Status: ${e.statusCode})');
      rethrow;
    } catch (e) {
      debugPrint('Connection error or other: $e');
      final errStr = e.toString().toLowerCase();
      // Broad check for connection-related errors
      if (errStr.contains('socketexception') ||
          errStr.contains('connection') ||
          errStr.contains('clientexception') ||
          errStr.contains('handshakeexception') ||
          errStr.contains('network') ||
          errStr.contains('unreachable') ||
          errStr.contains('no address') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('not connected') ||
          errStr.contains('disconnected') ||
          errStr.contains('timeout') ||
          errStr.contains('software caused connection abort')) {

        // Try to verify if this user exists in our local cache
        final db = await LocalDatabase.instance.database;
        final passwordHash = _hashPassword(password);

        final localUser = await db.query(
          'profiles',
          where: 'email = ? AND password_hash = ?',
          whereArgs: [email, passwordHash]
        );

        if (localUser.isNotEmpty) {
          // Store the offline email for providers to find the right profile
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('offline_user_email', email);

          final localId = localUser.first['id']?.toString() ?? '';
          if (localId.isNotEmpty) {
            await prefs.setString('user_role_$localId', localUser.first['role']?.toString() ?? 'student');
            await prefs.setString('user_name_$localId', localUser.first['full_name']?.toString() ?? 'User');
            if (localUser.first['student_id_number'] != null) {
              await prefs.setString('user_student_id_number_$localId', localUser.first['student_id_number'].toString());
            }
            if (localUser.first['level'] != null) {
              await prefs.setString('user_level_$localId', localUser.first['level'].toString());
            }
          }

          throw 'OFFLINE_MODE_RECOVERED';
        }

        throw 'Invalid credentials or network error. Please connect to the internet for the first sign-in.';
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    // Pillar 4: Instant Sign-Out
    // 1. Clear SharedPreferences markers
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_user_email');

    // Clear role/name cache
    final user = _client.auth.currentUser;
    if (user != null) {
      await prefs.remove('user_role_${user.id}');
      await prefs.remove('user_name_${user.id}');
    }

    // 2. Clear Auth from Supabase (Local-only operation if offline)
    await _client.auth.signOut();

    // Note: Provider invalidation should be handled at the UI/Service call level
    // to ensure the UI reacts before the navigation stack is wiped.
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

  Future<String?> resetPassword(String email) async {
    try {
      final response = await _client.functions.invoke(
        'send-reset-otp',
        body: {'email': email, 'action': 'send'},
      );
      if (response.status != 200) {
        throw response.data?['error'] ?? 'Failed to send reset code';
      }
      // Return dev_otp if present in response
      return response.data?['dev_otp']?.toString();
    } catch (e) {
      debugPrint('Password reset code request error: $e');
      rethrow;
    }
  }

  Future<void> verifyOtpAndSetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'send-reset-otp',
        body: {
          'email': email,
          'action': 'reset',
          'otp': token,
          'newPassword': newPassword,
        },
      );

      if (response.status != 200) {
        throw response.data?['error'] ?? 'Verification failed';
      }

      // Update local profile with new password hash
      final db = await LocalDatabase.instance.database;
      final bytes = utf8.encode(newPassword);
      final passwordHash = sha256.convert(bytes).toString();

      await db.update(
        'profiles',
        {'password_hash': passwordHash},
        where: 'email = ?',
        whereArgs: [email],
      );

    } catch (e) {
      debugPrint('Code Verification error: $e');
      rethrow;
    }
  }
}
