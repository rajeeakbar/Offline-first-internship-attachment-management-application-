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

  // 1. Yield from metadata immediately to prevent UI hang
  // Check multiple possible keys for role and name
  final metadata = user.userMetadata ?? {};
  final initialProfile = {
    'id': user.id,
    'full_name': metadata['full_name'] ?? metadata['name'] ?? 'User',
    'role': metadata['role'] ?? 'student',
  };
  yield initialProfile;

  // 2. We want to yield the local profile whenever it changes
  final db = await ref.read(databaseProvider.future);

  // Initial check
  final localResults = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
  if (localResults.isNotEmpty) {
    final Map<String, dynamic> localData = {...initialProfile, ...localResults.first};
    yield localData;
  } else {
    // If not local, fetch remote and yield it
    try {
      final remoteProfile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (remoteProfile != null) {
        // Save to local for next time
        final Map<String, dynamic> data = Map.from(remoteProfile);
        data['is_dirty'] = 0;
        data['is_deleted'] = 0;
        await db.insert('profiles', data, conflictAlgorithm: ConflictAlgorithm.replace);
        final Map<String, dynamic> localData = {...initialProfile, ...data};
        yield localData;
      } else {
        yield null;
      }
    } catch (e) {
      print('Remote profile fetch error: $e');
    }
  }

  // Periodic poll for changes (poor man's stream for SQLite)
  // Reduced frequency to 5s to be more battery efficient.
  Map<String, dynamic>? lastEmitted;

  while (true) {
    try {
      await Future.delayed(const Duration(seconds: 5));
      final results = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
      if (results.isNotEmpty) {
        final Map<String, dynamic> localData = {...initialProfile, ...results.first};

        // Only yield if data actually changed to prevent rebuild loops
        if (lastEmitted == null || _mapChanged(lastEmitted, localData)) {
          lastEmitted = localData;
          yield localData;
        }
      }
    } catch (e) {
      print('Database polling error: $e');
      await Future.delayed(const Duration(seconds: 10));
    }
  }
});

bool _mapChanged(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return true;
  for (final key in a.keys) {
    if (a[key] != b[key]) return true;
  }
  return false;
}
