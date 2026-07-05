import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'local_database.dart';

class SyncService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalDatabase _localDb = LocalDatabase.instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  void startAutoSync() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        syncData();
      }
    });
    // Initial sync
    syncData();
  }

  void stopAutoSync() {
    _connectivitySubscription?.cancel();
  }

  Future<void> syncData() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final db = await _localDb.database;

      // Sync order: Profiles -> Log Entries -> Media
      await _syncTable(db, 'profiles', 'profiles');
      await _syncTable(db, 'log_entries', 'log_entries');
      await _syncMedia(db);
    } catch (e) {
      print('Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncTable(Database db, String localTable, String remoteTable) async {
    // 1. Push local changes to Cloud
    final dirtyRecords = await db.query(localTable, where: 'is_dirty = ?', whereArgs: [1]);

    for (var record in dirtyRecords) {
      try {
        final Map<String, dynamic> data = Map.from(record);
        final String id = data['id'] as String;

        data.remove('is_dirty');

        if (data['is_deleted'] == 1) {
          await _supabase.from(remoteTable).delete().eq('id', id);
          await db.delete(localTable, where: 'id = ?', whereArgs: [id]);
        } else {
          await _supabase.from(remoteTable).upsert(data);
          await db.update(localTable, {'is_dirty': 0}, where: 'id = ?', whereArgs: [id]);
        }
      } catch (e) {
        print('Failed to push record from $localTable: $e');
      }
    }

    // 2. Pull changes from Cloud (Incremental)
    final lastSyncResult = await db.rawQuery('SELECT MAX(updated_at) as last_sync FROM $localTable');
    final String? lastSync = lastSyncResult.first['last_sync'] as String?;

    var query = _supabase.from(remoteTable).select();
    if (lastSync != null) {
      query = query.gt('updated_at', lastSync);
    }

    final remoteRecords = await query;

    for (var remoteRecord in remoteRecords) {
      try {
        remoteRecord['is_dirty'] = 0;
        remoteRecord['is_deleted'] = 0;

        await db.insert(
          localTable,
          remoteRecord,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        print('Failed to pull record to $localTable: $e');
      }
    }
  }

  Future<void> _syncMedia(Database db) async {
    final dirtyMedia = await db.query('media_attachments', where: 'is_dirty = ?', whereArgs: [1]);

    for (var media in dirtyMedia) {
      try {
        final String id = media['id'] as String;
        final String localPath = media['local_path'] as String;
        final String logId = media['log_id'] as String;

        if (media['is_deleted'] == 1) {
          await db.delete('media_attachments', where: 'id = ?', whereArgs: [id]);
          continue;
        }

        if (media['remote_url'] == null) {
          final file = File(localPath);
          if (await file.exists()) {
            final fileName = '$logId/${id.split('-').last}';
            await _supabase.storage.from('logs').upload(fileName, file);

            final String publicUrl = _supabase.storage.from('logs').getPublicUrl(fileName);

            await db.update('media_attachments', {
              'remote_url': publicUrl,
              'is_dirty': 0,
            }, where: 'id = ?', whereArgs: [id]);

            final Map<String, dynamic> remoteMedia = Map.from(media);
            remoteMedia['remote_url'] = publicUrl;
            remoteMedia.remove('is_dirty');
            remoteMedia.remove('local_path'); // Local path not needed in cloud
            await _supabase.from('media_attachments').upsert(remoteMedia);
          }
        }
      } catch (e) {
        print('Error syncing media: $e');
      }
    }
  }
}
