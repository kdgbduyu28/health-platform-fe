import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:api_sdk/api_sdk.dart';

const _clinic = Clinic(
  id: 'c1',
  name: 'D-Touch',
  slug: 'dtouch',
  typeSlug: 'dental',
  typeName: 'Dental',
  chartKind: 'dental',
);

const _ana = Patient(
  id: 'chart-1',
  personId: 'person-1',
  clinicId: 'c1',
  name: 'Ana Cruz',
  phone: '0917 555 0101',
  email: 'ana@example.com',
);

const _doctor = Doctor(
  id: 'd1',
  clinicId: 'c1',
  name: 'Maria Santos',
  specialty: 'General Dentistry',
  availableWeekdays: [1, 2, 3, 4, 5],
  availableTimeSlots: ['09:00'],
);

/// Serves one patient's record, and a list page, from memory.
class _Repo extends HealthRepository {
  _Repo() : super(SupabaseClient('http://localhost', 'test-key'));

  final searches = <(Set<PatientFlag>, PatientSort, bool, int)>[];

  late final visits = [
    Appointment(
      id: 'v2',
      clinicId: 'c1',
      patient: _ana,
      doctor: _doctor,
      dateTime: DateTime.now().subtract(const Duration(days: 40)),
      service: 'Root Canal',
      status: AppointmentStatus.completed,
      patientNote: 'Avoid chewing on the left for a day.',
    ),
    Appointment(
      id: 'v1',
      clinicId: 'c1',
      patient: _ana,
      doctor: _doctor,
      dateTime: DateTime.now().subtract(const Duration(days: 400)),
      service: 'Cleaning',
      status: AppointmentStatus.completed,
    ),
  ];

  @override
  Future<PatientPage> searchPatients(
    String clinicId, {
    String? query,
    int offset = 0,
    int limit = 30,
    Set<PatientFlag> filters = const {},
    PatientSort sort = PatientSort.name,
    bool descending = false,
  }) async {
    searches.add((filters, sort, descending, offset));
    return PatientPage(
      total: 60,
      all: 60,
      counts: const {PatientFlag.recall: 4, PatientFlag.balance: 2},
      patients: [
        PatientListing(
          patient: _ana,
          completedVisits: 2,
          firstVisitAt: visits.last.dateTime,
          lastVisitAt: visits.first.dateTime,
          lastVisitService: 'Root Canal',
          lastVisitDoctor: 'Maria Santos',
          balance: 1500,
          age: 34,
          flags: const {
            PatientFlag.balance,
            PatientFlag.attention,
            PatientFlag.adult,
          },
          attention: const {AttentionReason.unbookedPlan},
        ),
        const PatientListing(
          patient: Patient(
            id: 'chart-2',
            personId: 'person-2',
            clinicId: 'c1',
            name: 'Ben Reyes',
            phone: '',
            email: '',
          ),
          age: 8,
          flags: {PatientFlag.noContact, PatientFlag.pedia},
        ),
      ],
    );
  }

  @override
  Future<List<Appointment>> fetchAppointments({required DateTime since}) async =>
      const [];

  @override
  Future<Patient?> fetchPatient(String patientId) async => _ana;

  @override
  Future<List<Appointment>> fetchPatientHistory(String patientId,
          {bool withVisitNotes = false}) async =>
      visits;

  @override
  Future<ClinicalNote?> fetchChartNote(String patientId) async => null;

  @override
  Future<PatientIntake?> fetchIntake(String patientId) async => null;

  @override
  Future<List<DentalEntry>> fetchDentalEntries(String patientId) async => [
        DentalEntry(
          id: 'e1',
          tooth: 46,
          code: DentalCode.fromWire('root_canal'),
          status: DentalEntryStatus.done,
          appointmentId: 'v2',
          note: 'Two canals',
        ),
        DentalEntry(
          id: 'e2',
          tooth: 46,
          code: DentalCode.fromWire('crown'),
          status: DentalEntryStatus.planned,
          appointmentId: 'v2',
        ),
      ];

  @override
  Future<List<Invoice>> fetchPatientInvoices(String patientId) async => [
        Invoice(
          id: 'inv1',
          clinicId: 'c1',
          patientId: patientId,
          number: 'INV-000001',
          status: InvoiceStatus.issued,
          subtotal: 3000,
          discountAmount: 0,
          total: 3000,
          amountPaid: 1500,
          createdAt: DateTime.now().subtract(const Duration(days: 40)),
          issuedAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
      ];
}

late final _Repo _repo;

Future<void> _pump(WidgetTester tester, Widget child,
    {double width = 1400, AppRole app = AppRole.doctor}) async {
  tester.view
    ..physicalSize = Size(width, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appRoleProvider.overrideWithValue(app),
      currentUserIdProvider.overrideWithValue('u1'),
      currentClinicProvider.overrideWithValue(const AsyncValue.data(_clinic)),
      canSeeClinicalNotesProvider.overrideWith((ref) async => true),
      healthRepositoryProvider.overrideWithValue(_repo),
      preferencesProvider.overrideWithValue(AppPreferences.memory()),
    ],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => _repo = _Repo());

  group('patient list', () {
    testWidgets('a table on a desktop: remarks, balance, pages', (tester) async {
      await _pump(tester, PatientDirectoryScreen(onOpenPatient: (_) {}));
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('₱1,500'), findsOneWidget);
      expect(find.widgetWithText(RemarkChip, 'Needs attention'), findsOneWidget);
      expect(find.text('No contact info'), findsWidgets);
      expect(find.text('For recall  4'), findsOneWidget);
      expect(find.text('1–25 of 60'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);

      _repo.searches.clear();
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(_repo.searches.last.$4, 25);
      expect(find.text('2 / 3'), findsOneWidget);

      // A filter starts again at page one.
      await tester.tap(find.text('With balance  2'));
      await tester.pumpAndSettle();
      expect(_repo.searches.last.$1, {PatientFlag.balance});
      expect(_repo.searches.last.$4, 0);

      // Sorting by a date starts with the latest.
      await tester.tap(find.text('Last visit'));
      await tester.pumpAndSettle();
      expect(_repo.searches.last.$2, PatientSort.lastVisit);
      expect(_repo.searches.last.$3, isTrue);
    });

    testWidgets('pedia and adult are one or the other', (tester) async {
      await _pump(tester, PatientDirectoryScreen(onOpenPatient: (_) {}));
      await tester.tap(find.widgetWithText(FilterChip, 'Pedia'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Adult'));
      await tester.pumpAndSettle();
      expect(_repo.searches.last.$1, {PatientFlag.adult});
    });

    testWidgets('cards on a phone', (tester) async {
      await _pump(tester, PatientDirectoryScreen(onOpenPatient: (_) {}),
          width: 390);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Ana Cruz, 34'), findsOneWidget);
      expect(find.byTooltip('Sort'), findsOneWidget);
    });

    for (final width in [360.0, 700.0]) {
      testWidgets('the front desk at ${width.toInt()}px: pager beside "Add patient"',
          (tester) async {
        await _pump(tester, PatientDirectoryScreen(onOpenPatient: (_) {}),
            width: width, app: AppRole.assistant);
        expect(find.byTooltip('Next page'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('patient page', () {
    for (final width in [1400.0, 390.0]) {
      testWidgets('the handover and every tab at ${width.toInt()}px',
          (tester) async {
        await _pump(tester, const PatientHistoryScreen(patientId: 'chart-1'),
            width: width);
        // Header: the numbers and the remarks worked out on the page.
        expect(find.text('Balance'), findsOneWidget);
        expect(find.text('Needs attention'), findsOneWidget);
        // Overview: the last visit in full, and the plan not booked.
        expect(find.text('Last visit'), findsWidgets);
        expect(find.text('Avoid chewing on the left for a day.'),
            findsOneWidget);
        expect(find.text('Not booked yet'), findsOneWidget);
        expect(find.text('No information form on file'), findsOneWidget);

        Future<void> openTab(String label) async {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await tester.tap(find.text('Treatments (1)'));
        await tester.pumpAndSettle();
        expect(find.textContaining('1 treatment over 1 visit'), findsOneWidget);

        await openTab('Appointments (2)');
        expect(find.text('Visit history'), findsOneWidget);

        await openTab('Billing (1)');
        expect(find.text('Billed'), findsOneWidget);
        expect(find.text('₱3,000'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
