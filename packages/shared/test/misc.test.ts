import { privacyPolicy, termsAndConditions } from '../src/legal/documents';
import { type LegalDocument, legalDated } from '../src/legal/legal_content';
import { AppNotification, notificationTopicsFor } from '../src/models/app_notification';
import { type AppRole, appRoles } from '../src/models/app_role';
import { Appointment } from '../src/models/appointment';
import type { AppointmentStatus } from '../src/models/appointment_status';
import { boardColumnOf, boardNextStep } from '../src/models/board';
import { Doctor } from '../src/models/doctor';
import { BillingSummary, Invoice, invoiceStatusFromWire, paymentMethodFromWire, paymentMethods, wantsReference } from '../src/models/invoice';
import { formatPeso, parseMoney } from '../src/models/money';
import { Patient, PatientPage } from '../src/models/patient';
import { PatientIntake } from '../src/models/patient_intake';
import { patientRemarks } from '../src/models/patient_remarks';
import { AppPreferences } from '../src/state/preferences';

const patient = new Patient('chart-1', 'person-1', 'c1', 'Ana Cruz', '0917 555 0101', '');
const doctor = new Doctor('d1', 'c1', 'Maria Santos', 'General Dentistry', [1, 2, 3, 4, 5], ['09:00']);
const visit = (id: string, at: Date, status: AppointmentStatus, who: Patient = patient) => new Appointment(id, 'c1', who, doctor, at, 'Cleaning', status);

const bill = (status: string, total: number, paid: number, issued: Date) =>
  Invoice.fromJson({
    id: `inv-${total}-${paid}`,
    clinic_id: 'c1',
    patient_id: 'chart-1',
    status,
    subtotal: total,
    discount_amount: 0,
    total,
    amount_paid: paid,
    created_at: issued.toISOString(),
    issued_at: issued.toISOString(),
  });

// ── Patient list ────────────────────────────────────────────────────────────

describe('PatientPage.fromJson', () => {
  test('reads the remarks, the counts and the visit details', () => {
    const page = PatientPage.fromJson({
      total: 1,
      counts: { all: 40, recall: 3, balance: 2, pedia: 5 },
      patients: [
        {
          id: 'chart-1',
          person_id: 'person-1',
          clinic_id: 'c1',
          person: { full_name: 'Ana Cruz', phone: null, email: null },
          completed_visits: 4,
          first_visit_at: '2025-01-10T01:00:00+00:00',
          last_visit_at: '2026-02-01T01:00:00+00:00',
          last_visit_status: 'no_show',
          last_visit_service: 'Filling',
          last_visit_doctor: 'Maria Santos',
          balance: 1500.5,
          planned_count: 2,
          age: 9,
          flags: ['balance', 'attention', 'pedia', 'something_new'],
          attention: ['no_show', 'unbooked_plan'],
        },
      ],
    });
    expect(page.total).toBe(1);
    expect(page.all).toBe(40);
    expect(page.counts.get('recall')).toBe(3);
    expect(page.counts.has('attention')).toBe(false);
    const l = page.patients[0];
    expect(l.completedVisits).toBe(4);
    expect(l.firstVisitAt).not.toBeNull();
    expect(l.lastVisitMissed).toBe(true);
    expect(l.lastVisitDoctor).toBe('Maria Santos');
    expect(l.balance).toBe(1500.5);
    expect(l.age).toBe(9);
    // An unknown remark from a newer database is skipped, not a crash.
    expect(l.flags).toEqual(new Set(['balance', 'attention', 'pedia']));
    expect(l.attention).toEqual(new Set(['no_show', 'unbooked_plan']));
  });

  test('an older database without remarks still parses', () => {
    const page = PatientPage.fromJson({
      total: 1,
      patients: [{ id: 'chart-1', person_id: 'person-1', clinic_id: 'c1', person: { full_name: 'Ana Cruz' }, completed_visits: 1 }],
    });
    expect(page.all).toBeNull();
    expect(page.patients[0].flags.size).toBe(0);
    expect(page.patients[0].balance).toBe(0);
  });
});

describe('patientRemarks mirrors search_patients', () => {
  const now = new Date(2026, 8, 23, 10);
  const remarks = (opts: { patient?: Patient; visits?: Appointment[]; invoices?: Invoice[]; planned?: number; recallMonths?: number } = {}) =>
    patientRemarks({
      patient: opts.patient ?? patient,
      visits: opts.visits ?? [],
      invoices: opts.invoices ?? [],
      plannedCount: opts.planned ?? 0,
      recallMonths: opts.recallMonths ?? 6,
      now,
    });

  test('seen 8 months ago, nothing booked: for recall', () => {
    const old = visit('a', new Date(2026, 0, 20), 'completed');
    expect(remarks({ visits: [old] }).flags.has('recall')).toBe(true);
    expect(remarks({ visits: [old], recallMonths: 12 }).flags.has('recall')).toBe(false);
    const booked = visit('b', new Date(2026, 9, 1), 'confirmed');
    expect(remarks({ visits: [old, booked] }).flags.has('recall')).toBe(false);
  });

  test('an issued bill with money left is a balance; a draft is not', () => {
    const issued = bill('issued', 1500, 500, new Date(2026, 8, 20));
    const draft = bill('draft', 900, 0, new Date(2026, 8, 20));
    expect(remarks({ invoices: [issued] }).flags.has('balance')).toBe(true);
    expect(remarks({ invoices: [issued] }).attention.size).toBe(0);
    expect(remarks({ invoices: [draft] }).flags.has('balance')).toBe(false);
  });

  test('unpaid 30+ days, a missed last visit, or an unbooked plan: attention', () => {
    const overdue = bill('issued', 1500, 0, new Date(2026, 7, 1));
    const missed = visit('m', new Date(2026, 8, 1), 'no_show');
    const r = remarks({ invoices: [overdue], visits: [missed], planned: 2 });
    expect(r.flags.has('attention')).toBe(true);
    expect(r.attention).toEqual(new Set(['overdue_balance', 'no_show', 'unbooked_plan']));
  });

  test('no phone and no email; pedia and adult by age', () => {
    const nobody = new Patient('chart-2', 'person-2', 'c1', 'Ben', ' ', '');
    expect(remarks({ patient: nobody }).flags).toEqual(new Set(['no_contact']));
    const child = new Patient('chart-3', 'person-3', 'c1', 'Lia', '0917', '', new Date(new Date().getFullYear() - 10, 0, 1));
    expect(remarks({ patient: child }).flags).toEqual(new Set(['pedia']));
  });
});

// ── Board ───────────────────────────────────────────────────────────────────

describe('board', () => {
  test('each status has one column; closed visits have none', () => {
    expect(boardColumnOf('pending')).toBe('upcoming');
    expect(boardColumnOf('confirmed')).toBe('planned');
    expect(boardColumnOf('arrived')).toBe('in_progress');
    expect(boardColumnOf('in_consultation')).toBe('in_progress');
    expect(boardColumnOf('completed')).toBe('completed');
    expect(boardColumnOf('cancelled')).toBeNull();
    expect(boardColumnOf('no_show')).toBeNull();
  });

  const to = (s: AppointmentStatus, app: AppRole, clinician: boolean) => boardNextStep(visit('a', new Date(), s), app, clinician)?.to ?? null;

  test('the front desk confirms, checks in and marks done, but never starts', () => {
    expect(to('pending', 'assistant', false)).toBe('confirmed');
    expect(to('confirmed', 'assistant', false)).toBe('arrived');
    expect(to('arrived', 'assistant', false)).toBe('completed');
    expect(to('in_consultation', 'assistant', false)).toBe('completed');
  });

  test('an admin at the desk can also start and complete', () => {
    expect(to('arrived', 'assistant', true)).toBe('in_consultation');
    expect(to('in_consultation', 'admin', true)).toBe('completed');
    // The admin app checks a planned visit in rather than starting it.
    expect(to('confirmed', 'admin', true)).toBe('arrived');
  });

  test('a doctor starts a planned visit straight away', () => {
    expect(to('confirmed', 'doctor', true)).toBe('in_consultation');
    expect(to('in_consultation', 'doctor', true)).toBe('completed');
  });

  test('nothing moves on from a finished visit', () => {
    for (const s of ['completed', 'cancelled', 'no_show'] as AppointmentStatus[]) expect(to(s, 'admin', true)).toBeNull();
  });
});

// ── Preferences ─────────────────────────────────────────────────────────────

describe('preferences', () => {
  test('theme follows the device until chosen, and is remembered', () => {
    const prefs = AppPreferences.memory();
    expect(prefs.themeMode).toBe('system');
    prefs.setThemeMode('dark');
    expect(prefs.themeMode).toBe('dark');
    // Back to the default stores nothing.
    prefs.setThemeMode('system');
    expect(prefs.getString('display.theme')).toBeNull();
  });

  test('the calendar view and list-or-board are remembered per app', () => {
    const prefs = AppPreferences.memory();
    expect(prefs.calendarView('assistant')).toBeNull();
    prefs.setCalendarView('assistant', 'day');
    expect(prefs.calendarView('assistant')).toBe('day');
    expect(prefs.calendarView('admin')).toBeNull();

    expect(prefs.appointmentView('doctor')).toBe('list');
    prefs.setAppointmentView('doctor', 'board');
    expect(prefs.appointmentView('doctor')).toBe('board');
    expect(prefs.appointmentView('assistant')).toBe('list');
  });

  test('text size is remembered, and reset puts everything back', () => {
    const prefs = AppPreferences.memory();
    prefs.setTextSize('larger');
    prefs.setThemeMode('light');
    prefs.setLastClinicSlug('patient', 'dtouchdental');
    expect(prefs.textSize).toBe('larger');
    prefs.resetDisplay();
    expect(prefs.textSize).toBe('normal');
    expect(prefs.themeMode).toBe('system');
    // Not a display setting: where the app opens is left alone.
    expect(prefs.lastClinicSlug('patient')).toBe('dtouchdental');
  });

  test('tooth numbering is FDI until chosen; the last clinic is per app', () => {
    const prefs = AppPreferences.memory();
    expect(prefs.toothNumbering).toBe('fdi');
    prefs.setToothNumbering('universal');
    expect(prefs.toothNumbering).toBe('universal');
    prefs.setLastClinicSlug('doctor', 'dtouchdental');
    expect(prefs.lastClinicSlug('doctor')).toBe('dtouchdental');
    expect(prefs.lastClinicSlug('patient')).toBeNull();
  });

  test('every app has notification topics, none twice', () => {
    for (const app of appRoles) {
      const kinds = notificationTopicsFor(app).map((t) => t.kind);
      expect(kinds.length, app).toBeGreaterThan(0);
      expect(new Set(kinds).size, app).toBe(kinds.length);
    }
  });
});

// ── Legal documents ─────────────────────────────────────────────────────────

const text = (d: LegalDocument) => [d.intro, ...d.sections.flatMap((s) => [s.heading, ...s.body])].join(' ');

describe('the legal documents', () => {
  test('are dated, as the database takes it', () => {
    for (const d of [privacyPolicy, termsAndConditions]) {
      expect(d.version).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect(legalDated(d)).toBe('September 30, 2026');
    }
    // The ids the database's `document` column accepts.
    expect(privacyPolicy.id).toBe('privacy');
    expect(termsAndConditions.id).toBe('terms');
  });

  test('name the operator and where to write', () => {
    for (const d of [privacyPolicy, termsAndConditions]) {
      expect(text(d)).toContain('D-Touch Dental Clinic');
      expect(text(d)).toContain('dtouchdental@gmail.com');
    }
  });

  test('the Privacy Policy says what the law asks it to', () => {
    expect(privacyPolicy.sections.map((s) => s.heading)).toEqual(expect.arrayContaining(['Who we are', 'What we collect', 'How long we keep it', 'Your rights']));
    const t = text(privacyPolicy);
    expect(t).toContain('Republic Act No. 10173');
    // Data leaves the country: that must be said.
    expect(t).toContain('Mumbai, India');
    expect(t).toContain('72 hours');
    expect(t).toContain('privacy.gov.ph');
  });

  test('the Terms say the apps are not for emergencies', () => {
    expect(text(termsAndConditions)).toContain('911');
  });
});

// ── Billing and notifications ───────────────────────────────────────────────

const person = { id: 'person-1', full_name: 'Juan dela Cruz', phone: '0917', email: 'juan@email.com' };
const invoiceJson = (status = 'issued') => ({
  id: 'inv-1',
  clinic_id: 'c1',
  patient_id: 'chart-1',
  appointment_id: 'appt-1',
  number: status === 'draft' ? null : 'INV-000042',
  status,
  subtotal: '1500.00',
  discount_amount: 0,
  discount_reason: null,
  total: 1500,
  amount_paid: 500,
  balance: 1000,
  notes: null,
  created_at: '2026-09-24T01:00:00Z',
  issued_at: status === 'draft' ? null : '2026-09-24T02:00:00Z',
  voided_at: null,
  void_reason: null,
  items: [{ id: 'line-1', description: 'Root Canal', quantity: 1, unit_price: 1500, amount: 1500, service_id: 's1' }],
  payments: [
    { id: 'pay-2', amount: 200, method: 'gcash', reference: 'GC-1', received_at: '2026-09-24T04:00:00Z', voided_at: '2026-09-24T05:00:00Z', void_reason: 'Wrong amount' },
    { id: 'pay-1', amount: '500.00', method: 'cash', reference: null, received_at: '2026-09-24T03:00:00Z', voided_at: null, void_reason: null },
  ],
  patient: { id: 'chart-1', person_id: 'person-1', clinic_id: 'c1', person },
  appointment: { service_name: 'Root Canal', scheduled_at: '2026-09-24T01:00:00Z' },
});

describe('billing', () => {
  test('pesos group thousands and drop whole centavos', () => {
    expect(formatPeso(1500)).toBe('₱1,500');
    expect(formatPeso(1234567.5)).toBe('₱1,234,567.50');
    expect(formatPeso(0)).toBe('₱0');
  });

  test('parseMoney takes numbers and numeric strings', () => {
    expect(parseMoney('1500.00')).toBe(1500);
    expect(parseMoney(12)).toBe(12);
    expect(parseMoney(null)).toBe(0);
  });

  test('an invoice reads totals, lines, payments and embeds', () => {
    const v = Invoice.fromJson(invoiceJson());
    expect(v.status).toBe('issued');
    expect(v.label).toBe('INV-000042');
    expect(v.subtotal).toBe(1500);
    expect(v.balance).toBe(1000);
    expect(v.isOpen).toBe(true);
    expect(v.items[0].amount).toBe(1500);
    expect(v.patient?.name).toBe('Juan dela Cruz');
    expect(v.title).toBe('Root Canal');
  });

  test('payments run oldest first, with voided ones kept apart', () => {
    const v = Invoice.fromJson(invoiceJson());
    expect(v.payments.map((p) => p.id)).toEqual(['pay-1', 'pay-2']);
    expect(v.activePayments.map((p) => p.id)).toEqual(['pay-1']);
    expect(v.payments[1].method).toBe('gcash');
    expect(v.payments[1].isVoid).toBe(true);
  });

  test('a voided bill is closed; a draft has no number yet', () => {
    expect(invoiceStatusFromWire('void')).toBe('void');
    expect(Invoice.fromJson(invoiceJson('void')).isOpen).toBe(false);
    const draft = Invoice.fromJson(invoiceJson('draft'));
    expect(draft.isDraft).toBe(true);
    expect(draft.label).toBe('Draft');
  });

  test('every payment method round-trips its wire name', () => {
    for (const m of paymentMethods) expect(paymentMethodFromWire(m)).toBe(m);
    expect(paymentMethods).toContain('bank_transfer');
    expect(wantsReference('cash')).toBe(false);
  });

  test('BillingSummary reads takings by method', () => {
    const s = BillingSummary.fromJson({ collected: 500, by_method: { gcash: 300, cash: '200.00' }, billed: 1500, outstanding: 1000, unpaid_count: 1, draft_count: 0 });
    expect(s.byMethod.get('gcash')).toBe(300);
    expect(s.byMethod.get('cash')).toBe(200);
    expect(s.outstanding).toBe(1000);
  });
});

describe('rescheduling', () => {
  const json = (status: string, from: string | null = null) => ({
    id: 'a1',
    clinic_id: 'c1',
    patient: { id: 'chart-1', person_id: 'person-1', clinic_id: 'c1', person },
    doctor: { id: 'd1', clinic_id: 'c1', full_name: 'Maria Santos', specialty: 'General Dentistry' },
    scheduled_at: '2030-01-07T01:00:00Z',
    service_name: 'Check-up',
    status,
    rescheduled_from: from,
    reschedule_count: from == null ? 0 : 1,
  });

  test('carries where it was moved from', () => {
    const a = Appointment.fromJson(json('pending', '2030-01-06T01:00:00Z'));
    expect(a.rescheduledFrom?.toISOString()).toBe('2030-01-06T01:00:00.000Z');
    expect(a.rescheduleCount).toBe(1);
  });

  test('only a visit that has not started can move', () => {
    expect(Appointment.fromJson(json('pending')).canReschedule).toBe(true);
    expect(Appointment.fromJson(json('confirmed')).canReschedule).toBe(true);
    expect(Appointment.fromJson(json('arrived')).canReschedule).toBe(false);
    expect(Appointment.fromJson(json('cancelled')).canReschedule).toBe(false);
  });
});

test('AppNotification.fromJson', () => {
  const n = AppNotification.fromJson({
    id: 'n1',
    app: 'patient',
    kind: 'visit_confirmed',
    title: 'Visit confirmed',
    body: 'Check-up on Mon',
    link: '/dtouchdental/appointments/a1',
    clinic_id: 'c1',
    appointment_id: 'a1',
    created_at: '2026-09-24T01:00:00Z',
    read_at: null,
  });
  expect(n.app).toBe('patient');
  expect(n.isRead).toBe(false);
  expect(n.link).toBe('/dtouchdental/appointments/a1');
});

// ── Patient information form ────────────────────────────────────────────────

describe('patient information form', () => {
  const chart = (intake: unknown, embed = true) => ({
    id: 'c1',
    person_id: 'p1',
    clinic_id: 'dt',
    person: { full_name: 'Ana', sex: 'female', address: 'Pasig' },
    ...(embed ? { intake } : {}),
  });

  test('a chart knows whether its form is filled in, when asked', () => {
    expect(Patient.fromJson(chart(null, false)).hasIntake).toBeNull();
    expect(Patient.fromJson(chart(null)).hasIntake).toBe(false);
    expect(Patient.fromJson(chart([])).hasIntake).toBe(false);
    expect(Patient.fromJson(chart([{ updated_at: 'x' }])).hasIntake).toBe(true);
    expect(Patient.fromJson(chart({ updated_at: 'x' })).hasIntake).toBe(true);
  });

  test("the person's new details come through", () => {
    const p = Patient.fromJson(chart(null));
    expect(p.sex).toBe('female');
    expect(p.address).toBe('Pasig');
  });

  const intakeRow = (extra: Record<string, unknown> = {}) => ({
    patient_id: 'c1',
    under_treatment: false,
    takes_medications: false,
    consent_at: '2026-09-22T01:00:00Z',
    signed_name: 'Ana',
    source: 'patient_app',
    updated_at: '2026-09-22T01:00:00Z',
    ...extra,
  });

  test('an allergy this build does not know is skipped, not fatal', () => {
    const i = PatientIntake.fromJson(
      intakeRow({ allergies: ['latex', 'from_the_future'], allergies_other: 'Shellfish', conditions: ['asthma'], source: 'front_desk_tablet' }),
    );
    expect([...i.allergies]).toEqual(['latex']);
    expect(i.allergyLabels).toEqual(['Latex', 'Shellfish']);
    expect(i.hasAllergies).toBe(true);
    expect(i.source).toBe('front_desk_tablet');
  });

  test('a guardian comes back from the row, or none', () => {
    expect(PatientIntake.fromJson(intakeRow()).guardian).toBeNull();
    const g = PatientIntake.fromJson(intakeRow({ guardian_name: 'Rosa', guardian_relationship: 'parent', guardian_phone: '0917' })).guardian!;
    expect(g.relationship).toBe('parent');
    expect(g.email).toBeNull();
  });
});
