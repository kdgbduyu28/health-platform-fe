import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/appointments/appointment_detail_screen.dart';
import '../features/clinic/clinic_settings_screen.dart';

/// /:clinic/dashboard           Dashboard tab (home)
/// /:clinic/schedule            Schedule tab
/// /:clinic/patients            Patients tab
/// /:clinic/patients/:id
/// /:clinic/appointments/:id
/// /:clinic/settings            Clinic tab
///
/// A branch admin is held to their one branch by the router's redirect; a
/// full admin of several switches between them from the title.
final adminRouterProvider = Provider<GoRouter>(
  (ref) => createClinicRouter(
    ref,
    appName: 'Admin',
    routes: [
      GoRoute(
        path: 'appointments/:id',
        builder: (context, state) => AdminAppointmentDetailScreen(
            appointmentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'patients/:id',
        builder: (context, state) => PatientHistoryScreen(
          patientId: state.pathParameters['id']!,
          onOpenAppointment: (a) =>
              context.pushInClinic('/appointments/${a.id}'),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _NavScaffold(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'dashboard',
              builder: (_, __) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'schedule',
              builder: (_, __) => const ScheduleScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'patients',
              builder: (context, _) => PatientDirectoryScreen(
                onOpenPatient: (p) => context.pushInClinic('/patients/${p.id}'),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'settings',
              builder: (_, __) => const ClinicSettingsScreen(),
            ),
          ]),
        ],
      ),
    ],
  ),
);

class _NavScaffold extends ConsumerWidget {
  const _NavScaffold({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // New staff waiting for approval surface on the Clinic tab from anywhere.
    final pending = ref.watch(pendingStaffRequestsProvider).length;
    Widget clinicIcon(IconData icon) => Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending'),
          child: Icon(icon),
        );

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          const NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: clinicIcon(Icons.storefront_outlined),
            selectedIcon: clinicIcon(Icons.storefront),
            label: 'Clinic',
          ),
        ],
      ),
    );
  }
}
