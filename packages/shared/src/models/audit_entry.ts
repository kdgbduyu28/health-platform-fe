import { format } from 'date-fns';

import { parseDay } from '../util/dates';
import { formatPeso } from './money';

type Json = Record<string, any>;

/// Which part of the clinic a change was to. Filters the activity log.
export type AuditArea = 'patients' | 'visits' | 'billing' | 'clinic';
export const auditAreas: readonly AuditArea[] = ['patients', 'visits', 'billing', 'clinic'];
export const auditAreaMeta: Record<AuditArea, { label: string; tables: readonly string[] }> = {
  patients: {
    label: 'Patients',
    tables: ['patients', 'persons', 'patient_intakes', 'chart_notes', 'visit_notes', 'dental_chart_entries'],
  },
  visits: { label: 'Visits', tables: ['appointments'] },
  billing: { label: 'Billing', tables: ['invoices', 'invoice_items', 'payments', 'expenses'] },
  clinic: {
    label: 'Clinic & staff',
    tables: ['clinics', 'services', 'doctors', 'doctor_time_off', 'clinic_memberships', 'staff_invites'],
  },
};

export type AuditAction = 'insert' | 'update' | 'delete';

/// One field of a record, before and after, ready to show. [before] is null
/// when there was no before (an insert); [after] when there is no after (a
/// delete).
export type AuditChange = { label: string; before: string | null; after: string | null };

const hidden = new Set(['id', 'clinic_id', 'tx_id', 'imported']);

const recordLabels: Record<string, string> = {
  patients: 'Patient',
  persons: 'Contact details',
  patient_intakes: 'Patient form',
  chart_notes: 'Medical note',
  visit_notes: 'Visit note',
  dental_chart_entries: 'Tooth chart',
  appointments: 'Visit',
  invoices: 'Bill',
  invoice_items: 'Bill item',
  payments: 'Payment',
  expenses: 'Expense',
  clinics: 'Clinic details',
  services: 'Service',
  doctors: 'Doctor',
  doctor_time_off: 'Time off',
  clinic_memberships: 'Staff member',
  staff_invites: 'Staff code',
};

/// One change to one record, from `public.audit_entries` — see
/// 20261005120100_audit_log in health-platform-be. Readable by the clinic's
/// admins only.
export class AuditEntry {
  constructor(
    readonly id: number,
    readonly table: string,
    readonly rowId: string,
    readonly action: AuditAction,
    readonly oldValues: Json,
    readonly newValues: Json,
    readonly createdAt: Date,
    /// Shared by every change made in the same go.
    readonly txId: number,
    readonly patientId: string | null = null,
    readonly patientName: string | null = null,
    /// Null for a change nobody signed in made: a scheduled job, or the
    /// platform operator.
    readonly actorId: string | null = null,
    readonly actorName: string | null = null,
    /// `admin`, `doctor`, `assistant`, `patient`, or null.
    readonly actorRole: string | null = null,
  ) {}

  static fromJson(json: Json): AuditEntry {
    return new AuditEntry(
      Math.trunc(Number(json.id)),
      json.table_name,
      json.row_id,
      json.action,
      (json.old_values as Json | null) ?? {},
      (json.new_values as Json | null) ?? {},
      new Date(json.created_at),
      Math.trunc(Number(json.tx_id)),
      json.patient_id ?? null,
      json.patient_name ?? null,
      json.actor_id ?? null,
      json.actor_name ?? null,
      json.actor_role ?? null,
    );
  }

  /// "Maria Santos", or "System" for a change nobody signed in made.
  get actorLabel(): string {
    return this.actorName ?? (this.actorId == null ? 'System' : 'Former user');
  }

  /// "Doctor", "Front desk", "Admin", "Patient", or null.
  get actorRoleLabel(): string | null {
    switch (this.actorRole) {
      case 'admin':
        return 'Admin';
      case 'doctor':
        return 'Doctor';
      case 'assistant':
        return 'Front desk';
      case 'patient':
        return 'Patient';
      default:
        return null;
    }
  }

  /// What kind of record: "Visit", "Payment", "Medical note".
  get recordLabel(): string {
    return recordLabels[this.table] ?? humanize(this.table);
  }

  get area(): AuditArea | null {
    for (const a of auditAreas) {
      if (auditAreaMeta[a].tables.includes(this.table)) return a;
    }
    return null;
  }

  /// "added", "changed", "removed" — or the word that fits the record better.
  get verb(): string {
    if (this.action === 'insert') {
      switch (this.table) {
        case 'patients':
          return 'registered';
        case 'payments':
          return 'recorded';
        case 'invoices':
          return 'drafted';
        case 'appointments':
          return 'booked';
        default:
          return 'added';
      }
    }
    return this.action === 'update' ? 'changed' : 'removed';
  }

  /// "Visit booked", "Payment voided"… a short headline for the entry.
  get headline(): string {
    if (this.action === 'update') {
      const status = this.newValues.status;
      if (typeof status === 'string') return `${this.recordLabel} ${humanize(status).toLowerCase()}`;
      if (this.newValues.voided_at != null) return `${this.recordLabel} voided`;
    }
    return `${this.recordLabel} ${this.verb}`;
  }

  /// The fields worth showing, in a stable order.
  ///
  /// An update lists what changed. An insert or delete lists the record as it
  /// was, leaving out the ids and stamps nobody reads. A reference to another
  /// record (a doctor, a service) is shown as "changed", not as its id.
  get changes(): AuditChange[] {
    const isUpdate = this.action === 'update';
    const isDelete = this.action === 'delete';
    const source = isDelete ? this.oldValues : this.newValues;
    const out: AuditChange[] = [];

    // A chart's insert or delete carries who the patient is.
    const person = source.person;
    if (person != null && typeof person === 'object' && !Array.isArray(person)) {
      for (const [key, value] of Object.entries(person as Json)) {
        const v = formatAuditValue(key, value);
        if (v == null) continue;
        out.push(isDelete ? { label: fieldLabel(key), before: v, after: null } : { label: fieldLabel(key), before: null, after: v });
      }
    }

    for (const key of Object.keys(source)) {
      if (key === 'person' || hidden.has(key)) continue;
      const isRef = key.endsWith('_id') || key.endsWith('_by');
      if (isUpdate) {
        out.push(
          isRef
            ? { label: fieldLabel(key), before: null, after: 'changed' }
            : {
                label: fieldLabel(key),
                before: formatAuditValue(key, this.oldValues[key]) ?? '—',
                after: formatAuditValue(key, this.newValues[key]) ?? '—',
              },
        );
      } else {
        if (isRef) continue;
        const v = formatAuditValue(key, source[key]);
        if (v == null) continue;
        out.push(isDelete ? { label: fieldLabel(key), before: v, after: null } : { label: fieldLabel(key), before: null, after: v });
      }
    }
    return out;
  }
}

const fieldLabels: Record<string, string> = {
  full_name: 'Name',
  date_of_birth: 'Date of birth',
  scheduled_at: 'Time',
  ends_at: 'Ends',
  duration_minutes: 'Minutes',
  doctor_id: 'Doctor',
  service_id: 'Service',
  service_name: 'Service',
  patient_id: 'Patient',
  appointment_id: 'Visit',
  invoice_id: 'Bill',
  body: 'Note',
  patient_note: 'Note to the patient',
  chart_number: 'Chart no.',
  emergency_contact_name: 'Emergency contact',
  emergency_contact_phone: 'Emergency contact phone',
  amount_paid: 'Paid',
  discount_amount: 'Discount',
  unit_price: 'Unit price',
  is_active: 'Active',
  available_weekdays: 'Working days',
  available_time_slots: 'Hours',
  starts_on: 'From',
  ends_on: 'To',
  spent_on: 'Date',
  received_at: 'Received',
  code: 'Treatment',
  tooth: 'Tooth',
  role: 'Role',
  branch_locked: 'Branch admin',
  recall_months: 'Recall (months)',
  seed_color: 'Colour',
  signed_name: 'Signed by',
  consent_at: 'Consent given',
};

/// "date_of_birth" → "Date of birth", with the few that read better by hand.
export function fieldLabel(key: string): string {
  const known = fieldLabels[key];
  if (known != null) return known;
  let k = key;
  if (k.endsWith('_id')) k = k.substring(0, k.length - 3);
  if (k.endsWith('_by')) k = `${k.substring(0, k.length - 3)} by`;
  return humanize(k);
}

const moneyFields = new Set(['amount', 'price', 'total', 'subtotal', 'balance', 'amount_paid', 'unit_price', 'discount_amount']);

const isoDateTime = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;
const isoDate = /^\d{4}-\d{2}-\d{2}$/;

/// Fields people type into, never tidied up.
const freeText = new Set([
  'full_name',
  'body',
  'patient_note',
  'note',
  'notes',
  'description',
  'reason',
  'address',
  'occupation',
  'email',
  'signed_name',
  'medications',
  'treatment_details',
  'name',
  'label',
]);

/// A stored value as a person would write it. Null for nothing to show.
export function formatAuditValue(key: string, value: unknown): string | null {
  if (value == null) return null;
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'number') return moneyFields.has(key) ? formatPeso(value) : `${value}`;
  if (Array.isArray(value)) {
    if (value.length === 0) return null;
    return value.map((v) => (typeof v === 'string' ? humanize(v) : `${v}`)).join(', ');
  }
  if (typeof value === 'object') return null;
  const s = String(value);
  if (s.trim() === '') return null;
  if (isoDateTime.test(s)) {
    const t = new Date(s);
    if (!Number.isNaN(t.getTime())) return format(t, 'd MMM y, h:mm a');
  }
  if (isoDate.test(s)) {
    const d = parseDay(s);
    if (!Number.isNaN(d.getTime())) return format(d, 'd MMM y');
  }
  // An enum value (in_consultation, gcash) rather than something typed.
  if (/^[a-z]+(_[a-z]+)*$/.test(s) && !freeText.has(key)) return humanize(s);
  return s;
}

function humanize(snake: string): string {
  const words = snake.replace(/_/g, ' ').trim();
  if (words === '') return words;
  return words[0].toUpperCase() + words.substring(1);
}

/// One page of the log, newest first.
export type AuditPage = { entries: AuditEntry[]; hasMore: boolean };
