import { type BookingCheck, checkBooking } from '../src/calendar/booking_check';
import {
  calendarRangeFor,
  calendarTitle,
  closureOn,
  layoutLanes,
  shiftCalendar,
  startOfWeek,
  workingSpans,
} from '../src/calendar/calendar_math';
import { Appointment } from '../src/models/appointment';
import type { AppointmentStatus } from '../src/models/appointment_status';
import { Doctor } from '../src/models/doctor';
import { Patient } from '../src/models/patient';
import { TimeOff } from '../src/models/time_off';
import { addDays } from '../src/util/dates';

const santos = new Doctor('d1', 'c1', 'Maria Santos', 'General Dentistry', [1, 2, 3, 4, 5], ['08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30']);
const reyes = new Doctor('d2', 'c1', 'Jose Reyes', 'Orthodontics', [1, 3, 5], ['08:00', '09:00', '10:00', '11:00']);

const patient = (id: string) => new Patient(`chart-${id}`, `person-${id}`, 'c1', `Patient ${id}`, '0917', `${id}@email.com`);

function visit(id: string, at: Date, opts: { doctor?: Doctor; minutes?: number; status?: AppointmentStatus; patientId?: string } = {}) {
  const { doctor = santos, minutes = 30, status = 'confirmed', patientId } = opts;
  return new Appointment(id, 'c1', patient(patientId ?? id), doctor, at, 'Cleaning', status, null, null, null, minutes);
}

/// A Monday at least a week out, so every test day is still to come.
const monday = (() => {
  const now = new Date();
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 7);
  const weekday = d.getDay() === 0 ? 7 : d.getDay();
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() - (weekday - 1));
})();

const at = (day: Date, hour: number, minute = 0) => new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute);
const day = (y: number, m: number, d: number) => new Date(y, m - 1, d);

describe('pages', () => {
  test('weeks start on Monday', () => {
    expect(startOfWeek(day(2026, 9, 23))).toEqual(day(2026, 9, 21));
    expect(startOfWeek(day(2026, 9, 27))).toEqual(day(2026, 9, 21));
    expect(startOfWeek(day(2026, 9, 21))).toEqual(day(2026, 9, 21));
  });

  test('a month page is the six whole weeks around it', () => {
    const r = calendarRangeFor('month', day(2026, 9, 23));
    expect(r.from).toEqual(day(2026, 8, 31));
    expect(r.to).toEqual(day(2026, 10, 12));
  });

  test('week and day pages', () => {
    const w = calendarRangeFor('week', new Date(2026, 8, 23, 15));
    expect([w.from, w.to]).toEqual([day(2026, 9, 21), day(2026, 9, 28)]);
    const d = calendarRangeFor('day', new Date(2026, 8, 23, 15));
    expect([d.from, d.to]).toEqual([day(2026, 9, 23), day(2026, 9, 24)]);
  });

  test('paging a month from the 31st lands on the next month', () => {
    expect(shiftCalendar('month', day(2026, 1, 31), 1)).toEqual(day(2026, 2, 1));
    expect(shiftCalendar('week', day(2026, 9, 23), -1)).toEqual(day(2026, 9, 16));
    expect(shiftCalendar('day', day(2026, 12, 31), 1)).toEqual(day(2027, 1, 1));
  });

  test('titles', () => {
    expect(calendarTitle('month', day(2026, 9, 23))).toBe('September 2026');
    expect(calendarTitle('week', day(2026, 9, 23))).toBe('Sep 21 – 27, 2026');
    expect(calendarTitle('week', day(2026, 9, 30))).toBe('Sep 28 – Oct 4, 2026');
    expect(calendarTitle('week', day(2026, 12, 30))).toBe('Dec 28, 2026 – Jan 3, 2027');
  });
});

describe('working hours', () => {
  const mon = day(2026, 9, 21);

  test('start times become one span, the last lasting one step', () => {
    expect(workingSpans(santos, mon, [])).toEqual([{ start: 480, end: 720 }]);
  });

  test('a list with gaps stays in pieces', () => {
    const split = new Doctor('d3', 'c1', 'Ana Cruz', '', [1], ['08:00', '08:30', '13:00', '13:30']);
    expect(workingSpans(split, mon, [])).toEqual([
      { start: 480, end: 540 },
      { start: 780, end: 840 },
    ]);
  });

  test('nothing on a day off, on leave, or when the clinic is closed', () => {
    expect(workingSpans(reyes, day(2026, 9, 22), [])).toEqual([]);
    const leave = new TimeOff('t1', 'c1', mon, mon, 'd1');
    expect(workingSpans(santos, mon, [leave])).toEqual([]);
    expect(workingSpans(reyes, mon, [leave])).not.toEqual([]);
    const closed = new TimeOff('t2', 'c1', mon, mon);
    expect(workingSpans(reyes, mon, [closed])).toEqual([]);
    expect(closureOn([closed], at(mon, 15))).toBe(closed);
  });
});

test('overlapping visits share the width only while they overlap', () => {
  const d = day(2026, 9, 21);
  const lanes = layoutLanes([
    visit('a', at(d, 9), { minutes: 60 }),
    visit('b', at(d, 9, 30), { doctor: reyes }),
    visit('c', at(d, 10)),
    visit('d', at(d, 11)),
  ]);
  expect(lanes.get('a')).toEqual({ lane: 0, lanes: 2 });
  expect(lanes.get('b')).toEqual({ lane: 1, lanes: 2 });
  // 10:00 starts as 'a' ends: a new group, full width.
  expect(lanes.get('c')).toEqual({ lane: 0, lanes: 1 });
  expect(lanes.get('d')).toEqual({ lane: 0, lanes: 1 });
});

describe('booking check', () => {
  const rows = [
    visit('x', at(monday, 8, 30), { minutes: 60 }), // Santos 8:30–9:30
    visit('y', at(monday, 9), { doctor: reyes, patientId: 'p' }), // p with Reyes
  ];
  const check = (doctor: Doctor, start: Date, opts: { patientId?: string; off?: TimeOff[] } = {}): BookingCheck =>
    checkBooking({ start, minutes: 30, doctor, appointments: rows, timeOff: opts.off ?? [], patientId: opts.patientId, patientName: 'Juan' });

  test('a doctor already seeing someone', () => {
    const c = check(santos, at(monday, 9));
    expect(c.blocking).toHaveLength(1);
    expect(c.blocking[0]).toContain('already sees Patient x');
  });

  test('a patient already booked with another doctor', () => {
    expect(check(santos, at(monday, 10), { patientId: 'chart-p' }).blocking).toEqual([]);
    const clash = check(santos, at(monday, 9, 15), { patientId: 'chart-p' });
    expect(clash.blocking.some((b) => b.includes('Juan already has a visit') && b.includes('Dr. Jose Reyes'))).toBe(true);
  });

  test('cancelled visits hold no time', () => {
    const c = checkBooking({ start: at(monday, 9), minutes: 30, doctor: santos, appointments: [visit('x', at(monday, 9), { status: 'cancelled' })], timeOff: [] });
    expect(c.blocking).toEqual([]);
  });

  test('past times block; off-grid, leave and closures only warn', () => {
    expect(check(santos, new Date(Date.now() - 3600_000)).blocking.some((b) => b.startsWith('That time has passed'))).toBe(true);
    expect(check(santos, at(monday, 15)).warnings).toHaveLength(1);
    expect(check(santos, at(monday, 15)).warnings[0]).toContain('Outside Dr. Maria');
    expect(check(reyes, at(addDays(monday, 1), 9)).warnings[0]).toContain('Outside');
    const leave = new TimeOff('t', 'c1', monday, monday, 'd1');
    expect(check(santos, at(monday, 10), { off: [leave] }).warnings[0]).toContain('on leave');
    expect(check(santos, at(monday, 10)).warnings).toEqual([]);
  });
});
