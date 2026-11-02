import { formatDay, parseDay } from '../util/dates';
import { type AppointmentStatus, appointmentStatusFromWire, appointmentStatuses, statusMeta } from './appointment_status';
import { parseMoney } from './money';

type Json = Record<string, any>;

export type ReportDay = { day: Date; visits: number; completed: number; noShows: number; paid: number };
export type ReportDoctor = {
  doctorId: string;
  name: string;
  visits: number;
  completed: number;
  noShows: number;
  cancelled: number;
  billed: number;
};
/// [amount] is what the lines billed, before each bill's discount.
export type ReportService = { name: string; completed: number; quantity: number; amount: number };

/// How a run of days went at a clinic, from `public.clinic_report` — see
/// 20261102120000_clinic_report in health-platform-be. Admins only.
///
/// Visits count by the day they were booked for, bills by the day they were
/// issued, payments by the day they were received — all the clinic's days.
export class ClinicReport {
  constructor(
    readonly from: Date,
    readonly to: Date,
    /// Every visit booked for those days, cancelled ones included.
    readonly visitTotal: number,
    readonly byStatus: Map<AppointmentStatus, number>,
    readonly byDay: ReportDay[],
    readonly byDoctor: ReportDoctor[],
    readonly byService: ReportService[],
    readonly newPatients: number,
    readonly billed: number,
    readonly discounts: number,
    readonly billCount: number,
    readonly paid: number,
  ) {}

  count(status: AppointmentStatus): number {
    return this.byStatus.get(status) ?? 0;
  }

  /// Visits that were not called off.
  get visits(): number {
    return this.visitTotal - this.count('cancelled');
  }

  /// No-shows out of the visits whose outcome is known — the patient came
  /// (completed) or did not. Null when there are none yet.
  get noShowRate(): number | null {
    const settled = this.count('completed') + this.count('no_show');
    return settled === 0 ? null : this.count('no_show') / settled;
  }

  static fromJson(json: Json): ClinicReport {
    const visits = (json.visits as Json | null | undefined) ?? {};
    const statuses = (visits.by_status as Json | null | undefined) ?? {};
    return new ClinicReport(
      parseDay(json.from),
      parseDay(json.to),
      Number(visits.total ?? 0),
      new Map(Object.entries(statuses).map(([k, v]) => [appointmentStatusFromWire(k), Number(v)])),
      ((json.by_day as Json[] | null) ?? []).map((d) => ({
        day: parseDay(d.day),
        visits: Number(d.visits ?? 0),
        completed: Number(d.completed ?? 0),
        noShows: Number(d.no_shows ?? 0),
        paid: parseMoney(d.paid),
      })),
      ((json.by_doctor as Json[] | null) ?? []).map((d) => ({
        doctorId: d.doctor_id as string,
        name: d.name as string,
        visits: Number(d.visits ?? 0),
        completed: Number(d.completed ?? 0),
        noShows: Number(d.no_shows ?? 0),
        cancelled: Number(d.cancelled ?? 0),
        billed: parseMoney(d.billed),
      })),
      ((json.by_service as Json[] | null) ?? []).map((s) => ({
        name: s.name as string,
        completed: Number(s.completed ?? 0),
        quantity: Number(s.quantity ?? 0),
        amount: parseMoney(s.amount),
      })),
      Number(json.new_patients ?? 0),
      parseMoney(json.billed),
      parseMoney(json.discounts),
      Number(json.bill_count ?? 0),
      parseMoney(json.paid),
    );
  }
}

/// `12%`, or `—` when there is nothing to divide by.
export function formatRate(rate: number | null): string {
  return rate == null ? '—' : `${Math.round(rate * 100)}%`;
}

/// The report as one CSV: a block per table, a blank row between, amounts as
/// plain numbers so a spreadsheet can add them up.
export function clinicReportCsvRows(r: ClinicReport): string[][] {
  const n = (v: number) => String(v);
  const money = (v: number) => v.toFixed(2);
  return [
    ['Report', `${formatDay(r.from)} to ${formatDay(r.to)}`],
    ['Visits', n(r.visits)],
    ...appointmentStatuses.filter((s) => r.count(s) > 0).map((s) => [`  ${statusMeta[s].label}`, n(r.count(s))]),
    ['No-show rate', formatRate(r.noShowRate)],
    ['New patients', n(r.newPatients)],
    ['Billed', money(r.billed)],
    ['Discounts', money(r.discounts)],
    ['Bills issued', n(r.billCount)],
    ['Paid', money(r.paid)],
    [],
    ['Day', 'Visits', 'Completed', 'No-shows', 'Paid'],
    ...r.byDay.map((d) => [formatDay(d.day), n(d.visits), n(d.completed), n(d.noShows), money(d.paid)]),
    [],
    ['Doctor', 'Visits', 'Completed', 'No-shows', 'Cancelled', 'Billed'],
    ...r.byDoctor.map((d) => [d.name, n(d.visits), n(d.completed), n(d.noShows), n(d.cancelled), money(d.billed)]),
    [],
    ['Service', 'Visits completed', 'Billed (qty)', 'Billed before discounts'],
    ...r.byService.map((s) => [s.name, n(s.completed), n(s.quantity), money(s.amount)]),
  ];
}
