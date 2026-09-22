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
      expect(p.dateOfBirth, DateTime(1985, 7, 22));
    });

    test('a missing person degrades to blanks rather than a crash', () {
      final p = Patient.fromJson(
          {'id': 'c', 'person_id': 'p', 'clinic_id': 'k'});
      expect(p.name, '');
      expect(p.initials, '?');
    });

    test('search matches a name, or a phone however it is typed', () {
      final p = Patient.fromJson({
        'id': 'c',
        'person_id': 'p',
        'clinic_id': 'k',
        'person': {'full_name': 'Maria Reyes', 'phone': '0928-123-4567'},
      });
      expect(p.matches(''), isTrue);
      expect(p.matches('reyes'), isTrue);
      expect(p.matches('928 123'), isTrue);
      expect(p.matches('juan'), isFalse);
      // The front desk's duplicate check: same number, different formatting.
      expect(p.hasPhone('+63 928 123 4567'), isTrue);
      expect(p.hasPhone('09281234560'), isFalse);
      expect(p.hasPhone(''), isFalse);
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

  group('Appointment notes', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'id': 'appt-1',
          'clinic_id': 'clinic-1',
          'scheduled_at': '2026-09-14T01:00:00Z',
          'service_name': 'Teeth Cleaning',
          'status': 'completed',
          'patient': {
            'id': 'chart-1',
            'person_id': 'person-1',
            'clinic_id': 'clinic-1',
          },
          'doctor': {
            'id': 'doc-1',
            'clinic_id': 'clinic-1',
            'full_name': 'Maria Santos',
          },
          ...extra,
        };

    test('reads the note to the patient; a blank one is none', () {
      expect(Appointment.fromJson(row({'patient_note': 'Floss daily.'})).patientNote,
          'Floss daily.');
      expect(Appointment.fromJson(row({'patient_note': '  '})).patientNote,
          isNull);
    });

    test('reads an embedded visit note as an object or a one-element list', () {
      const note = {'body': 'No cavities.', 'updated_at': '2026-09-01T02:00:00Z'};
      expect(Appointment.fromJson(row({'visit_note': note})).visitNote?.body,
          'No cavities.');
      expect(Appointment.fromJson(row({'visit_note': [note]})).visitNote?.body,
          'No cavities.');
      expect(Appointment.fromJson(row({'visit_note': <dynamic>[]})).visitNote,
          isNull);
      expect(
          Appointment.fromJson(row({'visit_note': {'body': ''}})).visitNote,
          isNull);
      expect(Appointment.fromJson(row({})).visitNote, isNull);
    });
  });

  test('AppRole.seesClinicalNotes: doctors and admins only', () {
    expect(AppRole.doctor.seesClinicalNotes, isTrue);
    expect(AppRole.admin.seesClinicalNotes, isTrue);
    expect(AppRole.assistant.seesClinicalNotes, isFalse);
    expect(AppRole.patient.seesClinicalNotes, isFalse);
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

  group('currentClinicProvider is the clinic in the URL', () {
    final a = clinic('a'), b = clinic('b');

    ProviderContainer twoClinicAdmin() => appContainer(
          app: AppRole.admin,
          visible: [a, b],
          memberships: [staffAt('a', AppRole.admin), staffAt('b', AppRole.admin)],
        );

    void openClinic(ProviderContainer c, String id) =>
        c.read(routeClinicSlugProvider.notifier).set('clinic-$id');

    test('is null outside any clinic', () async {
      final container = twoClinicAdmin();
      await container.read(myClinicsProvider.future);
      expect(container.read(currentClinicIdProvider), isNull);
    });

    test('follows the slug', () async {
      final container = twoClinicAdmin();
      await container.read(myClinicsProvider.future);
      openClinic(container, 'a');
      expect(container.read(currentClinicIdProvider), 'a');
      openClinic(container, 'b');
      expect(container.read(currentClinicIdProvider), 'b');
    });

    test('is null at a clinic the app does not offer, never another one',
        () async {
      final container = appContainer(
        app: AppRole.admin,
        visible: [a, b],
        memberships: [staffAt('a', AppRole.admin), staffAt('b', AppRole.doctor)],
      );
      await container.read(myClinicsProvider.future);
      // B is visible to this account, but not as an admin.
      openClinic(container, 'b');
      expect(container.read(currentClinicIdProvider), isNull);
    });

    test('is null when the account belongs to no clinic', () async {
      final container = appContainer(app: AppRole.patient, visible: [a]);
      await container.read(myClinicsProvider.future);
      openClinic(container, 'a');
      expect(container.read(currentClinicProvider).value, isNull);
    });

    test('signed out, nothing is fetched and nothing is current', () async {
      final container = ProviderContainer(overrides: [
        appRoleProvider.overrideWithValue(AppRole.patient),
        currentUserIdProvider.overrideWithValue(null),
        // Would throw if asked: signed out must not reach the network.
        visibleClinicsProvider.overrideWith((ref) => throw StateError('fetched')),
      ]);
      addTearDown(container.dispose);
      expect(await container.read(myClinicsProvider.future), isEmpty);
    });
  });

  group('canSeeClinicalNotesProvider follows the role at the current clinic', () {
    final a = clinic('a'), b = clinic('b');

    Future<bool> canSee(ProviderContainer c, {String at = 'a'}) async {
      await c.read(myClinicsProvider.future);
      c.read(routeClinicSlugProvider.notifier).set('clinic-$at');
      return c.read(canSeeClinicalNotesProvider.future);
    }

    test('a doctor at the clinic can', () async {
      final c = appContainer(
        app: AppRole.doctor,
        visible: [a],
        memberships: [staffAt('a', AppRole.doctor)],
      );
      expect(await canSee(c), isTrue);
    });

    test('the front desk cannot', () async {
      final c = appContainer(
        app: AppRole.assistant,
        visible: [a],
        memberships: [staffAt('a', AppRole.assistant)],
      );
      expect(await canSee(c), isFalse);
    });

    test('an admin running the front desk can', () async {
      final c = appContainer(
        app: AppRole.assistant,
        visible: [a],
        memberships: [staffAt('a', AppRole.admin)],
      );
      expect(await canSee(c), isTrue);
    });

    test('a clinician role at another clinic does not carry over', () async {
      final c = appContainer(
        app: AppRole.assistant,
        visible: [a, b],
        memberships: [staffAt('a', AppRole.assistant), staffAt('b', AppRole.admin)],
      );
      expect(await canSee(c), isFalse);
      expect(await canSee(c, at: 'b'), isTrue);
    });

    test('never in the patient app, even for an account that is also staff',
        () async {
      final c = appContainer(
        app: AppRole.patient,
        visible: [a],
        charts: [chartAt('a')],
        memberships: [staffAt('a', AppRole.doctor)],
      );
      expect(await canSee(c), isFalse);
    });
  });

  group('staff codes', () {
    test('StaffInvite.fromJson reads a pending request', () {
      final i = StaffInvite.fromJson({
        'id': 'inv-1',
        'clinic_id': 'clinic-1',
        'role': 'doctor',
        'code': 'ABCD2345',
        'status': 'pending',
        'expires_at': '2026-09-22T00:00:00Z',
        'label': 'Dr Reyes',
        'redeemer_name': 'Ana Reyes',
        'redeemer_email': 'reyes@mail.com',
        'redeemed_at': '2026-09-16T01:00:00Z',
      });
      expect(i.role, AppRole.doctor);
      expect(i.status, StaffInviteStatus.pending);
      expect(i.applicant, 'Ana Reyes');
      expect(i.redeemedAt, isNotNull);
    });

    test('only an OPEN code past its expiry counts as expired', () {
      Map<String, dynamic> row(String status) => {
            'id': 'i',
            'clinic_id': 'c',
            'role': 'assistant',
            'code': 'ABCD2345',
            'status': status,
            'expires_at': '2026-09-01T00:00:00Z',
          };
      final later = DateTime.utc(2026, 9, 2);
      expect(StaffInvite.fromJson(row('open')).isExpired(later), isTrue);
      expect(StaffInvite.fromJson(row('pending')).isExpired(later), isFalse);
      expect(StaffInvite.fromJson(row('open')).applicant, 'Someone');
    });

    test('StaffRequest.fromJson reads the my_staff_requests row', () {
      final r = StaffRequest.fromJson({
        'id': 'inv-1',
        'clinic_name': 'D-Touch Dental Clinic',
        'role': 'assistant',
        'status': 'rejected',
        'redeemed_at': '2026-09-16T01:00:00Z',
        'decided_at': null,
      });
      expect(r.clinicName, 'D-Touch Dental Clinic');
      expect(r.status, StaffInviteStatus.rejected);
    });

    test('AppRole.takesStaffCodes: doctors and assistants only', () {
      expect(AppRole.doctor.takesStaffCodes, isTrue);
      expect(AppRole.assistant.takesStaffCodes, isTrue);
      expect(AppRole.admin.takesStaffCodes, isFalse);
      expect(AppRole.patient.takesStaffCodes, isFalse);
    });
  });

  group('branch admins', () {
    test('a branch-locked admin is not a full admin', () {
      final branch = ClinicMembership.fromJson({
        'profile_id': 'u',
        'clinic_id': 'c',
        'role': 'admin',
        'branch_locked': true,
      });
      expect(branch.isFullAdmin, isFalse);
      expect(branch.roleLabel, 'Branch admin');

      // A row selected without the column reads as a full admin.
      final full = ClinicMembership.fromJson(
          {'profile_id': 'u', 'clinic_id': 'c', 'role': 'admin'});
      expect(full.isFullAdmin, isTrue);
      expect(full.roleLabel, 'Administrator');
    });

    test('isFullAdminProvider follows the current clinic', () async {
      final a = clinic('a'), b = clinic('b');
      final c = appContainer(
        app: AppRole.admin,
        visible: [a, b],
        memberships: [
          staffAt('a', AppRole.admin),
          const ClinicMembership(
            profileId: 'u1',
            clinicId: 'b',
            role: AppRole.admin,
            branchLocked: true,
          ),
        ],
      );
      await c.read(myClinicsProvider.future);
      c.read(routeClinicSlugProvider.notifier).set('clinic-a');
      expect(c.read(isFullAdminProvider), isTrue);
      c.read(routeClinicSlugProvider.notifier).set('clinic-b');
      expect(c.read(isFullAdminProvider), isFalse);
    });
  });

  group('public clinic pages', () {
    test('ClinicPage.fromJson reads the clinic, services and doctors', () {
      final page = ClinicPage.fromJson({
        ...clinicJson('a'),
        'services': [
          {'id': 's1', 'clinic_id': 'a', 'name': 'Cleaning', 'duration_minutes': 45},
        ],
        'doctors': [
          {
            'id': 'd1',
            'clinic_id': 'a',
            'full_name': 'Ana Santos',
            'specialty': 'Orthodontics',
            'available_weekdays': [1, 2, 3, 4, 5],
          },
        ],
      });
      expect(page.clinic.slug, 'clinic-a');
      expect(page.clinic.joinCode, isNull);
      expect(page.services.single.durationMinutes, 45);
      expect(page.doctors.single.availableWeekdays, [1, 2, 3, 4, 5]);
      expect(page.doctors.single.availableTimeSlots, isEmpty);
    });

    test('a page without lists is still a page', () {
      final page = ClinicPage.fromJson(clinicJson('a'));
      expect(page.services, isEmpty);
      expect(page.doctors, isEmpty);
    });

    test('formatWeekdays reads the way a clinic would write it', () {
      expect(formatWeekdays([1, 2, 3, 4, 5]), 'Mon–Fri');
      expect(formatWeekdays([1, 3, 5]), 'Mon, Wed, Fri');
      expect(formatWeekdays([1, 2, 4, 5, 6]), 'Mon, Tue, Thu–Sat');
      expect(formatWeekdays([6, 7]), 'Sat, Sun');
      expect(formatWeekdays([1, 2, 3, 4, 5, 6, 7]), 'Every day');
      expect(formatWeekdays([5, 1, 3, 3, 9]), 'Mon, Wed, Fri');
      expect(formatWeekdays([]), '');
    });

    test('each app lands on its own home tab', () {
      expect(clinicHome('dtouchdental', AppRole.patient), '/dtouchdental/home');
      expect(clinicHome('dtouchdental', AppRole.doctor), '/dtouchdental/schedule');
      expect(clinicHome('dtouchdental', AppRole.assistant), '/dtouchdental/check-in');
      expect(clinicHome('dtouchdental', AppRole.admin), '/dtouchdental/dashboard');
    });
  });
}
