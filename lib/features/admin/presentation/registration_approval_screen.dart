import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/local_database.dart';

class RegistrationApprovalScreen extends ConsumerStatefulWidget {
  const RegistrationApprovalScreen({super.key});

  @override
  ConsumerState<RegistrationApprovalScreen> createState() => _RegistrationApprovalScreenState();
}

class _RegistrationApprovalScreenState extends ConsumerState<RegistrationApprovalScreen> {
  List<Map<String, dynamic>> _pendingUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingUsers();
  }

  Future<void> _loadPendingUsers() async {
    setState(() => _isLoading = true);
    try {
      final results = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('status', 'pending');

      setState(() {
        _pendingUsers = List<Map<String, dynamic>>.from(results);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading users: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateUserStatus(String userId, String status) async {
    try {
      final now = DateTime.now().toIso8601String();
      await Supabase.instance.client
          .from('profiles')
          .update({'status': status, 'updated_at': now})
          .eq('id', userId);

      // Update local if exists
      final db = await LocalDatabase.instance.database;
      await db.update('profiles', {'status': status, 'updated_at': now}, where: 'id = ?', whereArgs: [userId]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User ${status.toUpperCase()}')));
        _loadPendingUsers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registration Approvals')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPendingUsers,
              child: _pendingUsers.isEmpty
                  ? const Center(child: Text('No pending registrations'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pendingUsers.length,
                      itemBuilder: (context, index) {
                        final user = _pendingUsers[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(child: Text(user['full_name']?[0] ?? 'U')),
                            title: Text(user['full_name'] ?? 'No Name'),
                            subtitle: Text('Role: ${user['role'].toString().toUpperCase()}\nID: ${user['student_id_number'] ?? 'N/A'}'),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                  onPressed: () => _updateUserStatus(user['id'], 'active'),
                                  tooltip: 'Approve',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                                  onPressed: () => _updateUserStatus(user['id'], 'rejected'),
                                  tooltip: 'Reject',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
