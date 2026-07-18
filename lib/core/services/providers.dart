import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../services/local_database.dart';
import '../services/sync_service.dart';
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

final userProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final user = ref.watch(currentUserProvider);
  Map<String, dynamic>? lastValue;

  // Use a slightly longer delay for background polling
  const syncInterval = Duration(seconds: 5);

  if (user == null) {
    final db = await ref.read(databaseProvider.future);
    bool isFirstRun = true;

    // Pillar 1 & 2: Immediate Cache Check
    final prefs = await SharedPreferences.getInstance();
    final offlineEmail = prefs.getString('offline_user_email');
    if (offlineEmail != null) {
      final results = await db.query('profiles', where: 'email = ?', whereArgs: [offlineEmail]);
      if (results.isNotEmpty) {
        lastValue = results.first;
        yield lastValue;
      }
    }

    while (true) {
      final currentPrefs = await SharedPreferences.getInstance();
      final currentOfflineEmail = currentPrefs.getString('offline_user_email');

      if (currentOfflineEmail != null) {
        final results = await db.query('profiles', where: 'email = ?', whereArgs: [currentOfflineEmail]);
        final current = results.isNotEmpty ? results.first : null;
        if (!_areMapsEqual(current, lastValue)) {
          lastValue = current;
          yield current;
        }
      } else {
        if (lastValue != null) {
          lastValue = null;
        }
        yield null;
      }
      if (isFirstRun) {
        isFirstRun = false;
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        await Future.delayed(syncInterval);
      }
    }
  }

  final db = await ref.read(databaseProvider.future);
  bool isFirstRun = true;

  // Pillar 2: Immediate Cache yield for authenticated users (with robust fallback)
  try {
    final initialResults = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
    if (initialResults.isNotEmpty) {
      lastValue = initialResults.first;
      yield lastValue;
    } else {
      final metadata = user.userMetadata ?? {};
      final initialProfile = {
        'id': user.id,
        'full_name': metadata['full_name'] ?? metadata['name'] ?? 'User',
        'role': metadata['role'] ?? 'student',
      };
      lastValue = initialProfile;
      yield initialProfile;
    }
  } catch (e) {
    debugPrint('Initial profile query error: $e');
    final metadata = user.userMetadata ?? {};
    final initialProfile = {
      'id': user.id,
      'full_name': metadata['full_name'] ?? metadata['name'] ?? 'User',
      'role': metadata['role'] ?? 'student',
    };
    lastValue = initialProfile;
    yield initialProfile;
  }

  while (true) {
    try {
      final results = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
      if (results.isNotEmpty) {
        final current = results.first;
        if (!_areMapsEqual(current, lastValue)) {
          lastValue = current;
          yield current;
        }
      } else {
        // Only yield metadata-based profile if DB is completely empty for this user
        final metadata = user.userMetadata ?? {};
        final initialProfile = {
          'id': user.id,
          'full_name': metadata['full_name'] ?? metadata['name'] ?? 'User',
          'role': metadata['role'] ?? 'student',
        };
        if (!_areMapsEqual(initialProfile, lastValue)) {
          lastValue = initialProfile;
          yield initialProfile;
        }
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
    }

    if (isFirstRun) {
      isFirstRun = false;
      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      await Future.delayed(syncInterval);
    }
  }
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
