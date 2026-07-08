import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

final userProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    yield null;
    return;
  }

  final metadata = user.userMetadata ?? {};
  final initialProfile = {
    'id': user.id,
    'full_name': metadata['full_name'] ?? metadata['name'] ?? 'User',
    'role': metadata['role'] ?? 'student',
  };
  yield initialProfile;

  final db = await ref.read(databaseProvider.future);

  while (true) {
    try {
      final results = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
      if (results.isNotEmpty) {
        yield {...initialProfile, ...results.first};
      }
    } catch (e) {
      print('Database polling error: $e');
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});

final studentLogsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, studentId) async* {
  final db = await ref.read(databaseProvider.future);

  while (true) {
    try {
      final results = await db.query(
        'log_entries',
        where: 'student_id = ?',
        whereArgs: [studentId],
        orderBy: 'date DESC',
      );
      yield results;
    } catch (e) {
      print('Logs query error: $e');
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});

final currentUserLogsProvider = Provider<AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const AsyncValue.data([]);
  return ref.watch(studentLogsProvider(user.id));
});

final internshipProgressProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
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
        [user.id, 'approved'],
      );
      final count = result.first['total'] as int? ?? 0;

      yield {'count': count, 'goal': goal};
    } catch (e) {
      print('Progress stream error: $e');
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

  while (true) {
    try {
      final results = await db.query(
        'profiles',
        where: isAcademic ? 'supervisor_id = ?' : 'industry_supervisor_id = ?',
        whereArgs: [user.id],
      );
      yield results;
    } catch (e) {
      print('Supervisor students query error: $e');
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});

bool _mapChanged(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return true;
  for (final key in a.keys) {
    if (a[key] != b[key]) return true;
  }
  return false;
}
