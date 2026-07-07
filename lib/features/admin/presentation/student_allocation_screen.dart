import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;

    try {
      final studentsRes = await supabase.from('profiles').select().eq('role', 'student');
      final supervisorsRes = await supabase.from('profiles').select().eq('role', 'academic_supervisor');

      setState(() {
        _students = List<Map<String, dynamic>>.from(studentsRes);
        _academicSupervisors = List<Map<String, dynamic>>.from(supervisorsRes);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _assignAcademicSupervisor(String studentId, String? supervisorId) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase.from('profiles').update({'supervisor_id': supervisorId}).eq('id', studentId);
      _loadData();
      ref.read(syncServiceProvider).syncData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Academic Allocation')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadData();
                await ref.read(syncServiceProvider).syncData();
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _students.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final student = _students[index];
                  final currentSupervisorId = student['supervisor_id'];

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: ListTile(
                        title: Text(student['full_name'] ?? 'Unknown Student', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('ID: ${student['student_id_number'] ?? "N/A"}'),
                            const SizedBox(height: 12),
                            const Text('Assign Academic Supervisor:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo)),
                            const SizedBox(height: 4),
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
