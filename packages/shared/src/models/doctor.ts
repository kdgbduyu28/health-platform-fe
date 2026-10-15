import { initialsOf } from './profile';

type Json = Record<string, any>;

/// `available_weekdays` (1=Mon … 7=Sun) as people write it: `Mon–Fri`,
/// `Mon, Wed, Fri`, `Every day`. A run of three or more days is a range.
export function formatWeekdays(weekdays: Iterable<number>): string {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const days = [...new Set([...weekdays].filter((d) => d >= 1 && d <= 7))].sort((a, b) => a - b);
  if (days.length === 7) return 'Every day';

  const parts: string[] = [];
  let i = 0;
  while (i < days.length) {
    let j = i;
    while (j + 1 < days.length && days[j + 1] === days[j] + 1) j++;
    if (j - i >= 2) {
      parts.push(`${names[days[i] - 1]}–${names[days[j] - 1]}`);
    } else {
      for (let k = i; k <= j; k++) parts.push(names[days[k] - 1]);
    }
    i = j + 1;
  }
  return parts.join(', ');
}

/// A doctor's working day as an admin thinks of it — first start time, last
/// start time, every N minutes — rather than the list of start times
/// (`available_time_slots`) the database keeps. Minutes since midnight.
export type WorkingHours = { first: number; last: number; step: number };

/// `08:00` … `11:30` every 30 → the start times, as `HH:MM`.
export function generateTimeSlots(hours: WorkingHours): string[] {
  if (hours.step <= 0 || hours.last < hours.first) return [];
  const out: string[] = [];
  for (let m = hours.first; m <= hours.last && m < 24 * 60; m += hours.step) out.push(formatClock(m));
  return out;
}

/// The pattern behind [slots], if they are one evenly spaced run; null for
/// anything irregular (lunch breaks, hand-edited lists).
export function workingHoursOf(slots: string[]): WorkingHours | null {
  const minutes = slots.map(parseClock);
  if (minutes.length === 0 || minutes.includes(null)) return null;
  const sorted = (minutes as number[]).slice().sort((a, b) => a - b);
  if (sorted.length === 1) return { first: sorted[0], last: sorted[0], step: 30 };
  const step = sorted[1] - sorted[0];
  for (let i = 2; i < sorted.length; i++) {
    if (sorted[i] - sorted[i - 1] !== step) return null;
  }
  return step <= 0 ? null : { first: sorted[0], last: sorted[sorted.length - 1], step };
}

/// `08:00–11:30, every 30 min` — or `9 set times` when irregular.
export function describeTimeSlots(slots: string[]): string {
  if (slots.length === 0) return 'No times set';
  const hours = workingHoursOf(slots);
  if (hours == null) return `${slots.length} set times`;
  if (hours.first === hours.last) return `At ${formatClock(hours.first)}`;
  return `${formatClock(hours.first)}–${formatClock(hours.last)}, every ${hours.step} min`;
}

/// `HH:MM` → minutes since midnight, or null if malformed.
export function parseClock(value: string): number | null {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(value.trim());
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

/// Minutes since midnight → `HH:MM`, the format the database checks.
export function formatClock(minutes: number): string {
  return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
}

/// A roster row from `public.doctors`. One per clinic a doctor practises at:
/// the same account may appear on several clinics' rosters.
export class Doctor {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    readonly name: string,
    readonly specialty: string,
    /// 1=Monday … 7=Sunday
    readonly availableWeekdays: number[],
    /// '09:00', '09:30', …
    readonly availableTimeSlots: string[],
    readonly profileId: string | null = null,
    readonly isActive: boolean = true,
  ) {}

  static fromJson(json: Json): Doctor {
    return new Doctor(
      json.id,
      json.clinic_id,
      json.full_name,
      json.specialty ?? '',
      (json.available_weekdays ?? []).map(Number),
      (json.available_time_slots ?? []).map(String),
      json.profile_id ?? null,
      json.is_active ?? true,
    );
  }

  get initials(): string {
    return initialsOf(this.name);
  }
}
