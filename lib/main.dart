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
      key: ValueKey(ref.watch(currentUserProvider)?.id ?? 'unauthenticated'),
      title: 'Internship Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo,
          secondary: Colors.amber,
          surface: Colors.grey[50]!,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.indigo.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.indigo, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
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
    _startSync();
  }

  void _startSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).startAutoSync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final user = ref.watch(currentUserProvider);

    return profileAsync.when(
      data: (profile) {
        // Use local DB role, fallback to auth metadata
        final role = profile?['role'] ?? user?.userMetadata?['role'];

        if (role == null) {
          // If still null, wait for loading
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Fetching profile details...', style: TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );
        }

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
      },
      loading: () => const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Setting up your workspace...', style: TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text('Session error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
