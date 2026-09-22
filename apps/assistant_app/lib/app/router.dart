import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';
import '../features/checkin/checkin_screen.dart';
import '../features/booking/walkin_booking_screen.dart';

/// /:clinic/check-in            Check-In tab (home)
/// /:clinic/walkin              Walk-In tab; ?patient= preselects a chart
/// /:clinic/patients            Patients tab
/// /:clinic/patients/:id
/// /:clinic/billing             Billing tab
/// /:clinic/billing/:id         one bill
final assistantRouterProvider = Provider<GoRouter>(
  (ref) => createClinicRouter(
    ref,
    appName: 'Assistant',
    routes: [
      // The front desk has no appointment screen, so visits are not tappable
      // here; booking hands the patient to the Walk-In tab instead.
      GoRoute(
        path: 'billing/:id',
        builder: (_, state) =>
            InvoiceScreen(invoiceId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'patients/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PatientHistoryScreen(
            patientId: id,
            onBook: () => context.goInClinic('/walkin?patient=$id'),
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _NavScaffold(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'check-in',
              builder: (_, __) => const CheckInScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'walkin',
              builder: (_, state) => WalkInBookingScreen(
                initialPatientId: state.uri.queryParameters['patient'],
              ),
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
              path: 'billing',
              builder: (context, _) => BillingScreen(
                onOpenInvoice: (id) => context.pushInClinic('/billing/$id'),
              ),
            ),
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
            icon: Icon(Icons.how_to_reg_outlined),
            selectedIcon: Icon(Icons.how_to_reg),
            label: 'Check-In',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Walk-In',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Billing',
          ),
        ],
      ),
    );
  }
}
