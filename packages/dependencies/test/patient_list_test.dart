import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:api_sdk/api_sdk.dart';

const _patient = Patient(
  id: 'chart-1',
  personId: 'person-1',
  clinicId: 'c1',
  name: 'Ana Cruz',
  phone: '0917 555 0101',
  email: '',
);

Appointment _visit(String id, DateTime at, AppointmentStatus status) =>
    Appointment(
      id: id,
      clinicId: 'c1',
      patient: _patient,
      doctor: const Doctor(
        id: 'd1',
        clinicId: 'c1',
        name: 'Maria Santos',
        specialty: 'General Dentistry',
        availableWeekdays: [1, 2, 3, 4, 5],
        availableTimeSlots: ['09:00'],
      ),
      dateTime: at,
      service: 'Cleaning',
      status: status,
    );

Invoice _bill(InvoiceStatus status, double total, double paid, DateTime issued) =>
    Invoice(
      id: 'inv-$total-$paid',
      clinicId: 'c1',
      patientId: 'chart-1',
      status: status,
      subtotal: total,
      discountAmount: 0,
      total: total,
      amountPaid: paid,
      createdAt: issued,
      issuedAt: issued,
    );

void main() {
  final now = DateTime(2026, 9, 23, 10);

  group('PatientPage.fromJson', () {
    test('reads the remarks, the counts and the visit details', () {
      final page = PatientPage.fromJson({
        'total': 1,
        'counts': {'all': 40, 'recall': 3, 'balance': 2, 'pedia': 5},
        'patients': [
          {
            'id': 'chart-1',
            'person_id': 'person-1',
            'clinic_id': 'c1',
            'person': {'full_name': 'Ana Cruz', 'phone': null, 'email': null},
            'completed_visits': 4,
            'first_visit_at': '2025-01-10T01:00:00+00:00',
            'last_visit_at': '2026-02-01T01:00:00+00:00',
            'last_visit_status': 'no_show',
            'last_visit_service': 'Filling',
            'last_visit_doctor': 'Maria Santos',
            'balance': 1500.5,
            'planned_count': 2,
            'age': 9,
            'flags': ['balance', 'attention', 'pedia', 'something_new'],
            'attention': ['no_show', 'unbooked_plan'],
          },
        ],
      });
      expect(page.total, 1);
      expect(page.all, 40);
      expect(page.counts[PatientFlag.recall], 3);
      expect(page.counts.containsKey(PatientFlag.attention), isFalse);
      final l = page.patients.single;
      expect(l.completedVisits, 4);
      expect(l.firstVisitAt, isNotNull);
      expect(l.lastVisitMissed, isTrue);
      expect(l.lastVisitDoctor, 'Maria Santos');
      expect(l.balance, 1500.5);
      expect(l.age, 9);
      // An unknown remark from a newer database is skipped, not a crash.
      expect(l.flags,
          {PatientFlag.balance, PatientFlag.attention, PatientFlag.pedia});
      expect(l.attention,
          {AttentionReason.noShow, AttentionReason.unbookedPlan});
    });

    test('an older database without remarks still parses', () {
      final page = PatientPage.fromJson({
        'total': 1,
        'patients': [
          {
            'id': 'chart-1',
            'person_id': 'person-1',
            'clinic_id': 'c1',
            'person': {'full_name': 'Ana Cruz'},
            'completed_visits': 1,
          },
        ],
      });
      expect(page.all, isNull);
      expect(page.patients.single.flags, isEmpty);
      expect(page.patients.single.balance, 0);
    });
  });

  group('PatientTableQuery', () {
    test('equal filters in any order are the same query', () {
      const a = PatientTableQuery(
          filters: {PatientFlag.recall, PatientFlag.balance});
      const b = PatientTableQuery(
          filters: {PatientFlag.balance, PatientFlag.recall});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(page: 2), isNot(b));
    });
  });

  group('patientRemarks mirrors search_patients', () {
    ({Set<PatientFlag> flags, Set<AttentionReason> attention}) remarks({
      Patient patient = _patient,
      List<Appointment> visits = const [],
      List<Invoice> invoices = const [],
      int planned = 0,
      int recallMonths = 6,
    }) =>
        patientRemarks(
          patient: patient,
          visits: visits,
          invoices: invoices,
          plannedCount: planned,
          recallMonths: recallMonths,
          now: now,
        );

    test('seen 8 months ago, nothing booked: for recall', () {
      final old = _visit('a', DateTime(2026, 1, 20), AppointmentStatus.completed);
      expect(remarks(visits: [old]).flags, contains(PatientFlag.recall));
      expect(remarks(visits: [old], recallMonths: 12).flags,
          isNot(contains(PatientFlag.recall)));
      final booked =
          _visit('b', DateTime(2026, 10, 1), AppointmentStatus.confirmed);
      expect(remarks(visits: [old, booked]).flags,
          isNot(contains(PatientFlag.recall)));
    });

    test('an issued bill with money left is a balance; a draft is not', () {
      final issued = _bill(InvoiceStatus.issued, 1500, 500, DateTime(2026, 9, 20));
      final draft = _bill(InvoiceStatus.draft, 900, 0, DateTime(2026, 9, 20));
      expect(remarks(invoices: [issued]).flags, contains(PatientFlag.balance));
      expect(remarks(invoices: [issued]).attention, isEmpty);
      expect(remarks(invoices: [draft]).flags,
          isNot(contains(PatientFlag.balance)));
    });

    test('unpaid 30+ days, a missed last visit, or an unbooked plan: attention',
        () {
      final overdue = _bill(InvoiceStatus.issued, 1500, 0, DateTime(2026, 8, 1));
      final missed =
          _visit('m', DateTime(2026, 9, 1), AppointmentStatus.noShow);
      final r = remarks(invoices: [overdue], visits: [missed], planned: 2);
      expect(r.flags, contains(PatientFlag.attention));
      expect(r.attention, {
        AttentionReason.overdueBalance,
        AttentionReason.noShow,
        AttentionReason.unbookedPlan,
      });
    });

    test('no phone and no email; pedia and adult by age', () {
      const nobody = Patient(
        id: 'chart-2',
        personId: 'person-2',
        clinicId: 'c1',
        name: 'Ben',
        phone: ' ',
        email: '',
      );
      expect(remarks(patient: nobody).flags, {PatientFlag.noContact});
      final child = Patient(
        id: 'chart-3',
        personId: 'person-3',
        clinicId: 'c1',
        name: 'Lia',
        phone: '0917',
        email: '',
        dateOfBirth: DateTime(DateTime.now().year - 10, 1, 1),
      );
      expect(remarks(patient: child).flags, {PatientFlag.pedia});
    });
  });

  testWidgets('remark chips explain "Needs attention"', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: RemarkChips(
            flags: {PatientFlag.attention, PatientFlag.recall, PatientFlag.adult},
            attention: {AttentionReason.noShow},
            showAgeGroup: false,
          ),
        ),
      ),
    ));
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('For recall'), findsOneWidget);
    expect(find.text('Adult'), findsNothing);
    expect(find.byTooltip('Missed the last visit'), findsOneWidget);
  });
}
