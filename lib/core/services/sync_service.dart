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

  Future<void> syncData({int retryCount = 0}) async {
    if (_isSyncing) return;
    _isSyncing = true;

    print('Starting synchronization cycle (Retry: $retryCount)...');

    try {
      final db = await _localDb.database;

      // Sync order: Profiles -> Companies -> Log Entries -> Media
      // We pull first then push to maintain "Cloud wins" strategy
      await _syncTable(db, 'profiles', 'profiles');
      await _syncTable(db, 'companies', 'companies');

      // Prioritize current user profile sync to local DB
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _pullSpecificProfile(db, user.id);
      }

      await _syncTable(db, 'log_entries', 'log_entries');
      await _syncMedia(db);

      print('Synchronization cycle completed successfully.');
    } catch (e) {
      print('Sync failed: $e');
      if (retryCount < 3) {
        final nextRetry = retryCount + 1;
        print('Retrying sync in ${nextRetry * 2} seconds...');
        Future.delayed(Duration(seconds: nextRetry * 2), () => syncData(retryCount: nextRetry));
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pullSpecificProfile(Database db, String userId) async {
    try {
      final remoteRecord = await _supabase.from('profiles').select().eq('id', userId).maybeSingle();
      if (remoteRecord != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(remoteRecord);
        data['is_dirty'] = 0;
        data['is_deleted'] = 0;
        await db.insert('profiles', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } catch (e) {
      print('Failed to pull specific profile: $e');
    }
  }

  Future<void> _syncTable(Database db, String localTable, String remoteTable) async {
    try {
      // 1. Pull changes from Cloud (Incremental)
      final lastSyncResult = await db.rawQuery('SELECT MAX(updated_at) as last_sync FROM $localTable');
      final String? lastSync = lastSyncResult.first['last_sync']?.toString();

      var query = _supabase.from(remoteTable).select();
      if (lastSync != null && lastSync.isNotEmpty && lastSync != 'null') {
        query = query.gt('updated_at', lastSync);
      }

      final List<dynamic> remoteRecords = await query;

      for (var remoteRecord in remoteRecords) {
        try {
          final Map<String, dynamic> remoteData = Map<String, dynamic>.from(remoteRecord);
          final String id = remoteData['id'].toString();

          // Check for local version to perform conflict resolution/merging
          final localResult = await db.query(localTable, where: 'id = ?', whereArgs: [id]);

          if (localResult.isNotEmpty) {
            final Map<String, dynamic> localData = Map<String, dynamic>.from(localResult.first);
            final bool isLocalDirty = localData['is_dirty'] == 1;

            if (isLocalDirty) {
              // Conflict resolution: Latest updated_at wins, but merge fields
              final DateTime localUpdated = DateTime.parse(localData['updated_at'].toString());
              final DateTime remoteUpdated = DateTime.parse(remoteData['updated_at'].toString());

              if (remoteUpdated.isAfter(localUpdated)) {
                // Cloud is newer: Merge remote into local, but keep local-only fields
                final Map<String, dynamic> mergedData = {...localData, ...remoteData};
                mergedData['is_dirty'] = 0; // Cloud version accepted
                mergedData['is_deleted'] = remoteData['is_deleted'] ?? 0;
                await db.update(localTable, mergedData, where: 'id = ?', whereArgs: [id]);
              } else {
                // Local is newer or equal: Keep local dirty, will push later
                print('Local version of $id is newer or equal. Keeping local changes.');
              }
            } else {
              // Local is not dirty: Safe to overwrite with remote data
              final Map<String, dynamic> data = {...remoteData};
              data['is_dirty'] = 0;
              data['is_deleted'] = remoteData['is_deleted'] ?? 0;
              await db.update(localTable, data, where: 'id = ?', whereArgs: [id]);
            }
          } else {
            // New record from remote
            final Map<String, dynamic> data = {...remoteData};
            data['is_dirty'] = 0;
            data['is_deleted'] = remoteData['is_deleted'] ?? 0;
            await db.insert(localTable, data);
          }
        } catch (e) {
          print('Failed to pull record to $localTable: $e');
        }
      }

      // 2. Push local changes to Cloud
      final dirtyRecords = await db.query(localTable, where: 'is_dirty = ?', whereArgs: [1]);

      for (var record in dirtyRecords) {
        try {
          final Map<String, dynamic> data = Map<String, dynamic>.from(record);
          final String id = data['id'].toString();

          // Prepare data for Supabase (remove local-only columns)
          final Map<String, dynamic> pushData = Map.from(data);
          pushData.remove('is_dirty');
          final bool isDeleted = pushData['is_deleted'] == 1;
          pushData.remove('is_deleted');

          // Remove other potential local-only fields if any (e.g., local_path in media)
          pushData.remove('local_path');

          if (isDeleted) {
            await _supabase.from(remoteTable).delete().eq('id', id);
            await db.delete(localTable, where: 'id = ?', whereArgs: [id]);
          } else {
            await _supabase.from(remoteTable).upsert(pushData);
            await db.update(localTable, {'is_dirty': 0}, where: 'id = ?', whereArgs: [id]);
          }
        } catch (e) {
          print('Failed to push record from $localTable: $e');
        }
      }
    } catch (e) {
      print('Error in _syncTable ($localTable): $e');
    }
  }

  Future<void> _syncMedia(Database db) async {
    try {
      final dirtyMedia = await db.query('media_attachments', where: 'is_dirty = ?', whereArgs: [1]);

      for (var media in dirtyMedia) {
        try {
          final String id = media['id'].toString();
          final String localPath = media['local_path'].toString();
          final String logId = media['log_id'].toString();

          if (media['is_deleted'] == 1) {
            await db.delete('media_attachments', where: 'id = ?', whereArgs: [id]);
            continue;
          }

          if (media['remote_url'] == null) {
            final file = File(localPath);
            if (await file.exists()) {
              final fileName = '$logId/${id.split('-').last}';

              try {
                await _supabase.storage.from('logs').upload(
                  fileName,
                  file,
                  fileOptions: const FileOptions(upsert: true)
                );

                final String publicUrl = _supabase.storage.from('logs').getPublicUrl(fileName);

                await db.update('media_attachments', {
                  'remote_url': publicUrl,
                  'is_dirty': 0,
                }, where: 'id = ?', whereArgs: [id]);

                final Map<String, dynamic> remoteMedia = Map<String, dynamic>.from(media);
                remoteMedia['remote_url'] = publicUrl;
                remoteMedia.remove('is_dirty');
                remoteMedia.remove('is_deleted');
                remoteMedia.remove('local_path');
                await _supabase.from('media_attachments').upsert(remoteMedia);
              } catch (uploadError) {
                print('Failed to upload media file $id: $uploadError');
              }
            } else {
              print('Local file missing for media attachment: $localPath');
            }
          }
        } catch (e) {
          print('Error syncing individual media item: $e');
        }
      }
    } catch (e) {
      print('Error in _syncMedia: $e');
    }
  }
}
