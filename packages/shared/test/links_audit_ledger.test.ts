import {
  calendarFeedUrl,
  foldIcsLine,
  googleCalendarLink,
  googleSubscribeLink,
  icsText,
  icsTime,
  visitEventFromAppointment,
  visitIcs,
  webcalUrl,
} from '../src/calendar/calendar_links';
import { appRoles, registersPatients } from '../src/models/app_role';
import { Appointment } from '../src/models/appointment';
import type { AppointmentStatus } from '../src/models/appointment_status';
import { AuditEntry, formatAuditValue } from '../src/models/audit_entry';
import { Clinic } from '../src/models/clinic';
import { Doctor } from '../src/models/doctor';
import { commonPaymentMethods, paymentMethodFromWire, paymentMethods } from '../src/models/invoice';
import { LedgerEntry, LedgerSummary } from '../src/models/ledger';
import { Patient } from '../src/models/patient';

// ── Calendar links ──────────────────────────────────────────────────────────

const visit = (status: AppointmentStatus = 'confirmed') =>
  new Appointment(
    'appt-1',
    'c1',
    new Patient('chart-1', 'person-1', 'c1', 'Juan dela Cruz', '0917', 'juan@email.com'),
    new Doctor('d1', 'c1', 'Maria Santos', 'General Dentistry', [1, 2, 3, 4, 5], ['09:00']),
    new Date(Date.UTC(2026, 8, 29, 1)),
    'Root Canal',
    status,
    null,
    null,
    null,
    45,
  );

const clinic = Clinic.fromJson({
  id: 'c1',
  name: 'D-Touch Dental Clinic',
  slug: 'dtouchdental',
  type: 'dental',
  clinic_type: { display_name: 'Dental' },
  address: '12 Rizal St., Quezon City',
  contact_phone: '+63 2 8123 4567',
});
const appLink = 'https://app.example/dtouchdental/appointments/appt-1';

describe('calendar links', () => {
  test('times are UTC basic format, whatever the device zone', () => {
    expect(icsTime(new Date(Date.UTC(2026, 8, 29, 1, 0, 5)))).toBe('20260929T010005Z');
  });

  test('the event names the clinic and doctor, never the service', () => {
    const e = visitEventFromAppointment(visit(), { clinic, appLink });
    expect(e.title).toBe('Visit at D-Touch Dental Clinic');
    expect(e.details).toContain('Dr. Maria Santos');
    expect(e.details).toContain('+63 2 8123 4567');
    expect(`${e.title}${e.details}`).not.toContain('Root Canal');
    expect(e.end.getTime() - e.start.getTime()).toBe(45 * 60_000);
    expect(e.uid).toBe('appt-1@health-platform');
  });

  test('a requested visit says so, and is tentative', () => {
    const e = visitEventFromAppointment(visit('pending'), { clinic });
    expect(e.title.startsWith('Requested: ')).toBe(true);
    expect(visitIcs(e)).toContain('\r\nSTATUS:TENTATIVE\r\n');
  });

  test('Google Calendar link is filled in', () => {
    const url = new URL(googleCalendarLink(visitEventFromAppointment(visit(), { clinic })));
    expect(url.host).toBe('calendar.google.com');
    expect(url.searchParams.get('action')).toBe('TEMPLATE');
    expect(url.searchParams.get('text')).toBe('Visit at D-Touch Dental Clinic');
    expect(url.searchParams.get('dates')).toBe('20260929T010000Z/20260929T014500Z');
    expect(url.searchParams.get('location')).toBe('12 Rizal St., Quezon City');
  });

  test('.ics file is valid enough for every calendar', () => {
    const ics = visitIcs(visitEventFromAppointment(visit(), { clinic, appLink }), new Date(Date.UTC(2026, 8, 22)));
    expect(ics.startsWith('BEGIN:VCALENDAR\r\n')).toBe(true);
    expect(ics.endsWith('END:VCALENDAR\r\n')).toBe(true);
    expect(ics).toContain('\r\nDTSTART:20260929T010000Z\r\nDTEND:20260929T014500Z\r\n');
    expect(ics).toContain('LOCATION:12 Rizal St.\\, Quezon City');
    expect(ics).toContain('\r\nDTSTAMP:20260922T000000Z\r\n');
    for (const line of ics.split('\r\n')) expect(new TextEncoder().encode(line).length, line).toBeLessThanOrEqual(75);
  });

  test('text escaping and folding', () => {
    expect(icsText('a,b;c\\d\ne')).toBe('a\\,b\\;c\\\\d\\ne');
    const line = `DESCRIPTION:${'₱'.repeat(40)}`;
    const folded = foldIcsLine(line);
    expect(folded.replaceAll('\r\n ', '')).toBe(line);
    // ₱ is 3 octets in UTF-8: 12 + 21*3 = 75 on the first line.
    expect(folded.split('\r\n')[0]).toBe(`DESCRIPTION:${'₱'.repeat(21)}`);
  });

  test('feed links', () => {
    const token = 'ab'.repeat(32);
    const url = calendarFeedUrl(token, 'https://x.supabase.co');
    expect(url).toBe(`https://x.supabase.co/functions/v1/calendar-feed?token=${token}`);
    expect(webcalUrl(url).startsWith('webcal://x.supabase.co/functions/v1/')).toBe(true);
    expect(new URL(googleSubscribeLink(url)).searchParams.get('cid')).toBe(webcalUrl(url));
  });
});

// ── Activity log ────────────────────────────────────────────────────────────

const row = (opts: {
  table?: string;
  action?: string;
  oldValues?: Record<string, unknown> | null;
  newValues?: Record<string, unknown> | null;
  actorId?: string | null;
  actorName?: string | null;
  actorRole?: string | null;
}) => ({
  id: 7,
  clinic_id: 'c1',
  patient_id: 'p1',
  patient_name: 'Ana Cruz',
  table_name: opts.table ?? 'appointments',
  row_id: 'r1',
  action: opts.action ?? 'update',
  old_values: opts.oldValues ?? null,
  new_values: opts.newValues ?? null,
  actor_id: opts.actorId === undefined ? 'u1' : opts.actorId,
  actor_name: opts.actorName === undefined ? 'Maria Santos' : opts.actorName,
  actor_role: opts.actorRole === undefined ? 'doctor' : opts.actorRole,
  tx_id: 99,
  created_at: '2026-09-30T02:15:00+00:00',
});

describe('activity log', () => {
  test('an update names the record, the new status and who did it', () => {
    const e = AuditEntry.fromJson(row({ oldValues: { status: 'pending' }, newValues: { status: 'in_consultation' } }));
    expect(e.headline).toBe('Visit in consultation');
    expect(e.actorLabel).toBe('Maria Santos');
    expect(e.actorRoleLabel).toBe('Doctor');
    expect(e.area).toBe('visits');
    expect(e.changes).toEqual([{ label: 'Status', before: 'Pending', after: 'In consultation' }]);
  });

  test('a reference to another record shows as changed, not as an id', () => {
    const e = AuditEntry.fromJson(row({ oldValues: { doctor_id: 'd1' }, newValues: { doctor_id: 'd2' } }));
    expect(e.changes).toEqual([{ label: 'Doctor', before: null, after: 'changed' }]);
  });

  test('a new patient lists who they are, without the ids', () => {
    const e = AuditEntry.fromJson(
      row({
        table: 'patients',
        action: 'insert',
        newValues: {
          id: 'p1',
          person_id: 'x',
          created_by: 'u1',
          chart_number: 'DT-7',
          person: { full_name: 'Ana Cruz', phone: '0917', sex: 'female', email: null },
        },
        actorRole: 'assistant',
      }),
    );
    expect(e.headline).toBe('Patient registered');
    expect(e.actorRoleLabel).toBe('Front desk');
    expect(e.changes.map((c) => `${c.label}=${c.after}`)).toEqual(['Name=Ana Cruz', 'Phone=0917', 'Sex=Female', 'Chart no.=DT-7']);
  });

  test('money, dates, flags and typed text read naturally', () => {
    expect(formatAuditValue('amount', 1500)).toBe('₱1,500');
    expect(formatAuditValue('date_of_birth', '1990-04-02')).toBe('2 Apr 1990');
    expect(formatAuditValue('is_active', false)).toBe('No');
    expect(formatAuditValue('allergies', ['local_anesthetic', 'latex'])).toBe('Local anesthetic, Latex');
    expect(formatAuditValue('body', 'keep_this')).toBe('keep_this');
    expect(formatAuditValue('method', 'gcash')).toBe('Gcash');
    expect(formatAuditValue('phone', '')).toBeNull();
  });

  test('a delete shows the record as it was, and a voided payment says so', () => {
    const gone = AuditEntry.fromJson(row({ table: 'expenses', action: 'delete', oldValues: { amount: 250, description: 'Gloves' } }));
    expect(gone.headline).toBe('Expense removed');
    expect(gone.changes.map((c) => `${c.label}:${c.before}:${c.after}`)).toEqual(['Amount:₱250:null', 'Description:Gloves:null']);

    const voided = AuditEntry.fromJson(
      row({ table: 'payments', oldValues: { voided_at: null }, newValues: { voided_at: '2026-09-30T03:00:00+00:00' }, actorRole: 'admin' }),
    );
    expect(voided.headline).toBe('Payment voided');
  });

  test("a change nobody signed in made is the system's", () => {
    const e = AuditEntry.fromJson(row({ actorId: null, actorName: null, actorRole: null, newValues: { price: 1 }, oldValues: { price: 2 } }));
    expect(e.actorLabel).toBe('System');
    expect(e.actorRoleLabel).toBeNull();
  });

  test('every staff app adds patients', () => {
    expect(appRoles.filter(registersPatients)).toEqual(['doctor', 'assistant', 'admin']);
  });
});

// ── Ledger ──────────────────────────────────────────────────────────────────

describe('ledger', () => {
  test('the desk picks from cash, GCash, BPI, BDO and QR Ph first', () => {
    expect(commonPaymentMethods).toEqual(['cash', 'gcash', 'bpi', 'bdo', 'qrph']);
    for (const m of paymentMethods) expect(paymentMethodFromWire(m)).toBe(m);
  });

  test("a ledger summary reads the database's figures as they are", () => {
    const s = LedgerSummary.fromJson({
      gross: 1500,
      discounts: '0.00',
      bill_count: 1,
      paid: 500,
      payment_count: 1,
      by_method: { bpi: 500 },
      pending: 1000,
      expenses: 200,
      by_category: { Supplies: 200 },
      net: 300,
      outstanding: 1000,
      unpaid_count: 1,
      draft_total: 0,
      draft_count: 0,
    });
    expect(s.gross).toBe(1500);
    expect([...s.byMethod]).toEqual([['bpi', 500]]);
    expect([...s.byCategory]).toEqual([['Supplies', 200]]);
    expect(s.net).toBe(300);
  });

  test('a ledger entry is a payment in or an expense out', () => {
    const e = LedgerEntry.fromJson({
      kind: 'expense',
      id: 'e1',
      happened_at: '2026-09-23T04:00:00Z',
      amount: '200.00',
      method: 'cash',
      reference: null,
      title: 'Supplies',
      detail: 'Gloves',
      invoice_id: null,
      voided: false,
      void_reason: null,
    });
    expect(e.isExpense).toBe(true);
    expect(e.amount).toBe(200);
    expect(e.method).toBe('cash');
  });
});
