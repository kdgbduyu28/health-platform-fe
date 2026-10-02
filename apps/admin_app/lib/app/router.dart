import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/appointments/appointment_detail_screen.dart';
import '../features/clinic/clinic_settings_screen.dart';
import '../features/roster/closures_screen.dart';
import '../features/roster/doctors_screen.dart';
import '../features/roster/services_screen.dart';

/// /:clinic/dashboard           Dashboard tab (home)
/// /:clinic/schedule            Schedule tab
/// /:clinic/calendar            Calendar tab: month / week / day; tap
///                              empty time to book it
/// /:clinic/patients            Patients tab
/// /:clinic/patients/:id
/// /:clinic/appointments/:id
/// /:clinic/billing             Billing tab
/// /:clinic/billing/:id         one bill
/// /:clinic/prices              what each service costs
/// /:clinic/data                patients, visits and dental charts in and
///                              out as CSV (from Patients)
/// /:clinic/activity            who changed what, and when (from Clinic)
/// /:clinic/settings            Clinic tab
/// /:clinic/settings/doctors    roster and working hours
/// /:clinic/settings/services   what can be booked, how long, how much
/// /:clinic/settings/closures   holidays and doctors' leave
/// /:clinic/preferences         this person's Settings (account menu), not
///                              the clinic's
///
/// A branch admin is held to their one branch by the router's redirect; a
/// full admin of several switches between them from the title.
final adminRouterProvider = Provider<GoRouter>(
  (ref) => createClinicRouter(
    ref,
    appName: 'Admin',
    routes: [
      GoRoute(
        path: 'preferences',
        builder: (_, __) => _framed(const SettingsScreen()),
      ),
      GoRoute(
        path: 'appointments/:id',
        builder: (context, state) => _framed(AdminAppointmentDetailScreen(
            appointmentId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: 'prices',
        builder: (_, __) => _framed(const PriceListScreen()),
      ),
      GoRoute(
        path: 'data',
        builder: (_, __) => _framed(const ImportExportScreen()),
      ),
      GoRoute(
        path: 'activity',
        builder: (context, _) => _framed(AuditLogScreen(
          onOpenPatient: (id) => context.pushInClinic('/patients/$id'),
        )),
      ),
      GoRoute(
        path: 'billing/:id',
        builder: (_, state) =>
            _framed(InvoiceScreen(invoiceId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: 'patients/:id',
        builder: (context, state) => _framed(PatientHistoryScreen(
          patientId: state.pathParameters['id']!,
          onOpenAppointment: (a) =>
              context.openInClinic('/appointments/${a.id}'),
          onOpenInvoice: (id) => context.pushInClinic('/billing/$id'),
          canRecordVisits: true,
        )),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            ClinicNavScaffold.shell(tabs: _tabs, shell: shell),
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
              path: 'calendar',
              builder: (context, _) => AppointmentCalendarScreen(
                scope: CalendarScope.clinic,
                canBook: true,
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
                canRecordVisits: true,
                onOpenData: () => context.pushInClinic('/data'),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'billing',
              builder: (context, _) => BillingScreen(
                onOpenInvoice: (id) => context.pushInClinic('/billing/$id'),
                onOpenPrices: () => context.pushInClinic('/prices'),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'settings',
              builder: (_, __) => const ClinicSettingsScreen(),
              routes: [
                GoRoute(
                  path: 'doctors',
                  builder: (_, __) => const DoctorsScreen(),
                ),
                GoRoute(
                  path: 'services',
                  builder: (_, __) => const ServicesScreen(),
                ),
                GoRoute(
                  path: 'closures',
                  builder: (_, __) => const ClosuresScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  ),
);

/// The admin app's tabs, in order; the shell's branches follow the same order.
List<ClinicTab> _tabs(WidgetRef ref) => [
      const ClinicTab(
        path: '/dashboard',
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
      const ClinicTab(
        path: '/schedule',
        label: 'Schedule',
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
      ),
      const ClinicTab(
        path: '/calendar',
        label: 'Calendar',
        icon: Icons.calendar_view_week_outlined,
        selectedIcon: Icons.calendar_view_week,
      ),
      const ClinicTab(
        path: '/patients',
        label: 'Patients',
        icon: Icons.group_outlined,
        selectedIcon: Icons.group,
      ),
      const ClinicTab(
        path: '/billing',
        label: 'Billing',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
      ),
      // New staff waiting for approval surface on the Clinic tab from anywhere.
      ClinicTab(
        path: '/settings',
        label: 'Clinic',
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        badge: ref.watch(pendingStaffRequestsProvider).length,
      ),
    ];

/// A page opened from a tab, with the tabs beside it on a wide screen.
Widget _framed(Widget page) => ClinicNavScaffold.frame(tabs: _tabs, child: page);
