import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:api_sdk/api_sdk.dart';

/// Holds appointments in memory; a status change is applied like the
/// database would, without its checks (the board is what is under test).
class BoardRepository extends HealthRepository {
  BoardRepository() : super(SupabaseClient('http://localhost', 'test-key'));

  List<Appointment> rows = const [];
  final changes = <(String, AppointmentStatus)>[];

  @override
  Future<List<Appointment>> fetchAppointments({required DateTime since}) async =>
      rows;

  @override
  Future<void> updateStatus(String appointmentId, AppointmentStatus status) async {
    changes.add((appointmentId, status));
    rows = [
      for (final a in rows)
        a.id == appointmentId ? a.copyWith(status: status) : a,
    ];
  }
}

Appointment _visit(String id, AppointmentStatus status, {int hour = 9}) {
  final now = DateTime.now();
  return Appointment(
    id: id,
    clinicId: 'c1',
    patient: Patient(
      id: 'chart-$id',
      personId: 'person-$id',
      clinicId: 'c1',
      name: 'Patient $id',
      phone: '0917',
      email: '$id@email.com',
    ),
    doctor: const Doctor(
      id: 'd1',
      clinicId: 'c1',
      name: 'Maria Santos',
      specialty: 'General Dentistry',
      availableWeekdays: [1, 2, 3, 4, 5],
      availableTimeSlots: ['09:00'],
    ),
    dateTime: DateTime(now.year, now.month, now.day, hour),
    service: 'Cleaning',
    status: status,
  );
}

// Made outside the widget tests: a SupabaseClient starts a timer that a
// test's fake clock would report as left pending.
late final BoardRepository _repo;

Future<BoardRepository> _pump(
  WidgetTester tester, {
  required AppRole app,
  required bool clinician,
  required List<Appointment> rows,
  double width = 1400,
}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _repo
    ..rows = rows
    ..changes.clear();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appRoleProvider.overrideWithValue(app),
      currentUserIdProvider.overrideWithValue('u1'),
      canSeeClinicalNotesProvider.overrideWith((ref) async => clinician),
      healthRepositoryProvider.overrideWithValue(repo),
      preferencesProvider.overrideWithValue(AppPreferences.memory()),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: AppointmentBoard(
            appointments: ref.watch(appointmentsProvider).value ?? rows,
            onOpen: (_) {},
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUpAll(() => _repo = BoardRepository());

  group('columns', () {
    test('each status has one column; closed visits have none', () {
      expect(BoardColumn.of(AppointmentStatus.pending), BoardColumn.upcoming);
      expect(BoardColumn.of(AppointmentStatus.confirmed), BoardColumn.planned);
      expect(BoardColumn.of(AppointmentStatus.arrived), BoardColumn.inProgress);
      expect(BoardColumn.of(AppointmentStatus.inConsultation),
          BoardColumn.inProgress);
      expect(BoardColumn.of(AppointmentStatus.completed), BoardColumn.completed);
      expect(BoardColumn.of(AppointmentStatus.cancelled), isNull);
      expect(BoardColumn.of(AppointmentStatus.noShow), isNull);
    });
  });

  group('next step', () {
    AppointmentStatus? to(AppointmentStatus s, AppRole app, bool clinician) =>
        boardNextStep(_visit('a', s), app: app, clinician: clinician)?.to;

    test('the front desk confirms, checks in and marks done, but never starts',
        () {
      const desk = AppRole.assistant;
      expect(to(AppointmentStatus.pending, desk, false),
          AppointmentStatus.confirmed);
      expect(to(AppointmentStatus.confirmed, desk, false),
          AppointmentStatus.arrived);
      expect(to(AppointmentStatus.arrived, desk, false),
          AppointmentStatus.completed);
      expect(to(AppointmentStatus.inConsultation, desk, false),
          AppointmentStatus.completed);
    });

    test('an admin at the desk can also start and complete', () {
      expect(to(AppointmentStatus.arrived, AppRole.assistant, true),
          AppointmentStatus.inConsultation);
      expect(to(AppointmentStatus.inConsultation, AppRole.admin, true),
          AppointmentStatus.completed);
      // The admin app checks a planned visit in rather than starting it.
      expect(to(AppointmentStatus.confirmed, AppRole.admin, true),
          AppointmentStatus.arrived);
    });

    test('a doctor starts a planned visit straight away', () {
      expect(to(AppointmentStatus.confirmed, AppRole.doctor, true),
          AppointmentStatus.inConsultation);
      expect(to(AppointmentStatus.inConsultation, AppRole.doctor, true),
          AppointmentStatus.completed);
    });

    test('nothing moves on from a finished visit', () {
      for (final s in [
        AppointmentStatus.completed,
        AppointmentStatus.cancelled,
        AppointmentStatus.noShow,
      ]) {
        expect(to(s, AppRole.admin, true), isNull);
      }
    });
  });

  testWidgets('wide: four columns, counts, closed visits folded away',
      (tester) async {
    await _pump(tester, app: AppRole.admin, clinician: true, rows: [
      _visit('p', AppointmentStatus.pending),
      _visit('c', AppointmentStatus.confirmed),
      _visit('w', AppointmentStatus.arrived),
      _visit('x', AppointmentStatus.inConsultation),
      _visit('done', AppointmentStatus.completed),
      _visit('gone', AppointmentStatus.cancelled),
    ]);
    for (final c in BoardColumn.values) {
      expect(find.text(c.label), findsOneWidget);
    }
    expect(find.text('Cancelled and no-shows (1)'), findsOneWidget);
    expect(find.text('Patient gone'), findsNothing);
    // In progress tells waiting apart from with the doctor.
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('With doctor'), findsOneWidget);
  });

  testWidgets('narrow: the columns become tabs', (tester) async {
    await _pump(tester, app: AppRole.assistant, clinician: false, width: 500,
        rows: [
          _visit('p', AppointmentStatus.pending),
          _visit('c', AppointmentStatus.confirmed),
        ]);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Upcoming (1)'), findsOneWidget);
    expect(find.text('Planned (1)'), findsOneWidget);
    expect(find.byType(DragTarget<Appointment>), findsNothing);
  });

  testWidgets('the card button takes the next step', (tester) async {
    final repo = await _pump(tester,
        app: AppRole.assistant,
        clinician: false,
        rows: [_visit('c', AppointmentStatus.confirmed)]);
    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();
    expect(repo.changes, [('c', AppointmentStatus.arrived)]);
  });

  testWidgets('dragging one column right takes the step; elsewhere does not',
      (tester) async {
    final repo = await _pump(tester,
        app: AppRole.assistant,
        clinician: false,
        rows: [_visit('p', AppointmentStatus.pending)]);

    Future<void> dragTo(String column) async {
      final g = await tester.startGesture(
          tester.getCenter(find.text('Patient p')));
      await tester.pump(const Duration(milliseconds: 300));
      await g.moveTo(tester.getCenter(find.text(column)) + const Offset(0, 80));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
    }

    // Skipping a column is not a move the desk can make.
    await dragTo('In progress');
    expect(repo.changes, isEmpty);

    await dragTo('Planned');
    expect(repo.changes, [('p', AppointmentStatus.confirmed)]);
  });

  test('list or board is remembered per app', () {
    final prefs = AppPreferences.memory();
    ProviderContainer container(AppRole app) {
      final c = ProviderContainer(overrides: [
        appRoleProvider.overrideWithValue(app),
        preferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final doctor = container(AppRole.doctor);
    expect(doctor.read(appointmentViewProvider), AppointmentView.list);
    doctor.read(appointmentViewProvider.notifier).set(AppointmentView.board);
    expect(container(AppRole.doctor).read(appointmentViewProvider),
        AppointmentView.board);
    expect(container(AppRole.assistant).read(appointmentViewProvider),
        AppointmentView.list);
  });
}
