import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/local_database.dart';
import '../services/sync_service.dart';
import '../services/network_utility.dart';
import '../../features/auth/data/auth_repository.dart';

final localDbProvider = Provider<LocalDatabase>((ref) => LocalDatabase.instance);

final databaseProvider = FutureProvider<Database>((ref) async {
  final localDb = ref.watch(localDbProvider);
  return await localDb.database;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService();
});

bool _areMapsEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (a == b) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}

bool _areMapListsEqual(List<Map<String, dynamic>>? a, List<Map<String, dynamic>>? b) {
  if (a == b) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (!_areMapsEqual(a[i], b[i])) return false;
  }
  return true;
}

enum AppRouteState { loading, login, authenticated }

final appRouteStateProvider = Provider<AppRouteState>((ref) {
  final authState = ref.watch(authStateProvider);
  final profileAsync = ref.watch(userProfileProvider);

  final hasSession = authState.value?.session != null;
  final profile = profileAsync.valueOrNull;

  // Authenticated state: has a session OR has a local profile (offline fallback)
  if (hasSession || profile != null) {
    return AppRouteState.authenticated;
  }

  // Loading state: auth is loading OR profile is loading AND we don't have a value yet
  if (authState.isLoading || (profileAsync.isLoading && !profileAsync.hasValue)) {
    return AppRouteState.loading;
  }

  // Login state: No session and no profile found after loading
  return AppRouteState.login;
});

final userProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);

  if (user == null) {
    // Check if offline email is stored
    final prefs = await SharedPreferences.getInstance();
    final offlineEmail = prefs.getString('offline_user_email');
    if (offlineEmail != null) {
      try {
        final db = await ref.read(databaseProvider.future);
        final results = await db.query('profiles', where: 'email = ?', whereArgs: [offlineEmail]);
        if (results.isNotEmpty) {
          final profile = results.first;
          await prefs.setString('user_role_${profile['id']}', profile['role']?.toString() ?? 'student');
          await prefs.setString('user_name_${profile['id']}', profile['full_name']?.toString() ?? 'User');
          return profile;
        }
      } catch (e) {
        debugPrint('Failed to query offline profile from SQLite: $e');
      }
    }
    return null;
  }

  // 1️⃣ FIRST: Try to load from local SharedPreferences cache (instant!)
  final prefs = await SharedPreferences.getInstance();
  final cachedRole = prefs.getString('user_role_${user.id}');
  final cachedName = prefs.getString('user_name_${user.id}');

  if (cachedRole != null) {
    debugPrint('✅ Loaded role from cache: $cachedRole');
    return {
      'id': user.id,
      'role': cachedRole,
      'full_name': cachedName ?? 'User',
    };
  }

  // 2️⃣ SECOND: Try local SQLite DB (instant fallback if no prefs cache yet)
  try {
    final db = await ref.read(databaseProvider.future);
    final results = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
    if (results.isNotEmpty) {
      final profile = results.first;
      await prefs.setString('user_role_${user.id}', profile['role']?.toString() ?? 'student');
      await prefs.setString('user_name_${user.id}', profile['full_name']?.toString() ?? 'User');
      return profile;
    }
  } catch (e) {
    debugPrint('Local SQLite profile check failed: $e');
  }

  // 3️⃣ THIRD: If cache/local DB is empty, fetch from Supabase (with timeout, only if online)
  try {
    debugPrint('🔍 No cache or local SQLite row, checking internet connectivity first...');
    final hasInternet = await NetworkUtility.instance.hasInternetAccess();
    if (!hasInternet) {
      debugPrint('🔌 Bypassing Supabase fetch because device is offline.');
      throw Exception('Offline');
    }
    debugPrint('🔍 Fetching from Supabase...');
    final response = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle()
        .timeout(const Duration(seconds: 3)); // ⏱️ 3 seconds max!

    if (response != null) {
      // Save to cache for next time
      await prefs.setString('user_role_${user.id}', response['role'] ?? 'student');
      await prefs.setString('user_name_${user.id}', response['full_name'] ?? '');

      // Also insert into local SQLite DB to keep it in sync
      try {
        final db = await ref.read(databaseProvider.future);
        final Map<String, dynamic> localProfile = Map<String, dynamic>.from(response);
        localProfile['is_dirty'] = 0;
        localProfile['is_deleted'] = 0;
        await db.insert('profiles', localProfile, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (e) {
        debugPrint('Failed to save profile response to SQLite: $e');
      }

      debugPrint('✅ Profile cached successfully.');
      return response;
    }
  } catch (e) {
    debugPrint('Supabase profile fetch failed: $e');
  }

  // 4️⃣ FOURTH: Use auth metadata or default "student" role as fallback
  final metadata = user.userMetadata ?? {};
  final String fallbackRole = metadata['role'] ?? 'student';
  final String fallbackName = metadata['full_name'] ?? metadata['name'] ?? 'User';

  await prefs.setString('user_role_${user.id}', fallbackRole);
  await prefs.setString('user_name_${user.id}', fallbackName);

  return {
    'id': user.id,
    'role': fallbackRole,
    'full_name': fallbackName,
  };
});

final studentLogsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, studentId) async* {
  final db = await ref.read(databaseProvider.future);
  List<Map<String, dynamic>>? lastValue;

  // Pillar 2: Immediate Cache yield
  final initialResults = await db.query(
    'log_entries',
    where: 'student_id = ?',
    whereArgs: [studentId],
    orderBy: 'date DESC',
  );
  lastValue = initialResults;
  yield initialResults;

  while (true) {
    try {
      final results = await db.query(
        'log_entries',
        where: 'student_id = ?',
        whereArgs: [studentId],
        orderBy: 'date DESC',
      );
      if (!_areMapListsEqual(results, lastValue)) {
        lastValue = results;
        yield results;
      }
    } catch (e) {
      debugPrint('Logs query error: $e');
    }
    await Future.delayed(const Duration(seconds: 5));
  }
});

final currentUserLogsProvider = Provider<AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final user = ref.watch(currentUserProvider);
  final profile = ref.watch(userProfileProvider).value;

  final effectiveUserId = user?.id ?? profile?['id'];

  if (effectiveUserId == null) return const AsyncValue.data([]);
  return ref.watch(studentLogsProvider(effectiveUserId));
});

final internshipProgressProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final profile = ref.watch(userProfileProvider).value;

  final effectiveUserId = user?.id ?? profile?['id'];

  if (effectiveUserId == null) {
    yield {'count': 0, 'goal': 60};
    return;
  }

  final db = await ref.read(databaseProvider.future);

  while (true) {
    try {
      // Get goal from settings
      final settings = await db.query('app_settings', where: 'key = ?', whereArgs: ['required_logs']);
      final goal = settings.isNotEmpty ? (int.tryParse(settings.first['value'].toString()) ?? 60) : 60;

      // Get count of approved logs
      final result = await db.rawQuery(
        'SELECT COUNT(*) as total FROM log_entries WHERE student_id = ? AND status = ?',
        [effectiveUserId, 'approved'],
      );
      final count = result.first['total'] as int? ?? 0;

      yield {'count': count, 'goal': goal};
    } catch (e) {
      debugPrint('Progress stream error: $e');
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});

final supervisorStudentsProvider = StreamProvider.family<List<Map<String, dynamic>>, bool>((ref, isAcademic) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    yield [];
    return;
  }

  final db = await ref.read(databaseProvider.future);
  List<Map<String, dynamic>>? lastValue;

  while (true) {
    try {
      final results = await db.query(
        'profiles',
        where: isAcademic ? 'supervisor_id = ?' : 'industry_supervisor_id = ?',
        whereArgs: [user.id],
      );
      if (!_areMapListsEqual(results, lastValue)) {
        lastValue = results;
        yield results;
      }
    } catch (e) {
      debugPrint('Supervisor students query error: $e');
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});
