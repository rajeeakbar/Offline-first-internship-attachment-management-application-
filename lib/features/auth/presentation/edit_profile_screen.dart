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
  final _deptOrCompanyController = TextEditingController();
  String _selectedLevel = 'Level 100';
  bool _isLoading = false;

  final List<String> _levels = [
    'Level 100',
    'Level 200',
    'Level 300',
    'Level 400',
    'Post-Grad',
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    final profile = ref.read(userProfileProvider).value;
    if (profile != null) {
      _nameController.text = profile['full_name'] ?? '';
      _studentIdController.text = profile['student_id_number'] ?? '';

      final role = profile['role'] ?? 'student';
      if (role == 'academic_supervisor') {
        _deptOrCompanyController.text = profile['department'] ?? '';
      } else {
        _deptOrCompanyController.text = profile['company_name'] ?? '';
      }

      final level = profile['level'] ?? 'Level 100';
      if (_levels.contains(level)) {
        _selectedLevel = level;
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(currentUserProvider);
    final profile = ref.read(userProfileProvider).value;
    final effectiveUserId = user?.id ?? profile?['id'];

    if (effectiveUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No active user session.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = await LocalDatabase.instance.database;
      final now = DateTime.now().toIso8601String();
      final role = profile?['role'] ?? 'student';

      final Map<String, dynamic> updateData = {
        'full_name': _nameController.text.trim(),
        'updated_at': now,
        'is_dirty': 1,
      };

      if (role == 'student') {
        updateData['student_id_number'] = _studentIdController.text.trim();
        updateData['level'] = _selectedLevel;
      } else if (role == 'academic_supervisor') {
        updateData['department'] = _deptOrCompanyController.text.trim();
      } else if (role == 'industry_supervisor') {
        updateData['company_name'] = _deptOrCompanyController.text.trim();
      }

      // 1. Update SQLite Local Table
      await db.update(
        'profiles',
        updateData,
        where: 'id = ?',
        whereArgs: [effectiveUserId],
      );

      // 2. Update SharedPreferences cache for instant synchronous reading
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name_$effectiveUserId', _nameController.text.trim());
      if (role == 'student') {
        await prefs.setString('user_student_id_number_$effectiveUserId', _studentIdController.text.trim());
        await prefs.setString('user_level_$effectiveUserId', _selectedLevel);
      }

      // 3. Invalidate profile provider to force UI redraw
      ref.invalidate(userProfileProvider);

      // 4. Trigger background sync
      ref.read(syncServiceProvider).syncData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(userProfileProvider).value;
    final role = profile?['role'] ?? 'student';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Update Personal Information',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Adjust your profile details which are displayed across the institution portal.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.withOpacity(0.1)),
                  ),
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
                          validator: (value) => value == null || value.isEmpty
                              ? 'Please enter your name'
                              : null,
                        ),
                        if (role == 'student') ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _studentIdController,
                            decoration: const InputDecoration(
                              labelText: 'School Student ID',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Please enter your student ID'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedLevel,
                            decoration: const InputDecoration(
                              labelText: 'Current Level',
                              prefixIcon: Icon(Icons.layers_outlined),
                            ),
                            items: _levels.map((level) {
                              return DropdownMenuItem(
                                value: level,
                                child: Text(level),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedLevel = value);
                              }
                            },
                          ),
                        ],
                        if (role == 'academic_supervisor') ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _deptOrCompanyController,
                            decoration: const InputDecoration(
                              labelText: 'Institution Department',
                              prefixIcon: Icon(Icons.school_outlined),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Please enter your department'
                                : null,
                          ),
                        ],
                        if (role == 'industry_supervisor') ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _deptOrCompanyController,
                            decoration: const InputDecoration(
                              labelText: 'Company / Organization Name',
                              prefixIcon: Icon(Icons.business_outlined),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Please enter your company name'
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _saveProfile,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Save Profile Changes',
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
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    _deptOrCompanyController.dispose();
    super.dispose();
  }
}
