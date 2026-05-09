import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _NavScaffold(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (_, __) => const DoctorHomeScreen()),
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
    return shell;
  }
}
