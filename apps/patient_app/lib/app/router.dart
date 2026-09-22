import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';
import '../features/home/home_screen.dart';
import '../features/landing/clinic_landing_screen.dart';
import '../features/appointments/my_appointments_screen.dart';
import '../features/appointments/book_appointment_screen.dart';
import '../features/appointments/appointment_detail_screen.dart';
import '../features/billing/my_bills_screen.dart';
import '../features/profile/profile_screen.dart';

/// /:clinic                    the clinic's public page
/// /:clinic/home               Home tab
/// /:clinic/appointments       Appointments tab
/// /:clinic/appointments/:id
/// /:clinic/book
/// /:clinic/bills              bills at this clinic
/// /:clinic/bills/:id
/// /:clinic/profile            Profile tab
///
/// …plus sign-in and join, which `createClinicRouter` adds.
final patientRouterProvider = Provider<GoRouter>(
  (ref) => createClinicRouter(
    ref,
    appName: 'Patient',
    landing: (_, __) => const ClinicLandingScreen(),
    routes: [
      GoRoute(
        path: 'book',
        builder: (_, __) => const BookAppointmentScreen(),
      ),
      GoRoute(
        path: 'appointments/:id',
        builder: (context, state) =>
            AppointmentDetailScreen(appointmentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'bills',
        builder: (_, __) => const MyBillsScreen(),
      ),
      GoRoute(
        path: 'bills/:id',
        builder: (_, state) =>
            InvoiceScreen(invoiceId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _NavScaffold(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: 'home', builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'appointments',
              builder: (_, __) => const MyAppointmentsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: 'profile', builder: (_, __) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  ),
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
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Appointments',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
