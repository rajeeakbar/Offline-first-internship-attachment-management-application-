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

      // Merge cloud data into local DB (respect offline wins: skip if local is dirty)
      for (var cloudStudent in studentsRes) {
        final local = _students.firstWhere(
          (s) => s['id'] == cloudStudent['id'],
          orElse: () => {},
        );
        if (local.isNotEmpty && (local['is_dirty'] ?? 0) == 1) {
          // Local is dirty – offline wins: keep local, don't overwrite
          continue;
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

  Future<void> _approveStudent(String studentId) async {
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    // 1. Update local DB with status approved and marked dirty
    await db.update(
      'profiles',
      {
        'status': 'approved',
        'is_dirty': 1,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [studentId],
    );

    // 2. Update local state instantly
    setState(() {
      final index = _students.indexWhere((s) => s['id'] == studentId);
      if (index != -1) {
        final Map<String, dynamic> updated = Map<String, dynamic>.from(_students[index]);
        updated['status'] = 'approved';
        updated['is_dirty'] = 1;
        _students[index] = updated;
      }
      _pendingUpdates.add(studentId);
    });

    // 3. Trigger remote update & sync
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'status': 'approved',
            'updated_at': now,
          })
          .eq('id', studentId);
    } catch (e) {
      debugPrint('Remote approval error: $e');
    }

    ref.read(syncServiceProvider).syncData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Student approved successfully! Access granted.'),
          backgroundColor: Colors.green,
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
                        final String status = student['status']?.toString().toLowerCase() ?? 'pending';
                        final bool needsApproval = status != 'approved';

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
                                  if (needsApproval) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 13),
                                          SizedBox(width: 4),
                                          Text(
                                            'Needs Admin Approval to Access Logbook',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Assign Academic Supervisor:',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (needsApproval) ...[
                                    ElevatedButton(
                                      onPressed: () => _approveStudent(student['id']),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text(
                                        'Approve',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  DropdownButton<String>(
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
                                ],
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
