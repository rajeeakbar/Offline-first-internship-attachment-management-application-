import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'local_database.dart';
import 'network_utility.dart';

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

    // Check active internet capability before starting to avoid unnecessary work/failures
    final hasInternet = await NetworkUtility.instance.hasInternetAccess();
    if (!hasInternet) {
      debugPrint('Sync skipped: No active internet capability detected.');
      return;
    }

    _isSyncing = true;
    try {
      final db = await _localDb.database;

      // Sync order: Profiles -> Log Entries -> Media
      // We also sync other tables to ensure full functional integration
      await _syncTable(db, 'profiles', 'profiles');
      await _syncTable(db, 'companies', 'companies');
      await _syncTable(db, 'app_settings', 'app_settings');
      await _syncTable(db, 'log_entries', 'log_entries');
      await _syncMedia(db);
    } catch (e) {
      debugPrint('Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncTable(Database db, String localTable, String remoteTable) async {
    // 1. Push local changes to Cloud
    final dirtyRecords = await db.query(localTable, where: 'is_dirty = ?', whereArgs: [1]);

    final List<String> successfullySyncedIds = [];
    final List<String> successfullyDeletedIds = [];

    for (var record in dirtyRecords) {
      try {
        final Map<String, dynamic> data = Map.from(record);
        final String id = data['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        data.remove('is_dirty');

        final bool isDeleted = (data['is_deleted']?.toString() == '1');
        data.remove('is_deleted');
        data.remove('local_path');

        if (isDeleted) {
          await _supabase.from(remoteTable).delete().eq('id', id);
          successfullyDeletedIds.add(id);
        } else {
          if (remoteTable == 'profiles') {
            data.remove('email');
            data.remove('password_hash');
          }
          await _supabase.from(remoteTable).upsert(data);
          successfullySyncedIds.add(id);
        }
      } catch (e) {
        debugPrint('Failed to push record from $localTable: $e');
      }
    }

    // Run batch SQLite transaction to finalize pushed records
    if (successfullySyncedIds.isNotEmpty || successfullyDeletedIds.isNotEmpty) {
      await db.transaction((txn) async {
        for (var id in successfullySyncedIds) {
          await txn.update(localTable, {'is_dirty': 0}, where: 'id = ?', whereArgs: [id]);
        }
        for (var id in successfullyDeletedIds) {
          await txn.delete(localTable, where: 'id = ?', whereArgs: [id]);
        }
      });
    }

    // 2. Pull changes from Cloud (Incremental)
    final lastSyncResult = await db.rawQuery('SELECT MAX(updated_at) as last_sync FROM $localTable');
    final String? lastSync = lastSyncResult.first['last_sync']?.toString();

    var query = _supabase.from(remoteTable).select();
    if (lastSync != null && lastSync.isNotEmpty && lastSync != 'null') {
      query = query.gt('updated_at', lastSync);
    }

    final remoteRecords = await query;

    if (remoteRecords.isNotEmpty) {
      await db.transaction((txn) async {
        for (var remoteRecord in remoteRecords) {
          try {
            final Map<String, dynamic> remoteData = Map<String, dynamic>.from(remoteRecord as Map);
            final String id = remoteData['id']?.toString() ?? '';

            if (id.isNotEmpty) {
              // Check if there is a local record with is_dirty = 1 (meaning offline wins)
              final localRecord = await txn.query(localTable, where: 'id = ?', whereArgs: [id]);
              if (localRecord.isNotEmpty) {
                final int isDirty = int.tryParse(localRecord.first['is_dirty']?.toString() ?? '0') ?? 0;
                if (isDirty == 1) {
                  // Local record has unsynced offline changes: offline wins, skip overwriting
                  debugPrint('Offline Wins: Skip overwriting unsynced local record $id in $localTable with cloud data');
                  continue;
                }
              }
            }

            remoteData['is_dirty'] = 0;
            remoteData['is_deleted'] = remoteData['is_deleted'] ?? 0;

            if (localTable == 'profiles' && id.isNotEmpty) {
              final existingLocal = await txn.query(localTable, where: 'id = ?', whereArgs: [id]);
              if (existingLocal.isNotEmpty) {
                remoteData['email'] = existingLocal.first['email'];
                remoteData['password_hash'] = existingLocal.first['password_hash'];
              }
            }

            await txn.insert(
              localTable,
              remoteData,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            // Dynamically update SharedPreferences cache to prevent dashboard UI latency
            if (localTable == 'profiles' && id.isNotEmpty) {
              final prefs = await SharedPreferences.getInstance();
              final role = remoteData['role']?.toString();
              if (role != null) {
                await prefs.setString('user_role_$id', role);
              }
              final fullName = remoteData['full_name']?.toString();
              if (fullName != null) {
                await prefs.setString('user_name_$id', fullName);
              }
              final status = remoteData['status']?.toString();
              if (status != null) {
                await prefs.setString('user_status_$id', status);
              }
              final supervisorId = remoteData['supervisor_id']?.toString();
              if (supervisorId != null) {
                await prefs.setString('user_supervisor_id_$id', supervisorId);
              } else {
                await prefs.remove('user_supervisor_id_$id');
              }
              final indSupervisorId = remoteData['industry_supervisor_id']?.toString();
              if (indSupervisorId != null) {
                await prefs.setString('user_industry_supervisor_id_$id', indSupervisorId);
              } else {
                await prefs.remove('user_industry_supervisor_id_$id');
              }
              final level = remoteData['level']?.toString();
              if (level != null) {
                await prefs.setString('user_level_$id', level);
              } else {
                await prefs.remove('user_level_$id');
              }
              final studentId = remoteData['student_id_number']?.toString();
              if (studentId != null) {
                await prefs.setString('user_student_id_number_$id', studentId);
              } else {
                await prefs.remove('user_student_id_number_$id');
              }
            }
          } catch (e) {
            debugPrint('Failed to pull record to $localTable in transaction: $e');
          }
        }
      });
    }
  }

  Future<void> _syncMedia(Database db) async {
    try {
      final dirtyMedia = await db.query('media_attachments', where: 'is_dirty = ?', whereArgs: [1]);

      for (var media in dirtyMedia) {
        try {
          // Robust, null-safe type casting and conversion with default fallbacks to prevent runtime crashes
          final String id = media['id']?.toString() ?? '';
          final String localPath = media['local_path']?.toString() ?? '';
          final String logId = media['log_id']?.toString() ?? '';

          if (id.isEmpty) continue;

          if (media['is_deleted']?.toString() == '1') {
            await db.delete('media_attachments', where: 'id = ?', whereArgs: [id]);
            continue;
          }

          if (media['remote_url'] == null && localPath.isNotEmpty) {
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
              remoteMedia.remove('is_deleted');
              remoteMedia.remove('local_path'); // Local path not needed in cloud
              await _supabase.from('media_attachments').upsert(remoteMedia);
            }
          }
        } catch (e) {
          debugPrint('Error syncing individual media item: $e');
        }
      }
    } catch (e) {
      debugPrint('Error querying or syncing media_attachments: $e');
    }
  }
}
