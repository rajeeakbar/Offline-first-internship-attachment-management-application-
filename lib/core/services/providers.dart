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

Future<void> _cacheProfileInPrefs(SharedPreferences prefs, String userId, Map<String, dynamic> profile) async {
  if (userId.isEmpty) return;
  await prefs.setString('user_role_$userId', profile['role']?.toString() ?? 'student');
  await prefs.setString('user_name_$userId', profile['full_name']?.toString() ?? 'User');

  final status = profile['status']?.toString();
  if (status != null) {
    await prefs.setString('user_status_$userId', status);
  } else {
    await prefs.remove('user_status_$userId');
  }

  final supervisorId = profile['supervisor_id']?.toString();
  if (supervisorId != null) {
    await prefs.setString('user_supervisor_id_$userId', supervisorId);
  } else {
    await prefs.remove('user_supervisor_id_$userId');
  }

  final indSupervisorId = profile['industry_supervisor_id']?.toString();
  if (indSupervisorId != null) {
    await prefs.setString('user_industry_supervisor_id_$userId', indSupervisorId);
  } else {
    await prefs.remove('user_industry_supervisor_id_$userId');
  }

  final level = profile['level']?.toString();
  if (level != null) {
    await prefs.setString('user_level_$userId', level);
  } else {
    await prefs.remove('user_level_$userId');
  }

  final studentId = profile['student_id_number']?.toString();
  if (studentId != null) {
    await prefs.setString('user_student_id_number_$userId', studentId);
  } else {
    await prefs.remove('user_student_id_number_$userId');
  }

  final companyName = profile['company_name']?.toString();
  if (companyName != null) {
    await prefs.setString('user_company_name_$userId', companyName);
  } else {
    await prefs.remove('user_company_name_$userId');
  }

  final department = profile['department']?.toString();
  if (department != null) {
    await prefs.setString('user_department_$userId', department);
  } else {
    await prefs.remove('user_department_$userId');
  }
}

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
          await _cacheProfileInPrefs(prefs, profile['id']?.toString() ?? '', profile);
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
    debugPrint('✅ Loaded profile from cache for ${user.id}');
    final cachedStatus = prefs.getString('user_status_${user.id}');
    final cachedSupervisorId = prefs.getString('user_supervisor_id_${user.id}');
    final cachedIndustrySupervisorId = prefs.getString('user_industry_supervisor_id_${user.id}');
    final cachedLevel = prefs.getString('user_level_${user.id}');
    final cachedStudentIdNumber = prefs.getString('user_student_id_number_${user.id}');
    final cachedCompanyName = prefs.getString('user_company_name_${user.id}');
    final cachedDepartment = prefs.getString('user_department_${user.id}');

    return {
      'id': user.id,
      'role': cachedRole,
      'full_name': cachedName ?? 'User',
      'status': cachedStatus,
      'supervisor_id': cachedSupervisorId,
      'industry_supervisor_id': cachedIndustrySupervisorId,
      'level': cachedLevel,
      'student_id_number': cachedStudentIdNumber,
      'company_name': cachedCompanyName,
      'department': cachedDepartment,
    };
  }

  // 2️⃣ SECOND: Try local SQLite DB (instant fallback if no prefs cache yet)
  try {
    final db = await ref.read(databaseProvider.future);
    final results = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
    if (results.isNotEmpty) {
      final profile = results.first;
      await _cacheProfileInPrefs(prefs, user.id, profile);
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
      await _cacheProfileInPrefs(prefs, user.id, response);

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
