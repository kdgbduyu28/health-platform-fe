import { type AppRole, appRoles, homeSubpath, isGrantedBy, seesClinicalNotes, takesStaffCodes } from '../src/models/app_role';
import { Appointment } from '../src/models/appointment';
import { appointmentStatusFromWire, appointmentStatuses, holdsTime, patientCanCancel, staffCanCancel } from '../src/models/appointment_status';
import { Clinic, parseHexColor } from '../src/models/clinic';
import { ClinicPage } from '../src/models/clinic_page';
import { describeTimeSlots, formatClock, formatWeekdays, generateTimeSlots, parseClock, workingHoursOf } from '../src/models/doctor';
import { Patient } from '../src/models/patient';
import { Service } from '../src/models/service';
import { StaffInvite, StaffRequest } from '../src/models/staff_invite';
import { TimeOff } from '../src/models/time_off';
import { ClinicMembership, eligibleClinicIds } from '../src/models/membership';

function clinicJson(id: string, opts: { type?: string; seedColor?: string | null; iconName?: string | null; embedType?: boolean } = {}) {
  const { type = 'dental', seedColor = null, iconName = 'medical_services', embedType = true } = opts;
  return {
    id,
    name: `Clinic ${id}`,
    slug: `clinic-${id}`,
    type,
    seed_color: seedColor,
    ...(embedType ? { clinic_type: { display_name: 'Dental', icon_name: iconName } } : {}),
  };
}

const chartAt = (clinicId: string) => new Patient(`chart-${clinicId}`, 'person-1', clinicId, 'Juan dela Cruz', '0917', '');
const staffAt = (clinicId: string, role: AppRole, branchLocked = false) =>
  ClinicMembership.fromJson({ profile_id: 'u1', clinic_id: clinicId, role, branch_locked: branchLocked });

describe('Clinic.fromJson', () => {
  test('reads the embedded vertical and brand colour', () => {
    const c = Clinic.fromJson(clinicJson('a', { seedColor: '#654F3B' }));
    expect(c.typeSlug).toBe('dental');
    expect(c.typeName).toBe('Dental');
    expect(c.icon).toBe('medical-services');
    expect(c.seedColor).toBe('#654F3B');
  });

  test('an unknown vertical icon falls back instead of failing', () => {
    expect(Clinic.fromJson(clinicJson('a', { iconName: 'not_an_icon' })).icon).toBe('local-hospital');
  });

  test('without the embed, the slug stands in for the vertical name', () => {
    const c = Clinic.fromJson(clinicJson('a', { type: 'derma', embedType: false }));
    expect(c.typeName).toBe('derma');
    expect(c.icon).toBe('local-hospital');
  });
});

describe('hex colours', () => {
  test('are normalised to upper case', () => {
    expect(parseHexColor('#1f8a70')).toBe('#1F8A70');
  });

  test('malformed values are null, not a broken theme', () => {
    expect(parseHexColor(null)).toBeNull();
    expect(parseHexColor('654F3B')).toBeNull();
    expect(parseHexColor('#FFF')).toBeNull();
    expect(parseHexColor('#GGGGGG')).toBeNull();
  });
});

describe('Patient.fromJson', () => {
  test('flattens the person onto the chart', () => {
    const p = Patient.fromJson({
      id: 'chart-1',
      person_id: 'person-1',
      clinic_id: 'clinic-1',
      person: { full_name: 'Maria Reyes', phone: '0928', email: null, date_of_birth: '1985-07-22' },
    });
    expect(p.id).toBe('chart-1');
    expect(p.clinicId).toBe('clinic-1');
    expect(p.name).toBe('Maria Reyes');
    expect(p.email).toBe('');
    expect(p.initials).toBe('MR');
    expect(p.dateOfBirth).toEqual(new Date(1985, 6, 22));
  });

  test('a missing person degrades to blanks rather than a crash', () => {
    const p = Patient.fromJson({ id: 'c', person_id: 'p', clinic_id: 'k' });
    expect(p.name).toBe('');
    expect(p.initials).toBe('?');
  });

  test('search matches a name, or a phone however it is typed', () => {
    const p = Patient.fromJson({ id: 'c', person_id: 'p', clinic_id: 'k', person: { full_name: 'Maria Reyes', phone: '0928-123-4567' } });
    expect(p.matches('')).toBe(true);
    expect(p.matches('reyes')).toBe(true);
    expect(p.matches('928 123')).toBe(true);
    expect(p.matches('juan')).toBe(false);
    // The front desk's duplicate check: same number, different formatting.
    expect(p.hasPhone('+63 928 123 4567')).toBe(true);
    expect(p.hasPhone('09281234560')).toBe(false);
    expect(p.hasPhone('')).toBe(false);
  });
});

function appointmentRow(extra: Record<string, unknown> = {}) {
  return {
    id: 'appt-1',
    clinic_id: 'clinic-1',
    scheduled_at: '2026-09-14T01:00:00Z',
    service_name: 'Teeth Cleaning',
    status: 'completed',
    patient: { id: 'chart-1', person_id: 'person-1', clinic_id: 'clinic-1', person: { full_name: 'Juan dela Cruz' } },
    doctor: { id: 'doc-1', clinic_id: 'clinic-1', full_name: 'Maria Santos' },
    ...extra,
  };
}

test('Appointment.fromJson reads the clinic id and nested chart', () => {
  const a = Appointment.fromJson(appointmentRow({ status: 'pending' }));
  expect(a.clinicId).toBe('clinic-1');
  expect(a.patient.name).toBe('Juan dela Cruz');
  expect(a.doctor.clinicId).toBe('clinic-1');
  expect(a.status).toBe('pending');
});

describe('Appointment notes', () => {
  test('reads the note to the patient; a blank one is none', () => {
    expect(Appointment.fromJson(appointmentRow({ patient_note: 'Floss daily.' })).patientNote).toBe('Floss daily.');
    expect(Appointment.fromJson(appointmentRow({ patient_note: '  ' })).patientNote).toBeNull();
  });

  test('reads an embedded visit note as an object or a one-element list', () => {
    const note = { body: 'No cavities.', updated_at: '2026-09-01T02:00:00Z' };
    expect(Appointment.fromJson(appointmentRow({ visit_note: note })).visitNote?.body).toBe('No cavities.');
    expect(Appointment.fromJson(appointmentRow({ visit_note: [note] })).visitNote?.body).toBe('No cavities.');
    expect(Appointment.fromJson(appointmentRow({ visit_note: [] })).visitNote).toBeNull();
    expect(Appointment.fromJson(appointmentRow({ visit_note: { body: '' } })).visitNote).toBeNull();
    expect(Appointment.fromJson(appointmentRow()).visitNote).toBeNull();
  });
});

test('seesClinicalNotes: doctors and admins only', () => {
  expect(seesClinicalNotes('doctor')).toBe(true);
  expect(seesClinicalNotes('admin')).toBe(true);
  expect(seesClinicalNotes('assistant')).toBe(false);
  expect(seesClinicalNotes('patient')).toBe(false);
});

test('isGrantedBy: which membership opens which app', () => {
  expect(isGrantedBy('doctor', 'doctor')).toBe(true);
  expect(isGrantedBy('doctor', 'admin')).toBe(false);
  expect(isGrantedBy('assistant', 'assistant')).toBe(true);
  expect(isGrantedBy('assistant', 'admin')).toBe(true);
  expect(isGrantedBy('assistant', 'doctor')).toBe(false);
  expect(isGrantedBy('admin', 'admin')).toBe(true);
  expect(isGrantedBy('admin', 'assistant')).toBe(false);
  expect(isGrantedBy('patient', 'admin')).toBe(false);
});

describe('eligibleClinicIds narrows clinics to the running app', () => {
  test('patient app: only clinics where they hold a chart', () => {
    expect(eligibleClinicIds('patient', [chartAt('a'), chartAt('c')], [staffAt('b', 'doctor')])).toEqual(['a', 'c']);
  });

  test('doctor app: excludes a clinic where they are only a patient', () => {
    // One account: doctor at A, patient at B. RLS returns both clinics.
    expect(eligibleClinicIds('doctor', [chartAt('b')], [staffAt('a', 'doctor')])).toEqual(['a']);
  });

  test('doctor app: an admin role elsewhere does not count', () => {
    expect(eligibleClinicIds('doctor', [], [staffAt('a', 'doctor'), staffAt('b', 'admin')])).toEqual(['a']);
  });

  test('assistant app: admins may run the front desk', () => {
    expect(eligibleClinicIds('assistant', [], [staffAt('a', 'assistant'), staffAt('b', 'admin'), staffAt('c', 'doctor')])).toEqual(['a', 'b']);
  });

  test('an account attached to nothing gets nothing', () => {
    expect(eligibleClinicIds('admin', [], [])).toEqual([]);
  });
});

describe('staff codes', () => {
  test('StaffInvite.fromJson reads a pending request', () => {
    const i = StaffInvite.fromJson({
      id: 'inv-1',
      clinic_id: 'clinic-1',
      role: 'doctor',
      code: 'ABCD2345',
      status: 'pending',
      expires_at: '2026-09-22T00:00:00Z',
      label: 'Dr Reyes',
      redeemer_name: 'Ana Reyes',
      redeemer_email: 'reyes@mail.com',
      redeemed_at: '2026-09-16T01:00:00Z',
    });
    expect(i.role).toBe('doctor');
    expect(i.status).toBe('pending');
    expect(i.applicant).toBe('Ana Reyes');
    expect(i.redeemedAt).not.toBeNull();
  });

  test('only an OPEN code past its expiry counts as expired', () => {
    const row = (status: string) => ({ id: 'i', clinic_id: 'c', role: 'assistant', code: 'ABCD2345', status, expires_at: '2026-09-01T00:00:00Z' });
    const later = new Date(Date.UTC(2026, 8, 2));
    expect(StaffInvite.fromJson(row('open')).isExpired(later)).toBe(true);
    expect(StaffInvite.fromJson(row('pending')).isExpired(later)).toBe(false);
    expect(StaffInvite.fromJson(row('open')).applicant).toBe('Someone');
  });

  test('StaffRequest.fromJson reads the my_staff_requests row', () => {
    const r = StaffRequest.fromJson({
      id: 'inv-1',
      clinic_name: 'D-Touch Dental Clinic',
      role: 'assistant',
      status: 'rejected',
      redeemed_at: '2026-09-16T01:00:00Z',
      decided_at: null,
    });
    expect(r.clinicName).toBe('D-Touch Dental Clinic');
    expect(r.status).toBe('rejected');
  });

  test('takesStaffCodes: doctors and assistants only', () => {
    expect(appRoles.filter(takesStaffCodes)).toEqual(['doctor', 'assistant']);
  });
});

test('a branch-locked admin is not a full admin', () => {
  const branch = staffAt('c', 'admin', true);
  expect(branch.isFullAdmin).toBe(false);
  expect(branch.roleLabel).toBe('Branch admin');
  // A row selected without the column reads as a full admin.
  const full = ClinicMembership.fromJson({ profile_id: 'u', clinic_id: 'c', role: 'admin' });
  expect(full.isFullAdmin).toBe(true);
  expect(full.roleLabel).toBe('Administrator');
});

describe('public clinic pages', () => {
  test('ClinicPage.fromJson reads the clinic, services and doctors', () => {
    const page = ClinicPage.fromJson({
      ...clinicJson('a'),
      services: [{ id: 's1', clinic_id: 'a', name: 'Cleaning', duration_minutes: 45 }],
      doctors: [{ id: 'd1', clinic_id: 'a', full_name: 'Ana Santos', specialty: 'Orthodontics', available_weekdays: [1, 2, 3, 4, 5] }],
    });
    expect(page.clinic.slug).toBe('clinic-a');
    expect(page.clinic.joinCode).toBeNull();
    expect(page.services[0].durationMinutes).toBe(45);
    expect(page.doctors[0].availableWeekdays).toEqual([1, 2, 3, 4, 5]);
    expect(page.doctors[0].availableTimeSlots).toEqual([]);
  });

  test('a page without lists is still a page', () => {
    const page = ClinicPage.fromJson(clinicJson('a'));
    expect(page.services).toEqual([]);
    expect(page.doctors).toEqual([]);
  });

  test('formatWeekdays reads the way a clinic would write it', () => {
    expect(formatWeekdays([1, 2, 3, 4, 5])).toBe('Mon–Fri');
    expect(formatWeekdays([1, 3, 5])).toBe('Mon, Wed, Fri');
    expect(formatWeekdays([1, 2, 4, 5, 6])).toBe('Mon, Tue, Thu–Sat');
    expect(formatWeekdays([6, 7])).toBe('Sat, Sun');
    expect(formatWeekdays([1, 2, 3, 4, 5, 6, 7])).toBe('Every day');
    expect(formatWeekdays([5, 1, 3, 3, 9])).toBe('Mon, Wed, Fri');
    expect(formatWeekdays([])).toBe('');
  });

  test('each app lands on its own home tab', () => {
    expect(homeSubpath('patient')).toBe('/home');
    expect(homeSubpath('doctor')).toBe('/schedule');
    expect(homeSubpath('assistant')).toBe('/check-in');
    expect(homeSubpath('admin')).toBe('/dashboard');
  });
});

describe('visit flow', () => {
  test('every status round-trips through its database label', () => {
    for (const s of appointmentStatuses) expect(appointmentStatusFromWire(s)).toBe(s);
  });

  test('cancelled visits and no-shows free the doctor; nothing else does', () => {
    expect(appointmentStatuses.filter((s) => !holdsTime(s))).toEqual(['cancelled', 'no_show']);
  });

  test('a patient cancels only before arriving; the desk until the consult', () => {
    expect(appointmentStatuses.filter(patientCanCancel)).toEqual(['pending', 'confirmed']);
    expect(appointmentStatuses.filter(staffCanCancel)).toEqual(['pending', 'confirmed', 'arrived']);
  });

  test('Appointment.fromJson reads the length and the step times', () => {
    const a = Appointment.fromJson(
      appointmentRow({
        scheduled_at: '2026-10-05T01:00:00Z',
        service_name: 'Root Canal',
        status: 'in_consultation',
        duration_minutes: 90,
        arrived_at: '2026-10-05T00:55:00Z',
        started_at: '2026-10-05T01:02:00Z',
      }),
    );
    expect(a.status).toBe('in_consultation');
    expect(a.endsAt.getTime() - a.dateTime.getTime()).toBe(90 * 60_000);
    expect(a.arrivedAt).not.toBeNull();
    expect(a.startedAt?.toISOString()).toBe('2026-10-05T01:02:00.000Z');
    expect(a.completedAt).toBeNull();
  });
});

describe('working hours', () => {
  test('first, last and step become the start times', () => {
    expect(generateTimeSlots({ first: 8 * 60, last: 9 * 60 + 30, step: 30 })).toEqual(['08:00', '08:30', '09:00', '09:30']);
    expect(generateTimeSlots({ first: 600, last: 540, step: 30 })).toEqual([]);
  });

  test('an even list is read back as its pattern', () => {
    const hours = workingHoursOf(['09:30', '08:00', '08:30', '09:00', '10:00']);
    expect(hours).toEqual({ first: 8 * 60, last: 10 * 60, step: 30 });
    expect(generateTimeSlots(hours!).length).toBe(5);
  });

  test('a list with a lunch break has no pattern, and says so', () => {
    const slots = ['09:00', '09:30', '10:00', '13:00', '13:30'];
    expect(workingHoursOf(slots)).toBeNull();
    expect(describeTimeSlots(slots)).toBe('5 set times');
  });

  test('described the way a clinic would say it', () => {
    expect(describeTimeSlots(['08:00', '08:30', '09:00'])).toBe('08:00–09:00, every 30 min');
    expect(describeTimeSlots(['14:00'])).toBe('At 14:00');
    expect(describeTimeSlots([])).toBe('No times set');
  });

  test('clock strings are checked like the database checks them', () => {
    expect(parseClock('07:05')).toBe(425);
    expect(parseClock('24:00')).toBeNull();
    expect(parseClock('9:00')).toBeNull();
    expect(formatClock(425)).toBe('07:05');
  });
});

describe('services', () => {
  const priced = (p: number | null) => Service.fromJson({ id: 's', clinic_id: 'c', name: 'x', duration_minutes: 30, price: p });

  test('prices print as pesos, grouped, without needless decimals', () => {
    expect(priced(1500).priceLabel).toBe('₱1,500');
    expect(priced(1250.5).priceLabel).toBe('₱1,250.50');
    expect(priced(350).priceLabel).toBe('₱350');
    expect(priced(1234567).priceLabel).toBe('₱1,234,567');
    expect(priced(null).priceLabel).toBeNull();
  });

  test('a price arrives from PostgREST as a number or not at all', () => {
    const s = Service.fromJson({ id: 's', clinic_id: 'c', name: 'Root Canal', duration_minutes: 90, price: 1500, is_active: false });
    expect(s.price).toBe(1500);
    expect(s.isActive).toBe(false);
  });

  test('TimeOff.fromJson: a null doctor is a clinic closure', () => {
    const t = TimeOff.fromJson({ id: 't', clinic_id: 'c', doctor_id: null, starts_on: '2026-12-24', ends_on: '2026-12-26', reason: 'Christmas' });
    expect(t.isClosure).toBe(true);
    expect(t.startsOn).toEqual(new Date(2026, 11, 24));
    expect(t.endsOn).toEqual(new Date(2026, 11, 26));
  });
});
