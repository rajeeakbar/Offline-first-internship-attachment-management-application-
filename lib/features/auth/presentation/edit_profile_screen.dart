import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';
import '../data/auth_repository.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _levelController = TextEditingController();
  final _companyController = TextEditingController();
  final _departmentController = TextEditingController();

  bool _isLoading = false;
  String _role = 'student';

  @override
  void initState() {
    super.initState();
    _prepopulateFields();
  }

  void _prepopulateFields() {
    final profile = ref.read(userProfileProvider).value;
    if (profile != null) {
      _role = profile['role']?.toString() ?? 'student';
      _nameController.text = profile['full_name']?.toString() ?? '';
      _studentIdController.text = profile['student_id_number']?.toString() ?? '';
      _levelController.text = profile['level']?.toString() ?? '';
      _companyController.text = profile['company_name']?.toString() ?? '';
      _departmentController.text = profile['department']?.toString() ?? '';
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(currentUserProvider);
    final profile = ref.read(userProfileProvider).value;
    final String? userId = user?.id ?? profile?['id']?.toString();

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User not found. Please log in again.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = await LocalDatabase.instance.database;
      final now = DateTime.now().toIso8601String();

      // Build update map based on role
      final Map<String, dynamic> updateData = {
        'full_name': _nameController.text.trim(),
        'updated_at': now,
        'is_dirty': 1,
      };

      if (_role == 'student') {
        updateData['student_id_number'] = _studentIdController.text.trim();
        updateData['level'] = _levelController.text.trim();
      } else {
        updateData['company_name'] = _companyController.text.trim();
        updateData['department'] = _departmentController.text.trim();
      }

      // 1. Update in local SQLite instantly
      await db.update('profiles', updateData, where: 'id = ?', whereArgs: [userId]);

      // 2. Update local SharedPreferences cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name_$userId', _nameController.text.trim());
      if (_role == 'student') {
        await prefs.setString('user_student_id_number_$userId', _studentIdController.text.trim());
        await prefs.setString('user_level_$userId', _levelController.text.trim());
      } else {
        await prefs.setString('user_company_name_$userId', _companyController.text.trim());
        await prefs.setString('user_department_$userId', _departmentController.text.trim());
      }

      // 3. Trigger background sync to Supabase
      ref.read(syncServiceProvider).syncData();

      // 4. Invalidate the provider so the app updates instantly
      ref.invalidate(userProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Profile updated successfully! (Local Cache)'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStudent = _role == 'student';
    final isAcademicOrAdmin = _role == 'academic_supervisor' || _role == 'admin';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 50,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Update Personal Information',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Profile Role: ${_role.toUpperCase().replaceAll('_', ' ')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Please enter your name' : null,
                          ),
                          if (isStudent) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _studentIdController,
                              decoration: const InputDecoration(
                                labelText: 'Student ID Number',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Please enter student ID' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _levelController,
                              decoration: const InputDecoration(
                                labelText: 'Level (e.g., Year 3, Master)',
                                prefixIcon: Icon(Icons.school_outlined),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Please enter academic level' : null,
                            ),
                          ] else ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _companyController,
                              decoration: InputDecoration(
                                labelText: isAcademicOrAdmin ? 'Institution Name' : 'Company Name',
                                prefixIcon: const Icon(Icons.business_outlined),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty
                                  ? (isAcademicOrAdmin ? 'Please enter institution name' : 'Please enter company name')
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _departmentController,
                              decoration: const InputDecoration(
                                labelText: 'Department / Division',
                                prefixIcon: Icon(Icons.work_outline_rounded),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Please enter department' : null,
                            ),
                          ],
                          const SizedBox(height: 24),
                          _isLoading
                              ? const CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _saveProfile,
                                  child: const Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    _levelController.dispose();
    _companyController.dispose();
    _departmentController.dispose();
    super.dispose();
  }
}
