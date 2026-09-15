import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/appointments/appointment_detail_screen.dart';
import '../features/clinic/clinic_settings_screen.dart';

final adminRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/appointments/:id',
      builder: (context, state) =>
          AdminAppointmentDetailScreen(appointmentId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/patients/:id',
      builder: (context, state) => PatientHistoryScreen(
        patientId: state.pathParameters['id']!,
        onOpenAppointment: (a) => context.push('/appointments/${a.id}'),
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _NavScaffold(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/schedule', builder: (_, __) => const ScheduleScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/patients',
            builder: (context, _) => PatientDirectoryScreen(
              onOpenPatient: (p) => context.push('/patients/${p.id}'),
            ),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/clinic', builder: (_, __) => const ClinicSettingsScreen()),
        ]),
      ],
    ),
  ],
);

class _NavScaffold extends StatelessWidget {
  const _NavScaffold({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Clinic',
          ),
        ],
      ),
    );
  }
}
