import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';

class StudentAllocationScreen extends ConsumerStatefulWidget {
  const StudentAllocationScreen({super.key});

  @override
  ConsumerState<StudentAllocationScreen> createState() => _StudentAllocationScreenState();
}

class _StudentAllocationScreenState extends ConsumerState<StudentAllocationScreen> {
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _academicSupervisors = [];
  bool _isLoading = true;
  Set<String> _pendingUpdates = {}; // Track student IDs that are dirty

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = await LocalDatabase.instance.database;

    // 1️⃣ Load students from local DB (offline-first)
    final localStudents = await db.query(
      'profiles',
      where: 'role = ? AND is_deleted = ?',
      whereArgs: ['student', 0],
    );
    _students = List<Map<String, dynamic>>.from(localStudents);

    // Mark which students have pending sync (is_dirty = 1)
    _pendingUpdates = _students
        .where((s) => (s['is_dirty'] ?? 0) == 1)
        .map((s) => s['id'].toString())
        .toSet();

    // 2️⃣ Load academic supervisors from local DB
    final localSupervisors = await db.query(
      'profiles',
      where: 'role = ? AND is_deleted = ?',
      whereArgs: ['academic_supervisor', 0],
    );
    _academicSupervisors = List<Map<String, dynamic>>.from(localSupervisors);

    // 3️⃣ If online, refresh from cloud (but only if we have internet)
    try {
      final supabase = Supabase.instance.client;
      final studentsRes = await supabase.from('profiles').select().eq('role', 'student');
      final supervisorsRes = await supabase.from('profiles').select().eq('role', 'academic_supervisor');

      // Merge cloud data into local DB (respect offline wins: skip if local is dirty or deleted)
      for (var cloudStudent in studentsRes) {
        final existingLocal = await db.query('profiles', where: 'id = ?', whereArgs: [cloudStudent['id']]);
        if (existingLocal.isNotEmpty) {
          final local = existingLocal.first;
          if ((local['is_dirty'] ?? 0) == 1 || (local['is_deleted'] ?? 0) == 1) {
            // Local is dirty or deleted – offline wins: keep local, don't overwrite
            continue;
          }
        }
        // Update local DB with cloud data
        await db.insert('profiles', {
          ...cloudStudent,
          'is_dirty': 0,
          'is_deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Also update supervisors similarly
      for (var cloudSup in supervisorsRes) {
        final existingLocal = await db.query('profiles', where: 'id = ?', whereArgs: [cloudSup['id']]);
        if (existingLocal.isNotEmpty) {
          final local = existingLocal.first;
          if ((local['is_dirty'] ?? 0) == 1 || (local['is_deleted'] ?? 0) == 1) {
            continue;
          }
        }
        await db.insert('profiles', {
          ...cloudSup,
          'is_dirty': 0,
          'is_deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Reload local DB after merge
      final refreshedStudents = await db.query(
        'profiles',
        where: 'role = ? AND is_deleted = ?',
        whereArgs: ['student', 0],
      );
      _students = List<Map<String, dynamic>>.from(refreshedStudents);
      _pendingUpdates = _students
          .where((s) => (s['is_dirty'] ?? 0) == 1)
          .map((s) => s['id'].toString())
          .toSet();

      final refreshedSupervisors = await db.query(
        'profiles',
        where: 'role = ? AND is_deleted = ?',
        whereArgs: ['academic_supervisor', 0],
      );
      _academicSupervisors = List<Map<String, dynamic>>.from(refreshedSupervisors);

    } catch (e) {
      debugPrint('⚠️ Could not refresh from cloud – using local data only: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _assignAcademicSupervisor(String studentId, String? supervisorId) async {
    final db = await LocalDatabase.instance.database;

    // ✅ 1. Update local DB with is_dirty = 1 (offline-first)
    await db.update(
      'profiles',
      {
        'supervisor_id': supervisorId,
        'is_dirty': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [studentId],
    );

    // 2. Update local state instantly
    setState(() {
      final index = _students.indexWhere((s) => s['id'] == studentId);
      if (index != -1) {
        final Map<String, dynamic> updated = Map<String, dynamic>.from(_students[index]);
        updated['supervisor_id'] = supervisorId;
        updated['is_dirty'] = 1;
        _students[index] = updated;
      }
      _pendingUpdates.add(studentId);
    });

    // 3. Trigger background sync (will push when online)
    ref.read(syncServiceProvider).syncData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Assignment saved locally. Will sync when online.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Academic Allocation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              ref.read(syncServiceProvider).syncData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing...')),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadData();
                await ref.read(syncServiceProvider).syncData();
              },
              child: _students.isEmpty
                  ? const Center(child: Text('No students found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _students.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final student = _students[index];
                        final currentSupervisorId = student['supervisor_id'];
                        final isPending = _pendingUpdates.contains(student['id']);

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: ListTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      student['full_name'] ?? 'Unknown Student',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (isPending)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Icon(Icons.sync_problem, color: Colors.orange, size: 18),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ID: ${student['student_id_number'] ?? "N/A"}'),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Assign Academic Supervisor:',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: DropdownButton<String>(
                                underline: const SizedBox(),
                                hint: const Text('Select Staff'),
                                value: currentSupervisorId,
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('None')),
                                  ..._academicSupervisors.map((s) => DropdownMenuItem(
                                        value: s['id'] as String,
                                        child: Text(s['full_name'] ?? 'Staff'),
                                      )),
                                ],
                                onChanged: (val) => _assignAcademicSupervisor(student['id'], val),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
