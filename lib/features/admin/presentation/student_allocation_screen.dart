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

class _StudentAllocationScreenState extends ConsumerState<StudentAllocationScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _academicSupervisors = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  Set<String> _pendingUpdates = {};
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = await LocalDatabase.instance.database;

    try {
      final localStudents = await db.query(
        'profiles',
        where: 'role = ? AND is_deleted = ?',
        whereArgs: ['student', 0],
      );
      _students = List<Map<String, dynamic>>.from(localStudents);

      _pendingUpdates = _students
          .where((s) => (s['is_dirty'] ?? 0) == 1)
          .map((s) => s['id'].toString())
          .toSet();

      final localSupervisors = await db.query(
        'profiles',
        where: 'role = ? AND is_deleted = ?',
        whereArgs: ['academic_supervisor', 0],
      );
      _academicSupervisors = List<Map<String, dynamic>>.from(localSupervisors);

      await _syncWithCloud();

      if (mounted) {
        setState(() => _isLoading = false);
        _animationController.forward();
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Failed to load data. Please try again.');
      }
    }
  }

  Future<void> _syncWithCloud() async {
    try {
      final supabase = Supabase.instance.client;
      final db = await LocalDatabase.instance.database;

      final studentsRes = await supabase.from('profiles').select().eq('role', 'student');
      final supervisorsRes = await supabase.from('profiles').select().eq('role', 'academic_supervisor');

      // Batch operations for better performance
      final batch = db.batch();

      for (var cloudStudent in studentsRes) {
        final existingLocal = await db.query('profiles', where: 'id = ?', whereArgs: [cloudStudent['id']]);
        if (existingLocal.isNotEmpty) {
          final local = existingLocal.first;
          if ((local['is_dirty'] ?? 0) == 1 || (local['is_deleted'] ?? 0) == 1) {
            continue;
          }
        }
        batch.insert('profiles', {
          ...cloudStudent,
          'is_dirty': 0,
          'is_deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (var cloudSup in supervisorsRes) {
        final existingLocal = await db.query('profiles', where: 'id = ?', whereArgs: [cloudSup['id']]);
        if (existingLocal.isNotEmpty) {
          final local = existingLocal.first;
          if ((local['is_dirty'] ?? 0) == 1 || (local['is_deleted'] ?? 0) == 1) {
            continue;
          }
        }
        batch.insert('profiles', {
          ...cloudSup,
          'is_dirty': 0,
          'is_deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);

      // Reload data
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
      debugPrint('⚠️ Cloud sync failed – using local data: $e');
    }
  }

  Future<void> _assignAcademicSupervisor(String studentId, String? supervisorId) async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    final db = await LocalDatabase.instance.database;

    try {
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

      setState(() {
        final index = _students.indexWhere((s) => s['id'] == studentId);
        if (index != -1) {
          final updated = Map<String, dynamic>.from(_students[index]);
          updated['supervisor_id'] = supervisorId;
          updated['is_dirty'] = 1;
          _students[index] = updated;
        }
        _pendingUpdates.add(studentId);
      });

      ref.read(syncServiceProvider).syncData();

      _showSuccessSnackBar('✅ Assignment saved locally. Will sync when online.');
    } catch (e) {
      _showErrorSnackBar('Failed to assign supervisor. Please try again.');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _approveStudent(String studentId) async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    try {
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

      setState(() {
        final index = _students.indexWhere((s) => s['id'] == studentId);
        if (index != -1) {
          final updated = Map<String, dynamic>.from(_students[index]);
          updated['status'] = 'approved';
          updated['is_dirty'] = 1;
          _students[index] = updated;
        }
        _pendingUpdates.add(studentId);
      });

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
      _showSuccessSnackBar('✅ Student approved successfully! Access granted.');
    } catch (e) {
      _showErrorSnackBar('Failed to approve student. Please try again.');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          await _loadData();
          await ref.read(syncServiceProvider).syncData();
        },
        child: _students.isEmpty
            ? _buildEmptyState()
            : _buildStudentList(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      title: const Text(
        'Academic Allocation',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      actions: [
        if (_isSyncing)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.sync),
          onPressed: _isSyncing ? null : _performSync,
          tooltip: 'Sync Data',
        ),
      ],
    );
  }

  void _performSync() async {
    setState(() => _isSyncing = true);
    try {
      await _syncWithCloud();
      await ref.read(syncServiceProvider).syncData();
      if (mounted) {
        _showSuccessSnackBar('✅ Data synced successfully!');
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to sync. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No Students Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Students will appear here once they register.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _students.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final student = _students[index];
          final currentSupervisorId = student['supervisor_id'];
          final isPending = _pendingUpdates.contains(student['id']);
          final String status = student['status']?.toString().toLowerCase() ?? 'pending';
          final bool needsApproval = status != 'approved';

          return _StudentCard(
            key: ValueKey(student['id']),
            student: student,
            currentSupervisorId: currentSupervisorId,
            isPending: isPending,
            needsApproval: needsApproval,
            isSyncing: _isSyncing,
            academicSupervisors: _academicSupervisors,
            onApprove: () => _approveStudent(student['id']),
            onAssign: (val) => _assignAcademicSupervisor(student['id'], val),
          );
        },
      ),
    );
  }
}

// Premium Student Card Widget
class _StudentCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final String? currentSupervisorId;
  final bool isPending;
  final bool needsApproval;
  final bool isSyncing;
  final List<Map<String, dynamic>> academicSupervisors;
  final VoidCallback onApprove;
  final ValueChanged<String?> onAssign;

  const _StudentCard({
    super.key,
    required this.student,
    required this.currentSupervisorId,
    required this.isPending,
    required this.needsApproval,
    required this.isSyncing,
    required this.academicSupervisors,
    required this.onApprove,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showStudentDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Section
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                student['full_name'] ?? 'Unknown Student',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isPending)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Tooltip(
                                  message: 'Pending sync',
                                  child: Icon(
                                    Icons.sync_problem,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'ID: ${student['student_id_number'] ?? "N/A"}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Status Badge
              if (needsApproval) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade50, Colors.red.shade100],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Needs Admin Approval',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Divider
              Divider(height: 1, color: Colors.grey.shade200),

              const SizedBox(height: 16),

              // Actions Section
              LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 16,
                            color: Colors.indigo.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Supervisor:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ],
                      ),
                      if (needsApproval)
                        _buildApproveButton(),
                      _buildSupervisorDropdown(),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade400, Colors.indigo.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          student['full_name']?.isNotEmpty == true
              ? student['full_name'][0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildApproveButton() {
    return ElevatedButton.icon(
      onPressed: isSyncing ? null : onApprove,
      icon: const Icon(Icons.check_circle_outline, size: 16),
      label: const Text(
        'Approve',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: const Size(80, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildSupervisorDropdown() {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 200,
        minWidth: 120,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: DropdownButton<String>(
          underline: const SizedBox(),
          hint: const Text(
            'Select Staff',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13),
          ),
          value: currentSupervisorId,
          isExpanded: true,
          isDense: true,
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('None', style: TextStyle(fontSize: 13)),
            ),
            ...academicSupervisors.map((s) => DropdownMenuItem(
              value: s['id'] as String,
              child: Text(
                s['full_name'] ?? 'Staff',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            )),
          ],
          onChanged: isSyncing ? null : onAssign,
          elevation: 8,
          icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  void _showStudentDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              student['full_name'] ?? 'Unknown Student',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildDetailRow('Student ID', student['student_id_number'] ?? 'N/A'),
            _buildDetailRow('Status', student['status'] ?? 'Pending'),
            _buildDetailRow('Supervisor',
                academicSupervisors.firstWhere(
                      (s) => s['id'] == student['supervisor_id'],
                  orElse: () => {'full_name': 'Not Assigned'},
                )['full_name'] ?? 'Not Assigned'
            ),
            if (student['level'] != null)
              _buildDetailRow('Level', student['level']),
            if (student['email'] != null)
              _buildDetailRow('Email', student['email']),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}