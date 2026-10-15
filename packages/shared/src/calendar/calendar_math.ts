import { format } from 'date-fns';

import type { Appointment } from '../models/appointment';
import { type Doctor, parseClock, workingHoursOf } from '../models/doctor';
import type { TimeOff } from '../models/time_off';
import type { IconName } from '../theme/icons';
import { addDays, isoWeekday, startOfDay } from '../util/dates';

/// How much of the calendar one page shows.
export type CalendarView = 'month' | 'week' | 'day';
export const calendarViews: readonly CalendarView[] = ['month', 'week', 'day'];
export const calendarViewMeta: Record<CalendarView, { label: string; icon: IconName }> = {
  month: { label: 'Month', icon: 'calendar-view-month' },
  week: { label: 'Week', icon: 'calendar-view-week' },
  day: { label: 'Day', icon: 'calendar-view-day' },
};

export function calendarViewFromName(name: string | null): CalendarView | null {
  return name === 'month' || name === 'week' || name === 'day' ? name : null;
}

// Days are built from their parts rather than by adding milliseconds, so a
// daylight-saving change never shifts a day by an hour.

/// The Monday on or before [d]. Weeks run Monday to Sunday, as the doctors'
/// working days (1=Mon … 7=Sun) do.
export function startOfWeek(d: Date): Date {
  return addDays(startOfDay(d), 1 - isoWeekday(d));
}

/// One calendar page: visits starting in [from, to), local wall-clock days.
export type CalendarRange = { from: Date; to: Date };

/// The days a page of [view] around [date] covers. A month page is the six
/// whole weeks that hold it, so its first and last rows show the edges of
/// the months either side.
export function calendarRangeFor(view: CalendarView, date: Date): CalendarRange {
  switch (view) {
    case 'month': {
      const from = startOfWeek(new Date(date.getFullYear(), date.getMonth(), 1));
      return { from, to: addDays(from, 42) };
    }
    case 'week': {
      const from = startOfWeek(date);
      return { from, to: addDays(from, 7) };
    }
    case 'day': {
      const from = startOfDay(date);
      return { from, to: addDays(from, 1) };
    }
  }
}

/// The page before or after the one around [date].
export function shiftCalendar(view: CalendarView, date: Date, by: number): Date {
  switch (view) {
    case 'month':
      return new Date(date.getFullYear(), date.getMonth() + by, 1);
    case 'week':
      return addDays(startOfDay(date), 7 * by);
    case 'day':
      return addDays(startOfDay(date), by);
  }
}

/// `September 2026`, `Sep 21 – 27, 2026`, `Wed, Sep 23, 2026`.
export function calendarTitle(view: CalendarView, date: Date): string {
  switch (view) {
    case 'month':
      return format(date, 'MMMM y');
    case 'week': {
      const r = calendarRangeFor(view, date);
      const last = addDays(r.to, -1);
      if (r.from.getFullYear() !== last.getFullYear()) return `${format(r.from, 'MMM d, y')} – ${format(last, 'MMM d, y')}`;
      if (r.from.getMonth() !== last.getMonth()) return `${format(r.from, 'MMM d')} – ${format(last, 'MMM d, y')}`;
      return `${format(r.from, 'MMM d')} – ${format(last, 'd, y')}`;
    }
    case 'day':
      return format(date, 'EEE, MMM d, y');
  }
}

// ── Working hours and time off ───────────────────────────────────────────────

/// A stretch of one day, in minutes since midnight: [start, end).
export type MinuteSpan = { start: number; end: number };

function covers(t: TimeOff, day: Date): boolean {
  const d = startOfDay(day).getTime();
  return d >= startOfDay(t.startsOn).getTime() && d <= startOfDay(t.endsOn).getTime();
}

/// The clinic-wide closure covering [day], if any.
export function closureOn(timeOff: readonly TimeOff[], day: Date): TimeOff | null {
  return timeOff.find((t) => t.isClosure && covers(t, day)) ?? null;
}

/// [doctor]'s own leave covering [day], if any.
export function leaveOn(timeOff: readonly TimeOff[], doctor: Doctor, day: Date): TimeOff | null {
  return timeOff.find((t) => t.doctorId === doctor.id && covers(t, day)) ?? null;
}

/// When [doctor] takes patients on [day]: each start time in their list
/// opens the gap to the next one (or one step, for the last), merged into
/// spans. Empty on a day off, on leave, or when the clinic is closed.
export function workingSpans(doctor: Doctor, day: Date, timeOff: readonly TimeOff[]): MinuteSpan[] {
  if (!doctor.availableWeekdays.includes(isoWeekday(day))) return [];
  if (closureOn(timeOff, day) != null || leaveOn(timeOff, doctor, day) != null) return [];
  const starts = doctor.availableTimeSlots
    .map(parseClock)
    .filter((m): m is number => m != null)
    .sort((a, b) => a - b);
  if (starts.length === 0) return [];
  const step = workingHoursOf(doctor.availableTimeSlots)?.step ?? 30;
  return mergeSpans(starts.map((m) => ({ start: m, end: Math.min(m + step, 24 * 60) })));
}

/// [spans] sorted and joined wherever they touch or overlap.
export function mergeSpans(spans: Iterable<MinuteSpan>): MinuteSpan[] {
  const sorted = [...spans].sort((a, b) => a.start - b.start);
  const out: MinuteSpan[] = [];
  for (const s of sorted) {
    const last = out[out.length - 1];
    if (last != null && s.start <= last.end) out[out.length - 1] = { start: last.start, end: Math.max(last.end, s.end) };
    else out.push(s);
  }
  return out;
}

// ── Overlapping visits side by side ─────────────────────────────────────────

/// Where each visit sits across its column: [lane] of [lanes] equal strips.
/// Visits that overlap, directly or through a chain, share a group and split
/// its width, as in any calendar. The database refuses a doctor or patient
/// in two places at once, so this happens only across doctors or patients,
/// or with cancelled visits shown.
export type LanePlace = { lane: number; lanes: number };

export function layoutLanes(items: readonly Appointment[]): Map<string, LanePlace> {
  const sorted = [...items].sort((a, b) => {
    const c = a.dateTime.getTime() - b.dateTime.getTime();
    return c !== 0 ? c : b.endsAt.getTime() - a.endsAt.getTime();
  });
  const out = new Map<string, LanePlace>();
  let group: Appointment[] = [];
  let laneEnds: number[] = [];
  const laneOf = new Map<string, number>();
  let groupEnd: number | null = null;

  const flush = () => {
    for (const a of group) out.set(a.id, { lane: laneOf.get(a.id)!, lanes: laneEnds.length });
    group = [];
    laneEnds = [];
  };

  for (const a of sorted) {
    const start = a.dateTime.getTime();
    const end = a.endsAt.getTime();
    if (groupEnd != null && start >= groupEnd) flush();
    let lane = laneEnds.findIndex((e) => start >= e);
    if (lane === -1) {
      lane = laneEnds.length;
      laneEnds.push(end);
    } else {
      laneEnds[lane] = end;
    }
    laneOf.set(a.id, lane);
    group.push(a);
    groupEnd = group.length === 1 || end > groupEnd! ? end : groupEnd;
  }
  flush();
  return out;
}

export function closedLabel(t: TimeOff): string {
  return t.reason == null || t.reason.trim() === '' ? 'Clinic closed' : `Closed · ${t.reason}`;
}

export function leaveLabel(t: TimeOff): string {
  return t.reason == null || t.reason.trim() === '' ? 'On leave' : `On leave · ${t.reason}`;
}
