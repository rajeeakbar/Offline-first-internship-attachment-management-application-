import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internship_app/core/config/supabase_config.dart';
import 'package:internship_app/features/auth/presentation/login_screen.dart';
import 'package:internship_app/features/student/presentation/student_dashboard.dart';
import 'package:internship_app/features/supervisor/presentation/supervisor_dashboard.dart';
import 'package:internship_app/features/admin/presentation/admin_dashboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/data/auth_repository.dart';
import 'core/services/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: InternshipApp(),
    ),
  );
}

class InternshipApp extends ConsumerWidget {
  const InternshipApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'Internship Management',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: authState.when(
        data: (session) {
          if (session.session != null) {
            return const RootNavigation();
          }
          return const LoginScreen();
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stack) => Scaffold(
          body: Center(child: Text('Error: $error')),
        ),
      ),
    );
  }
}

class RootNavigation extends ConsumerStatefulWidget {
  const RootNavigation({super.key});

  @override
  ConsumerState<RootNavigation> createState() => _RootNavigationState();
}

class _RootNavigationState extends ConsumerState<RootNavigation> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).startAutoSync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final role = user?.userMetadata?['role'] ?? 'student';

    switch (role) {
      case 'student':
        return const StudentDashboard();
      case 'academic_supervisor':
        return const SupervisorDashboard(isAcademic: true);
      case 'industry_supervisor':
        return const SupervisorDashboard(isAcademic: false);
      case 'admin':
        return const AdminDashboard();
      default:
        return const StudentDashboard();
    }
  }
}
