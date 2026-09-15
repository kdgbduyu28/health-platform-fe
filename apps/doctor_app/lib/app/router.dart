import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';
import '../features/home/home_screen.dart';
import '../features/appointments/appointment_detail_screen.dart';

final doctorRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/appointments/:id',
      builder: (context, state) => DoctorAppointmentDetailScreen(
          appointmentId: state.pathParameters['id']!),
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
          GoRoute(path: '/', builder: (_, __) => const DoctorHomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/patients',
            builder: (context, _) => PatientDirectoryScreen(
              onOpenPatient: (p) => context.push('/patients/${p.id}'),
            ),
          ),
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
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Patients',
          ),
        ],
      ),
    );
  }
}
