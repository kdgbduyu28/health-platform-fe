/// Time values as the database sends them, and back.
///
/// Dart's `DateTime.parse('2026-09-23')` reads a bare date as LOCAL midnight;
/// JavaScript's `new Date('2026-09-23')` reads it as UTC midnight, which is
/// the previous evening in the Americas and drifts a day in formatting. Every
/// `date` column therefore goes through [parseDay], never `new Date`.

/// A `timestamptz` (ISO 8601 with an offset) → a Date. The UI formats it in
/// the device's zone, which is the clinic's wall clock.
export function parseTime(value: unknown): Date {
  return new Date(value as string);
}

export function parseTimeOrNull(value: unknown): Date | null {
  return value == null ? null : new Date(value as string);
}

/// `2026-09-23` → local midnight on that calendar day. Accepts a longer ISO
/// string too and keeps only its date part.
export function parseDay(value: unknown): Date {
  const s = String(value);
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
  if (!m) return new Date(s);
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

export function parseDayOrNull(value: unknown): Date | null {
  return value == null ? null : parseDay(value);
}

/// `2026-09-23` — a calendar day, as Postgres `date` takes it.
export function formatDay(day: Date): string {
  return (
    `${String(day.getFullYear()).padStart(4, '0')}-` +
    `${String(day.getMonth() + 1).padStart(2, '0')}-` +
    `${String(day.getDate()).padStart(2, '0')}`
  );
}

/// Midnight at the start of [d]'s calendar day.
export function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function addDays(d: Date, days: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + days, d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds());
}

export function addMinutes(d: Date, minutes: number): Date {
  return new Date(d.getTime() + minutes * 60_000);
}

export function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/// Dart's weekday: 1 = Monday … 7 = Sunday.
export function isoWeekday(d: Date): number {
  return d.getDay() === 0 ? 7 : d.getDay();
}

/// Whole calendar days from [a] to [b], ignoring the time of day and any
/// daylight-saving shift in between.
export function daysBetween(a: Date, b: Date): number {
  const ua = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
  const ub = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
  return Math.round((ub - ua) / 86_400_000);
}
