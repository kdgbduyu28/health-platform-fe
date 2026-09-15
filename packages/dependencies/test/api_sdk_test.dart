import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:api_sdk/api_sdk.dart';

Map<String, dynamic> clinicJson(
  String id, {
  String type = 'dental',
  String? seedColor,
  String? iconName = 'medical_services',
  bool embedType = true,
}) =>
    {
      'id': id,
      'name': 'Clinic $id',
      'slug': 'clinic-$id',
      'type': type,
      'seed_color': seedColor,
      if (embedType)
        'clinic_type': {'display_name': 'Dental', 'icon_name': iconName},
    };

Clinic clinic(String id) => Clinic.fromJson(clinicJson(id));

Patient chartAt(String clinicId) => Patient(
      id: 'chart-$clinicId',
      personId: 'person-1',
      clinicId: clinicId,
      name: 'Juan dela Cruz',
      phone: '0917',
      email: '',
    );

ClinicMembership staffAt(String clinicId, AppRole role) =>
    ClinicMembership(profileId: 'u1', clinicId: clinicId, role: role);

/// A container wired as one of the four apps, with the network-backed
/// providers replaced by fixed data.
ProviderContainer appContainer({
  required AppRole app,
  List<Clinic> visible = const [],
  List<Patient> charts = const [],
  List<ClinicMembership> memberships = const [],
}) {
  final container = ProviderContainer(overrides: [
    appRoleProvider.overrideWithValue(app),
    currentUserIdProvider.overrideWithValue('u1'),
    visibleClinicsProvider.overrideWith((ref) async => visible),
    myPatientsProvider.overrideWith((ref) async => charts),
    myMembershipsProvider.overrideWith((ref) async => memberships),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<List<String>> clinicIds(ProviderContainer c) async =>
    [for (final clinic in await c.read(myClinicsProvider.future)) clinic.id];

void main() {
  group('Clinic.fromJson', () {
    test('reads the embedded vertical and brand colour', () {
      final c = Clinic.fromJson(clinicJson('a', seedColor: '#654F3B'));
      expect(c.typeSlug, 'dental');
      expect(c.typeName, 'Dental');
      expect(c.icon, Icons.medical_services_outlined);
      expect(c.seedColor, const Color(0xFF654F3B));
    });

    test('an unknown vertical icon falls back instead of failing', () {
      final c = Clinic.fromJson(clinicJson('a', iconName: 'not_an_icon'));
      expect(c.icon, Icons.local_hospital_outlined);
    });

    test('without the embed, the slug stands in for the vertical name', () {
      final c = Clinic.fromJson(
          clinicJson('a', type: 'derma', embedType: false));
      expect(c.typeName, 'derma');
      expect(c.icon, Icons.local_hospital_outlined);
    });
  });

  group('hex colours', () {
    test('parse and print round-trip', () {
      expect(toHexColor(parseHexColor('#1f8a70')!), '#1F8A70');
    });

    test('malformed values are null, not a broken theme', () {
      expect(parseHexColor(null), isNull);
      expect(parseHexColor('654F3B'), isNull);
      expect(parseHexColor('#FFF'), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
    });
  });

  group('Patient.fromJson', () {
    test('flattens the person onto the chart', () {
      final p = Patient.fromJson({
        'id': 'chart-1',
        'person_id': 'person-1',
        'clinic_id': 'clinic-1',
        'medical_notes': 'Allergic to latex.',
        'person': {
          'full_name': 'Maria Reyes',
          'phone': '0928',
          'email': null,
          'date_of_birth': '1985-07-22',
        },
      });
      expect(p.id, 'chart-1');
      expect(p.clinicId, 'clinic-1');
      expect(p.name, 'Maria Reyes');
      expect(p.email, '');
      expect(p.initials, 'MR');
      expect(p.medicalNotes, 'Allergic to latex.');
      expect(p.dateOfBirth, DateTime(1985, 7, 22));
    });

    test('a missing person degrades to blanks rather than a crash', () {
      final p = Patient.fromJson(
          {'id': 'c', 'person_id': 'p', 'clinic_id': 'k'});
      expect(p.name, '');
      expect(p.initials, '?');
    });
  });

  test('Appointment.fromJson reads the clinic id and nested chart', () {
    final a = Appointment.fromJson({
      'id': 'appt-1',
      'clinic_id': 'clinic-1',
      'scheduled_at': '2026-09-14T01:00:00Z',
      'service_name': 'Teeth Cleaning',
      'status': 'pending',
      'patient': {
        'id': 'chart-1',
        'person_id': 'person-1',
        'clinic_id': 'clinic-1',
        'person': {'full_name': 'Juan dela Cruz'},
      },
      'doctor': {
        'id': 'doc-1',
        'clinic_id': 'clinic-1',
        'full_name': 'Maria Santos',
      },
    });
    expect(a.clinicId, 'clinic-1');
    expect(a.patient.name, 'Juan dela Cruz');
    expect(a.doctor.clinicId, 'clinic-1');
    expect(a.status, AppointmentStatus.pending);
  });

  test('AppRole.isGrantedBy: which membership opens which app', () {
    const doctor = AppRole.doctor;
    const assistant = AppRole.assistant;
    const admin = AppRole.admin;

    expect(doctor.isGrantedBy(AppRole.doctor), isTrue);
    expect(doctor.isGrantedBy(AppRole.admin), isFalse);
    expect(assistant.isGrantedBy(AppRole.assistant), isTrue);
    expect(assistant.isGrantedBy(AppRole.admin), isTrue);
    expect(assistant.isGrantedBy(AppRole.doctor), isFalse);
    expect(admin.isGrantedBy(AppRole.admin), isTrue);
    expect(admin.isGrantedBy(AppRole.assistant), isFalse);
    expect(AppRole.patient.isGrantedBy(AppRole.admin), isFalse);
  });

  test('describeError passes database messages through verbatim', () {
    const error = PostgrestException(
      message: 'that clinic code is not valid',
      code: 'P0001',
    );
    expect(describeError(error), 'that clinic code is not valid');
  });

  group('myClinicsProvider narrows clinics to the running app', () {
    final a = clinic('a'), b = clinic('b'), c = clinic('c');

    test('patient app: only clinics where they hold a chart', () async {
      final container = appContainer(
        app: AppRole.patient,
        visible: [a, b, c],
        charts: [chartAt('a'), chartAt('c')],
      );
      expect(await clinicIds(container), ['a', 'c']);
    });

    test('doctor app: excludes a clinic where they are only a patient', () async {
      // One account: doctor at A, patient at B. RLS returns both clinics.
      final container = appContainer(
        app: AppRole.doctor,
        visible: [a, b],
        charts: [chartAt('b')],
        memberships: [staffAt('a', AppRole.doctor)],
      );
      expect(await clinicIds(container), ['a']);
    });

    test('doctor app: an admin role elsewhere does not count', () async {
      final container = appContainer(
        app: AppRole.doctor,
        visible: [a, b],
        memberships: [staffAt('a', AppRole.doctor), staffAt('b', AppRole.admin)],
      );
      expect(await clinicIds(container), ['a']);
    });

    test('assistant app: admins may run the front desk', () async {
      final container = appContainer(
        app: AppRole.assistant,
        visible: [a, b, c],
        memberships: [
          staffAt('a', AppRole.assistant),
          staffAt('b', AppRole.admin),
          staffAt('c', AppRole.doctor),
        ],
      );
      expect(await clinicIds(container), ['a', 'b']);
    });

    test('a signed-in account attached to nothing gets nothing', () async {
      final container = appContainer(app: AppRole.admin, visible: []);
      expect(await clinicIds(container), isEmpty);
    });
  });

  group('currentClinicProvider', () {
    final a = clinic('a'), b = clinic('b');

    ProviderContainer twoClinicAdmin() => appContainer(
          app: AppRole.admin,
          visible: [a, b],
          memberships: [staffAt('a', AppRole.admin), staffAt('b', AppRole.admin)],
        );

    test('defaults to the first clinic', () async {
      final container = twoClinicAdmin();
      await container.read(myClinicsProvider.future);
      expect(container.read(currentClinicIdProvider), 'a');
    });

    test('follows an explicit switch', () async {
      final container = twoClinicAdmin();
      await container.read(myClinicsProvider.future);
      container.read(selectedClinicIdProvider.notifier).select('b');
      expect(container.read(currentClinicIdProvider), 'b');
    });

    test('never lands on a clinic the app does not offer', () async {
      final container = appContainer(
        app: AppRole.admin,
        visible: [a, b],
        memberships: [staffAt('a', AppRole.admin), staffAt('b', AppRole.doctor)],
      );
      await container.read(myClinicsProvider.future);
      // B is visible to this account, but not as an admin.
      container.read(selectedClinicIdProvider.notifier).select('b');
      expect(container.read(currentClinicIdProvider), 'a');
    });

    test('is null when the account belongs to no clinic', () async {
      final container = appContainer(app: AppRole.patient, visible: [a]);
      await container.read(myClinicsProvider.future);
      expect(container.read(currentClinicProvider).value, isNull);
    });
  });
}
