import type { IconName } from '../theme/icons';
import { parseDayOrNull, parseTimeOrNull } from '../util/dates';
import { type Sex, sexFromWire } from './patient_intake';
import { initialsOf } from './profile';

type Json = Record<string, any>;

/// Digits only, with a Philippine +63 prefix rewritten to the local 0, so
/// "+63 917 123 4567" and "0917-123-4567" compare equal.
export function localDigits(s: string): string {
  const d = s.replace(/\D/g, '');
  return d.startsWith('63') && d.length === 12 ? `0${d.substring(2)}` : d;
}

/// Age in whole years on [now] for someone born on [dateOfBirth].
export function ageOn(dateOfBirth: Date, now: Date = new Date()): number {
  let a = now.getFullYear() - dateOfBirth.getFullYear();
  if (
    now.getMonth() < dateOfBirth.getMonth() ||
    (now.getMonth() === dateOfBirth.getMonth() && now.getDate() < dateOfBirth.getDate())
  ) {
    a--;
  }
  return a;
}

/// A patient chart: one person's record at ONE clinic.
///
/// The database keeps identity and clinical content apart. `persons` holds who
/// someone is (name, phone, date of birth) and is shared by every clinic that
/// treats them; `patients` is the chart, and belongs to a single clinic. The
/// clinical text on a chart lives in `chart_notes`, readable only by that
/// clinic's doctors and admins — see ClinicalNote.
///
/// The screens want one object per patient, so the person is embedded and
/// flattened here:
///
///   patients?select=*,person:persons(*)
export class Patient {
  constructor(
    /// The chart id — what appointments point at.
    readonly id: string,
    readonly personId: string,
    readonly clinicId: string,
    readonly name: string,
    readonly phone: string,
    readonly email: string,
    readonly dateOfBirth: Date | null = null,
    readonly sex: Sex | null = null,
    readonly address: string | null = null,
    readonly occupation: string | null = null,
    readonly emergencyContactName: string | null = null,
    readonly emergencyContactPhone: string | null = null,
    /// Whether the patient information form has been filled in for this
    /// chart. Null when the query did not ask (only `fetchMyPatients` embeds
    /// it, for the patient app's first-visit gate).
    readonly hasIntake: boolean | null = null,
    /// The clinic's own record number for the chart ("A-0042"), when it keeps
    /// one: the paper folder's, or the old system's. Set by an import.
    readonly chartNumber: string | null = null,
  ) {}

  /// Nullable person columns become empty strings, because the UI treats them
  /// as plain text; a missing embed degrades the same way rather than
  /// crashing.
  static fromJson(json: Json): Patient {
    const person = (json.person as Json | null | undefined) ?? {};
    // One-to-one, but PostgREST may still hand back a list for an embed
    // across a composite key.
    let hasIntake: boolean | null = null;
    if ('intake' in json) {
      const intake = json.intake;
      hasIntake = intake == null ? false : Array.isArray(intake) ? intake.length > 0 : true;
    }
    return new Patient(
      json.id,
      json.person_id,
      json.clinic_id,
      person.full_name ?? '',
      person.phone ?? '',
      person.email ?? '',
      parseDayOrNull(person.date_of_birth),
      sexFromWire(person.sex),
      person.address ?? null,
      person.occupation ?? null,
      person.emergency_contact_name ?? null,
      person.emergency_contact_phone ?? null,
      hasIntake,
      json.chart_number ?? null,
    );
  }

  get initials(): string {
    return initialsOf(this.name);
  }

  get age(): number | null {
    return this.dateOfBirth == null ? null : ageOn(this.dateOfBirth);
  }

  /// Whether this patient is what someone typed into a search box: part of
  /// the name, or part of the phone number however it is formatted.
  matches(query: string): boolean {
    const q = query.trim().toLowerCase();
    if (q === '') return true;
    if (this.name.toLowerCase().includes(q)) return true;
    const digits = localDigits(q);
    return digits !== '' && localDigits(this.phone).includes(digits);
  }

  /// Same phone number, however either was typed. How the front desk spots
  /// that a "new" walk-in is already on file.
  hasPhone(other: string): boolean {
    const mine = localDigits(this.phone);
    return mine.length >= 7 && mine === localDigits(other);
  }
}

/// A remark on a chart in the patient list. The rules live in the database
/// (`public.search_patients`); these are only their names.
export type PatientFlag = 'recall' | 'balance' | 'no_contact' | 'attention' | 'pedia' | 'adult';
export const patientFlags: readonly PatientFlag[] = ['recall', 'balance', 'no_contact', 'attention', 'pedia', 'adult'];
export const patientFlagMeta: Record<PatientFlag, { label: string; icon: IconName }> = {
  recall: { label: 'For recall', icon: 'event-repeat' },
  balance: { label: 'With balance', icon: 'account-balance-wallet' },
  no_contact: { label: 'No contact info', icon: 'phone-disabled' },
  attention: { label: 'Needs attention', icon: 'priority-high' },
  pedia: { label: 'Pedia', icon: 'child-care' },
  adult: { label: 'Adult', icon: 'person-outline' },
};

/// Age groups describe the patient; the rest ask someone to act.
export function isAgeGroup(f: PatientFlag): boolean {
  return f === 'pedia' || f === 'adult';
}

export function patientFlagFromWire(value: string): PatientFlag | null {
  return (patientFlags as readonly string[]).includes(value) ? (value as PatientFlag) : null;
}

/// What the patient list can be sorted by.
export type PatientSort = 'name' | 'age' | 'first_visit' | 'last_visit' | 'next_visit' | 'visits' | 'balance';

/// Why a chart flagged `attention` needs attention.
export type AttentionReason = 'unbooked_plan' | 'no_show' | 'overdue_balance';
export const attentionReasons: readonly AttentionReason[] = ['unbooked_plan', 'no_show', 'overdue_balance'];
export const attentionReasonLabel: Record<AttentionReason, string> = {
  unbooked_plan: 'Planned treatment not booked',
  no_show: 'Missed the last visit',
  overdue_balance: 'Bill unpaid 30+ days',
};

export function attentionReasonFromWire(value: string): AttentionReason | null {
  return (attentionReasons as readonly string[]).includes(value) ? (value as AttentionReason) : null;
}

/// A chart in the patient list, with what the list shows of it. From
/// `public.search_patients`.
export class PatientListing {
  constructor(
    readonly patient: Patient,
    readonly completedVisits: number = 0,
    /// First and last COMPLETED visit.
    readonly firstVisitAt: Date | null = null,
    readonly lastVisitAt: Date | null = null,
    readonly nextVisitAt: Date | null = null,
    /// The most recent visit that is over, completed or missed.
    readonly lastVisitService: string | null = null,
    readonly lastVisitDoctor: string | null = null,
    readonly lastVisitMissed: boolean = false,
    /// Owed on issued bills.
    readonly balance: number = 0,
    /// Treatment plan items not done yet (dental clinics).
    readonly plannedCount: number = 0,
    readonly age: number | null = null,
    readonly flags: Set<PatientFlag> = new Set(),
    readonly attention: Set<AttentionReason> = new Set(),
  ) {}

  static fromJson(json: Json): PatientListing {
    const flags = new Set<PatientFlag>();
    for (const w of (json.flags ?? []) as string[]) {
      const f = patientFlagFromWire(w);
      if (f) flags.add(f);
    }
    const attention = new Set<AttentionReason>();
    for (const w of (json.attention ?? []) as string[]) {
      const r = attentionReasonFromWire(w);
      if (r) attention.add(r);
    }
    return new PatientListing(
      Patient.fromJson(json),
      json.completed_visits == null ? 0 : Math.trunc(Number(json.completed_visits)),
      parseTimeOrNull(json.first_visit_at),
      parseTimeOrNull(json.last_visit_at),
      parseTimeOrNull(json.next_visit_at),
      json.last_visit_service ?? null,
      json.last_visit_doctor ?? null,
      json.last_visit_status === 'no_show',
      json.balance == null ? 0 : Number(json.balance),
      json.planned_count == null ? 0 : Math.trunc(Number(json.planned_count)),
      json.age == null ? null : Math.trunc(Number(json.age)),
      flags,
      attention,
    );
  }
}

/// One page of a patient search, how many match in all, and how many of the
/// whole search carry each remark (before the filters).
export class PatientPage {
  constructor(
    readonly patients: PatientListing[],
    /// Matches after the filters.
    readonly total: number,
    readonly counts: Map<PatientFlag, number> = new Map(),
    /// Matches before the filters. Null from a database without them.
    readonly all: number | null = null,
  ) {}

  static fromJson(json: Json): PatientPage {
    const counts = (json.counts as Json | null | undefined) ?? {};
    const byFlag = new Map<PatientFlag, number>();
    for (const f of patientFlags) {
      if (typeof counts[f] === 'number') byFlag.set(f, Math.trunc(counts[f]));
    }
    return new PatientPage(
      ((json.patients ?? []) as Json[]).map(PatientListing.fromJson),
      json.total == null ? 0 : Math.trunc(Number(json.total)),
      byFlag,
      counts.all == null ? null : Math.trunc(Number(counts.all)),
    );
  }
}
