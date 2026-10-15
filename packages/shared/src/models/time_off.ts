import { parseDay } from '../util/dates';

type Json = Record<string, any>;

/// A day or days nobody can book: one doctor's leave, or — with no
/// [doctorId] — the whole clinic closed. From `public.doctor_time_off`.
export class TimeOff {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    /// Calendar days in the clinic's time zone, both inclusive.
    readonly startsOn: Date,
    readonly endsOn: Date,
    readonly doctorId: string | null = null,
    readonly reason: string | null = null,
  ) {}

  get isClosure(): boolean {
    return this.doctorId == null;
  }

  static fromJson(json: Json): TimeOff {
    return new TimeOff(
      json.id,
      json.clinic_id,
      parseDay(json.starts_on),
      parseDay(json.ends_on),
      json.doctor_id ?? null,
      json.reason ?? null,
    );
  }
}
