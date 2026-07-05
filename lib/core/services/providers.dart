import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'local_database.dart';
import 'sync_service.dart';

final localDbProvider = Provider<LocalDatabase>((ref) => LocalDatabase.instance);

final databaseProvider = FutureProvider<Database>((ref) async {
  final localDb = ref.watch(localDbProvider);
  return await localDb.database;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService();
});
