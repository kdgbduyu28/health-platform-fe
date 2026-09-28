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
/// /:clinic/calendar           Calendar tab: my visits by month / week / day
/// /:clinic/appointments/:id
/// /:clinic/book
/// /:clinic/bills              bills at this clinic
/// /:clinic/bills/:id
/// /:clinic/teeth              dental chart (dental clinics)
/// /:clinic/profile            Profile tab
/// /:clinic/preferences        Settings (from Profile)
///
/// …plus sign-in and join, which `createClinicRouter` adds.
final patientRouterProvider = Provider<GoRouter>(
  (ref) => createClinicRouter(
    ref,
    appName: 'Patient',
    landing: (_, __) => const ClinicLandingScreen(),
    routes: [
      GoRoute(
        path: 'preferences',
        builder: (_, __) => _framed(const SettingsScreen()),
      ),
      GoRoute(
        path: 'book',
        builder: (_, __) => _framed(const BookAppointmentScreen()),
      ),
      GoRoute(
        path: 'appointments/:id',
        builder: (context, state) => _framed(
            AppointmentDetailScreen(appointmentId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: 'bills',
        builder: (_, __) => _framed(const MyBillsScreen()),
      ),
      GoRoute(
        path: 'teeth',
        builder: (_, __) => _framed(const _MyTeeth()),
      ),
      GoRoute(
        path: 'bills/:id',
        builder: (_, state) =>
            _framed(InvoiceScreen(invoiceId: state.pathParameters['id']!)),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            ClinicNavScaffold.shell(tabs: _tabs, shell: shell),
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
            GoRoute(
              path: 'calendar',
              builder: (context, _) => AppointmentCalendarScreen(
                scope: CalendarScope.patient,
                onOpenAppointment: (a) =>
                    context.pushInClinic('/appointments/${a.id}'),
                onBookAsPatient: () => context.pushInClinic('/book'),
              ),
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

/// The patient app's tabs, in order; the shell's branches follow the same order.
List<ClinicTab> _tabs(WidgetRef ref) => const [
      ClinicTab(
        path: '/home',
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
      ),
      ClinicTab(
        path: '/appointments',
        label: 'Appointments',
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today,
      ),
      ClinicTab(
        path: '/calendar',
        label: 'Calendar',
        icon: Icons.calendar_view_week_outlined,
        selectedIcon: Icons.calendar_view_week,
      ),
      ClinicTab(
        path: '/profile',
        label: 'Profile',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
      ),
    ];

/// A page opened from a tab, with the tabs beside it on a wide screen.
Widget _framed(Widget page) => ClinicNavScaffold.frame(tabs: _tabs, child: page);

/// The signed-in patient's chart at this clinic, once it has loaded.
class _MyTeeth extends ConsumerWidget {
  const _MyTeeth();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myPatientProvider);
    final guard = asyncGuard(me,
        appBar: AppBar(title: const Text('My teeth')),
        onRetry: () => ref.invalidate(myPatientsProvider));
    if (guard != null) return guard;
    final patient = me.requireValue;
    if (patient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My teeth')),
        body: const Center(child: Text('No chart at this clinic.')),
      );
    }
    return MyDentalChartScreen(patient: patient);
  }
}
