import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:api_sdk/api_sdk.dart';

/// Appointments in memory; records which older pages were fetched.
class CalendarRepository extends HealthRepository {
  CalendarRepository() : super(SupabaseClient('http://localhost', 'test-key'));

  List<Appointment> rows = const [];
  final ranges = <(DateTime, DateTime)>[];
  final changes = <(String, AppointmentStatus)>[];

  @override
  Future<List<Appointment>> fetchAppointments({required DateTime since}) async =>
      [for (final a in rows) if (!a.dateTime.isBefore(since)) a];

  @override
  Future<List<Appointment>> fetchAppointmentsBetween({
    required String clinicId,
    required DateTime from,
    required DateTime to,
  }) async {
    ranges.add((from, to));
    return [
      for (final a in rows)
        if (!a.dateTime.isBefore(from) && a.dateTime.isBefore(to)) a,
    ];
  }

  @override
  Future<void> updateStatus(String appointmentId, AppointmentStatus status) async {
    changes.add((appointmentId, status));
    rows = [
      for (final a in rows) a.id == appointmentId ? a.copyWith(status: status) : a,
    ];
  }
}

const _santos = Doctor(
  id: 'd1',
  clinicId: 'c1',
  name: 'Maria Santos',
  specialty: 'General Dentistry',
  availableWeekdays: [1, 2, 3, 4, 5],
  availableTimeSlots: ['08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30'],
);

const _reyes = Doctor(
  id: 'd2',
  clinicId: 'c1',
  name: 'Jose Reyes',
  specialty: 'Orthodontics',
  availableWeekdays: [1, 3, 5],
  availableTimeSlots: ['08:00', '09:00', '10:00', '11:00'],
);

Patient _patient(String id) => Patient(
      id: 'chart-$id',
      personId: 'person-$id',
      clinicId: 'c1',
      name: 'Patient $id',
      phone: '0917',
      email: '$id@email.com',
    );

Appointment _visit(
  String id,
  DateTime at, {
  Doctor doctor = _santos,
  int minutes = 30,
  AppointmentStatus status = AppointmentStatus.confirmed,
  String? patientId,
}) =>
    Appointment(
      id: id,
      clinicId: 'c1',
      patient: _patient(patientId ?? id),
      doctor: doctor,
      dateTime: at,
      service: 'Cleaning',
      status: status,
      durationMinutes: minutes,
    );

/// A Monday at least a week out, so every test day is still to come.
final DateTime _monday = () {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day + 7);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}();

DateTime _at(DateTime day, int hour, [int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);

void _size(WidgetTester tester, double width, [double height = 900]) {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

late final CalendarRepository _repo;

void main() {
  setUpAll(() => _repo = CalendarRepository());

  group('pages', () {
    test('weeks start on Monday', () {
      expect(startOfWeek(DateTime(2026, 9, 23)), DateTime(2026, 9, 21));
      expect(startOfWeek(DateTime(2026, 9, 27)), DateTime(2026, 9, 21));
      expect(startOfWeek(DateTime(2026, 9, 21)), DateTime(2026, 9, 21));
    });

    test('a month page is the six whole weeks around it', () {
      final r = calendarRangeFor(CalendarView.month, DateTime(2026, 9, 23));
      expect(r.from, DateTime(2026, 8, 31));
      expect(r.to, DateTime(2026, 10, 12));
    });

    test('week and day pages', () {
      final w = calendarRangeFor(CalendarView.week, DateTime(2026, 9, 23, 15));
      expect((w.from, w.to), (DateTime(2026, 9, 21), DateTime(2026, 9, 28)));
      final d = calendarRangeFor(CalendarView.day, DateTime(2026, 9, 23, 15));
      expect((d.from, d.to), (DateTime(2026, 9, 23), DateTime(2026, 9, 24)));
    });

    test('paging a month from the 31st lands on the next month', () {
      expect(shiftCalendar(CalendarView.month, DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(shiftCalendar(CalendarView.week, DateTime(2026, 9, 23), -1), DateTime(2026, 9, 16));
      expect(shiftCalendar(CalendarView.day, DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
    });

    test('titles', () {
      expect(calendarTitle(CalendarView.month, DateTime(2026, 9, 23)), 'September 2026');
      expect(calendarTitle(CalendarView.week, DateTime(2026, 9, 23)), 'Sep 21 – 27, 2026');
      expect(calendarTitle(CalendarView.week, DateTime(2026, 9, 30)), 'Sep 28 – Oct 4, 2026');
      expect(calendarTitle(CalendarView.week, DateTime(2026, 12, 30)),
          'Dec 28, 2026 – Jan 3, 2027');
    });
  });

  group('working hours', () {
    final mon = DateTime(2026, 9, 21);

    test('start times become one span, the last lasting one step', () {
      expect(workingSpans(_santos, mon, const []), [(start: 480, end: 720)]);
    });

    test('an hourly list with gaps stays in pieces', () {
      const split = Doctor(
        id: 'd3',
        clinicId: 'c1',
        name: 'Ana Cruz',
        specialty: '',
        availableWeekdays: [1],
        availableTimeSlots: ['08:00', '08:30', '13:00', '13:30'],
      );
      expect(workingSpans(split, mon, const []),
          [(start: 480, end: 540), (start: 780, end: 840)]);
    });

    test('nothing on a day off, on leave, or when the clinic is closed', () {
      expect(workingSpans(_reyes, DateTime(2026, 9, 22), const []), isEmpty);
      final leave = TimeOff(
          id: 't1', clinicId: 'c1', doctorId: 'd1', startsOn: mon, endsOn: mon);
      expect(workingSpans(_santos, mon, [leave]), isEmpty);
      expect(workingSpans(_reyes, mon, [leave]), isNotEmpty);
      final closed = TimeOff(id: 't2', clinicId: 'c1', startsOn: mon, endsOn: mon);
      expect(workingSpans(_reyes, mon, [closed]), isEmpty);
      expect(closureOn([closed], _at(mon, 15)), closed);
    });
  });

  group('overlapping visits', () {
    test('share the width only while they overlap', () {
      final day = DateTime(2026, 9, 21);
      final lanes = layoutLanes([
        _visit('a', _at(day, 9), minutes: 60),
        _visit('b', _at(day, 9, 30), doctor: _reyes),
        _visit('c', _at(day, 10)),
        _visit('d', _at(day, 11)),
      ]);
      expect(lanes['a'], (lane: 0, lanes: 2));
      expect(lanes['b'], (lane: 1, lanes: 2));
      // 10:00 starts as 'a' ends: a new group, full width.
      expect(lanes['c'], (lane: 0, lanes: 1));
      expect(lanes['d'], (lane: 0, lanes: 1));
    });
  });

  group('booking check', () {
    final start = _at(_monday, 9);
    final rows = [
      _visit('x', _at(_monday, 8, 30), minutes: 60), // Santos 8:30–9:30
      _visit('y', _at(_monday, 9), doctor: _reyes, patientId: 'p'), // p with Reyes
    ];

    BookingCheck check(Doctor doctor, DateTime at, {String? patientId, List<TimeOff>? off}) =>
        checkBooking(
          start: at,
          minutes: 30,
          doctor: doctor,
          appointments: rows,
          timeOff: off ?? const [],
          patientId: patientId,
          patientName: 'Juan',
        );

    test('a doctor already seeing someone', () {
      final c = check(_santos, start);
      expect(c.blocking.single, contains('already sees Patient x'));
    });

    test('a patient already booked with another doctor', () {
      final c = check(_santos, _at(_monday, 10), patientId: 'chart-p');
      expect(c.blocking, isEmpty);
      // 9:30 is when that visit ends: free.
      expect(check(_santos, _at(_monday, 10), patientId: 'chart-p').blocking, isEmpty);
      final clash = check(_santos, _at(_monday, 9, 15), patientId: 'chart-p');
      expect(
          clash.blocking,
          contains(allOf(
              contains('Juan already has a visit'), contains('Dr. Jose Reyes'))));
    });

    test('cancelled visits hold no time', () {
      final c = checkBooking(
        start: start,
        minutes: 30,
        doctor: _santos,
        appointments: [
          _visit('x', _at(_monday, 9), status: AppointmentStatus.cancelled),
        ],
        timeOff: const [],
      );
      expect(c.blocking, isEmpty);
    });

    test('past times block; off-grid, leave and closures only warn', () {
      expect(check(_santos, DateTime.now().subtract(const Duration(hours: 1))).blocking,
          contains(startsWith('That time has passed')));
      expect(check(_santos, _at(_monday, 15)).warnings.single, contains('Outside Dr. Maria'));
      expect(check(_reyes, _at(_monday.add(const Duration(days: 1)), 9)).warnings.single,
          contains('Outside'));
      final leave = TimeOff(
          id: 't', clinicId: 'c1', doctorId: 'd1', startsOn: _monday, endsOn: _monday);
      expect(check(_santos, _at(_monday, 10), off: [leave]).warnings.single,
          contains('on leave'));
      expect(check(_santos, _at(_monday, 10)).warnings, isEmpty);
    });
  });

  group('calendar widget', () {
    testWidgets('a week shows each visit as a block that opens it', (tester) async {
      _size(tester, 1400);
      Appointment? opened;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScheduleCalendar(
            view: CalendarView.week,
            date: _monday,
            appointments: [_visit('a', _at(_monday, 9), minutes: 90)],
            doctors: const [_santos],
            onOpen: (a) => opened = a,
          ),
        ),
      ));
      expect(find.text('Patient a'), findsOneWidget);
      // 7 day headings.
      expect(find.text('MON'), findsOneWidget);
      expect(find.text('SUN'), findsOneWidget);
      await tester.tap(find.text('Patient a'));
      expect(opened?.id, 'a');
      // As long as it lasts: 90 minutes at 60 px an hour.
      final block = tester.getSize(find.byType(AppointmentBlock));
      expect(block.height, closeTo(90 - 2, 0.5));
    });

    testWidgets('tapping empty time books it, snapped, in that doctor\'s column',
        (tester) async {
      _size(tester, 1200);
      (DateTime, Doctor?)? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScheduleCalendar(
            view: CalendarView.day,
            date: _monday,
            appointments: const [],
            doctors: const [_santos, _reyes],
            splitByDoctor: true,
            onCreate: (start, doctor) => tapped = (start, doctor),
          ),
        ),
      ));
      expect(find.text('Dr. Maria Santos'), findsOneWidget);
      expect(find.text('Dr. Jose Reyes'), findsOneWidget);
      final column = find.byKey(const ValueKey('calendar-column-d2'));
      final top = tester.getTopLeft(column);
      await tester.tapAt(top + const Offset(30, 10 * 60 + 20)); // 10:20
      expect(tapped?.$1, _at(_monday, 10, 15));
      expect(tapped?.$2?.id, 'd2');
    });

    testWidgets('without onCreate, empty time does nothing', (tester) async {
      _size(tester, 1200);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScheduleCalendar(
            view: CalendarView.day,
            date: _monday,
            appointments: const [],
            doctors: const [_santos],
          ),
        ),
      ));
      final column = find.byKey(const ValueKey('calendar-column-d1'));
      await tester.tapAt(tester.getTopLeft(column) + const Offset(30, 10 * 60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a closed day says so', (tester) async {
      _size(tester, 1200);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScheduleCalendar(
            view: CalendarView.day,
            date: _monday,
            appointments: const [],
            doctors: const [_santos],
            timeOff: [
              TimeOff(
                  id: 't',
                  clinicId: 'c1',
                  startsOn: _monday,
                  endsOn: _monday,
                  reason: 'Holiday'),
            ],
          ),
        ),
      ));
      expect(find.text('Closed · Holiday'), findsOneWidget);
    });

    testWidgets('a busy month day folds into "+n more"; a day opens the day view',
        (tester) async {
      _size(tester, 1400);
      DateTime? day;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScheduleCalendar(
            view: CalendarView.month,
            date: _monday,
            appointments: [
              for (var i = 0; i < 8; i++)
                _visit('m$i', _at(_monday, 8, 0).add(Duration(minutes: 30 * i)),
                    patientId: 'p$i'),
            ],
            onDayTap: (d) => day = d,
          ),
        ),
      ));
      expect(find.textContaining('more'), findsOneWidget);
      await tester.tap(find.textContaining('more'));
      expect(day, _monday);
    });

    testWidgets('fits a phone in every view', (tester) async {
      _size(tester, 360, 740);
      for (final view in CalendarView.values) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ScheduleCalendar(
              view: view,
              date: _monday,
              appointments: [
                _visit('a', _at(_monday, 9)),
                _visit('b', _at(_monday, 9), doctor: _reyes, patientId: 'q'),
              ],
              doctors: const [_santos, _reyes],
              splitByDoctor: true,
              onCreate: (_, __) {},
            ),
          ),
        ));
        expect(tester.takeException(), isNull, reason: view.name);
      }
    });
  });

  group('calendar screen', () {
    Future<void> pump(WidgetTester tester, {double width = 1400}) async {
      _size(tester, width);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appRoleProvider.overrideWithValue(AppRole.assistant),
          currentUserIdProvider.overrideWithValue('u1'),
          currentClinicIdProvider.overrideWithValue('c1'),
          healthRepositoryProvider.overrideWithValue(_repo),
          doctorsProvider.overrideWith((ref) async => const [_santos, _reyes]),
          timeOffProvider.overrideWith((ref) async => const []),
          preferencesProvider.overrideWithValue(AppPreferences.memory()),
        ],
        child: const MaterialApp(
          home: AppointmentCalendarScreen(scope: CalendarScope.clinic, canBook: true),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the front desk sees every doctor, filters to one, and pages back',
        (tester) async {
      final now = DateTime.now();
      _repo
        ..rows = [
          _visit('a', _at(now, 9)),
          _visit('b', _at(now, 9), doctor: _reyes, patientId: 'q'),
          _visit('old', DateTime(now.year, now.month - 3, 10, 9)),
        ]
        ..ranges.clear();
      await pump(tester);

      expect(find.textContaining('Patient a'), findsOneWidget);
      expect(find.textContaining('Patient q'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Dr. Jose Reyes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Patient a'), findsNothing);
      expect(find.textContaining('Patient q'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All doctors'));
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      final asked = _repo.ranges.length;
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
      }
      expect(_repo.ranges.length, greaterThan(asked));
      expect(find.textContaining('Patient old'), findsOneWidget);
    });

    testWidgets('a tapped visit offers the desk\'s next step', (tester) async {
      _repo
        ..rows = [
          _visit('p', _at(_monday, 9), status: AppointmentStatus.pending),
        ]
        ..changes.clear();
      await pump(tester);
      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Patient p'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Move'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(_repo.changes, [('p', AppointmentStatus.confirmed)]);
    });

    testWidgets('tapping empty future time opens the booking sheet with it',
        (tester) async {
      _repo.rows = const [];
      await pump(tester, width: 1200);
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      final days = _monday.difference(DateUtils.dateOnly(DateTime.now())).inHours / 24;
      for (var i = 0; i < days.round(); i++) {
        await tester.tap(find.byTooltip('Next day'));
        await tester.pumpAndSettle();
      }
      expect(find.text(calendarTitle(CalendarView.day, _monday)), findsOneWidget);
      final column = find.byKey(const ValueKey('calendar-column-d2'));
      await tester.tapAt(tester.getTopLeft(column) + const Offset(30, 10 * 60 + 5));
      await tester.pumpAndSettle();
      expect(find.text('New appointment'), findsWidgets);
      expect(find.text('Book'), findsOneWidget);
    });

    testWidgets('fits a phone', (tester) async {
      _repo.rows = [_visit('a', _at(DateTime.now(), 9))];
      await pump(tester, width: 360);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
