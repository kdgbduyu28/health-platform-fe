import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';
import '../features/home/home_screen.dart';
import '../features/appointments/appointment_detail_screen.dart';

/// /:clinic/schedule            Schedule tab (home)
/// /:clinic/calendar            Calendar tab: month / week / day
/// /:clinic/patients            Patients tab
/// /:clinic/patients/:id
/// /:clinic/appointments/:id
/// /:clinic/preferences         Settings (from the account menu)
final doctorRouterProvider = Provider<GoRouter>(
  (ref) => createClinicRouter(
    ref,
    appName: 'Doctor',
    routes: [
      GoRoute(
        path: 'preferences',
        builder: (_, __) => _framed(const SettingsScreen()),
      ),
      GoRoute(
        path: 'appointments/:id',
        builder: (context, state) => _framed(DoctorAppointmentDetailScreen(
            appointmentId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: 'patients/:id',
        builder: (context, state) => _framed(PatientHistoryScreen(
          patientId: state.pathParameters['id']!,
          onOpenAppointment: (a) =>
              context.openInClinic('/appointments/${a.id}'),
        )),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            ClinicNavScaffold.shell(tabs: _tabs, shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'schedule',
              builder: (_, __) => const DoctorHomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'calendar',
              builder: (context, _) => AppointmentCalendarScreen(
                scope: CalendarScope.doctor,
                onOpenAppointment: (a) =>
                    context.pushInClinic('/appointments/${a.id}'),
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
        ],
      ),
    ],
  ),
);

/// The doctor app's tabs, in order; the shell's branches follow the same order.
List<ClinicTab> _tabs(WidgetRef ref) => const [
      ClinicTab(
        path: '/schedule',
        label: 'Schedule',
        icon: Icons.today_outlined,
        selectedIcon: Icons.today,
      ),
      ClinicTab(
        path: '/calendar',
        label: 'Calendar',
        icon: Icons.calendar_view_week_outlined,
        selectedIcon: Icons.calendar_view_week,
      ),
      ClinicTab(
        path: '/patients',
        label: 'Patients',
        icon: Icons.group_outlined,
        selectedIcon: Icons.group,
      ),
    ];

/// A page opened from a tab, with the tabs beside it on a wide screen.
Widget _framed(Widget page) => ClinicNavScaffold.frame(tabs: _tabs, child: page);
