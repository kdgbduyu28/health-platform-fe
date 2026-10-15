import { format } from 'date-fns';

import type { Appointment } from '../models/appointment';
import { holdsTime } from '../models/appointment_status';
import { type Doctor, describeTimeSlots, formatWeekdays } from '../models/doctor';
import type { TimeOff } from '../models/time_off';
import { addMinutes } from '../util/dates';
import { closureOn, leaveOn, workingSpans } from './calendar_math';

/// What stands in the way of booking [patientId] with [doctor] from [start]
/// for [minutes], judged from the visits already loaded. [blocking] ones the
/// database would refuse; [warnings] it allows staff to override (a time off
/// the doctor's grid, a walk-in squeezed in).
export type BookingCheck = { blocking: string[]; warnings: string[] };

export function checkBooking(args: {
  start: Date;
  minutes: number;
  doctor: Doctor;
  appointments: readonly Appointment[];
  timeOff: readonly TimeOff[];
  patientId?: string | null;
  patientName?: string | null;
  now?: Date;
}): BookingCheck {
  const { start, minutes, doctor } = args;
  const end = addMinutes(start, minutes);
  const blocking: string[] = [];
  const warnings: string[] = [];
  const overlaps = (a: Appointment) => holdsTime(a.status) && a.dateTime.getTime() < end.getTime() && a.endsAt.getTime() > start.getTime();
  const span = (a: Appointment) => `${format(a.dateTime, 'h:mm')}–${format(a.endsAt, 'h:mm a')}`;

  if (start.getTime() <= (args.now ?? new Date()).getTime()) {
    blocking.push(`That time has passed. For a visit that already happened, use "Manually add visit" on the patient's page.`);
  }
  for (const a of args.appointments) {
    if (a.doctor.id === doctor.id && overlaps(a)) blocking.push(`Dr. ${doctor.name} already sees ${a.patient.name} ${span(a)}.`);
  }
  if (args.patientId != null) {
    for (const a of args.appointments) {
      if (a.patient.id === args.patientId && overlaps(a)) {
        blocking.push(`${args.patientName ?? 'This patient'} already has a visit ${span(a)} with Dr. ${a.doctor.name}.`);
      }
    }
  }

  const closure = closureOn(args.timeOff, start);
  const leave = leaveOn(args.timeOff, doctor, start);
  if (closure != null) {
    warnings.push(`The clinic is closed that day${closure.reason == null ? '' : ` (${closure.reason})`}.`);
  } else if (leave != null) {
    warnings.push(`Dr. ${doctor.name} is on leave that day${leave.reason == null ? '' : ` (${leave.reason})`}.`);
  } else {
    const from = start.getHours() * 60 + start.getMinutes();
    const to = from + minutes;
    const inHours = workingSpans(doctor, start, args.timeOff).some((s) => s.start <= from && to <= s.end);
    if (!inHours) {
      warnings.push(`Outside Dr. ${doctor.name}'s hours (${formatWeekdays(doctor.availableWeekdays)}, ${describeTimeSlots(doctor.availableTimeSlots)}).`);
    }
  }
  return { blocking, warnings };
}
