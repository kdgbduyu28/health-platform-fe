import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';
import '../features/checkin/checkin_screen.dart';
import '../features/booking/walkin_booking_screen.dart';

/// /:clinic/check-in            Check-In tab (home)
/// /:clinic/calendar            Calendar tab: month / week / day; tap
///                              empty time to book it
/// /:clinic/walkin              Walk-In tab; ?patient= preselects a chart
/// /:clinic/patients            Patients tab
/// /:clinic/patients/:id
/// /:clinic/billing             Billing tab
/// /:clinic/billing/:id         one bill
/// /:clinic/prices              what each service costs
/// /:clinic/data                patients, visits and dental charts in and
///                              out as CSV (from Patients)
/// /:clinic/preferences         Settings (from the account menu)
final assistantRouterProvider = Provider<GoRouter>(
  (ref) => createClinicRouter(
    ref,
    appName: 'Assistant',
    routes: [
      GoRoute(
        path: 'preferences',
        builder: (_, __) => _framed(const SettingsScreen()),
      ),
      // The front desk has no appointment screen, so visits are not tappable
      // here; booking hands the patient to the Walk-In tab instead.
      GoRoute(
        path: 'prices',
        builder: (_, __) => _framed(const PriceListScreen()),
      ),
      GoRoute(
        path: 'data',
        builder: (_, __) => _framed(const ImportExportScreen()),
      ),
      GoRoute(
        path: 'billing/:id',
        builder: (_, state) =>
            _framed(InvoiceScreen(invoiceId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: 'patients/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return _framed(PatientHistoryScreen(
            patientId: id,
            onBook: () => context.goInClinic('/walkin?patient=$id'),
            onOpenInvoice: (bill) => context.pushInClinic('/billing/$bill'),
            canRecordVisits: true,
          ));
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            ClinicNavScaffold.shell(tabs: _tabs, shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'check-in',
              builder: (_, __) => const CheckInScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: 'calendar',
              builder: (context, _) => AppointmentCalendarScreen(
                scope: CalendarScope.clinic,
                canBook: true,
                onOpenPatient: (id) => context.pushInClinic('/patients/$id'),
              ),
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
        ],
      ),
    ],
  ),
);

/// The front desk app's tabs, in order; the shell's branches follow the same order.
List<ClinicTab> _tabs(WidgetRef ref) => const [
      ClinicTab(
        path: '/check-in',
        label: 'Check-In',
        icon: Icons.how_to_reg_outlined,
        selectedIcon: Icons.how_to_reg,
      ),
      ClinicTab(
        path: '/calendar',
        label: 'Calendar',
        icon: Icons.calendar_view_week_outlined,
        selectedIcon: Icons.calendar_view_week,
      ),
      ClinicTab(
        path: '/walkin',
        label: 'Walk-In',
        icon: Icons.add_circle_outline,
        selectedIcon: Icons.add_circle,
      ),
      ClinicTab(
        path: '/patients',
        label: 'Patients',
        icon: Icons.group_outlined,
        selectedIcon: Icons.group,
      ),
      ClinicTab(
        path: '/billing',
        label: 'Billing',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
      ),
    ];

/// A page opened from a tab, with the tabs beside it on a wide screen.
Widget _framed(Widget page) => ClinicNavScaffold.frame(tabs: _tabs, child: page);
