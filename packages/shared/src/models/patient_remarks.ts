import type { Appointment } from './appointment';
import type { Invoice } from './invoice';
import { type AttentionReason, type Patient, type PatientFlag } from './patient';

/// The remarks on one chart, worked out from what the patient page has
/// already loaded. Mirrors `public.search_patients`, so the page and the list
/// agree.
export function patientRemarks(args: {
  patient: Patient;
  visits: Appointment[];
  invoices: Invoice[];
  plannedCount: number;
  recallMonths: number;
  now?: Date;
}): { flags: Set<PatientFlag>; attention: Set<AttentionReason> } {
  const at = args.now ?? new Date();
  const t = at.getTime();
  const completed = args.visits
    .filter((a) => a.status === 'completed')
    .map((a) => a.dateTime.getTime())
    .sort((a, b) => a - b);
  const lastVisit = completed.length === 0 ? null : completed[completed.length - 1];
  const hasNext = args.visits.some((a) => a.dateTime.getTime() > t && a.status !== 'cancelled' && a.status !== 'no_show');
  const over = args.visits
    .filter((a) => a.dateTime.getTime() <= t && (a.status === 'completed' || a.status === 'no_show'))
    .sort((a, b) => b.dateTime.getTime() - a.dateTime.getTime());
  const owed = args.invoices.filter((v) => v.status === 'issued' && v.balance > 0);
  const age = args.patient.age;

  const attention = new Set<AttentionReason>();
  if (args.plannedCount > 0 && !hasNext) attention.add('unbooked_plan');
  if (over.length > 0 && over[0].status === 'no_show') attention.add('no_show');
  const thirtyDaysAgo = t - 30 * 86_400_000;
  if (owed.some((v) => (v.issuedAt ?? v.createdAt).getTime() < thirtyDaysAgo)) attention.add('overdue_balance');

  // Dart's DateTime(y, m - n, d) rolls over the same way JavaScript's does.
  const recallBefore = new Date(at.getFullYear(), at.getMonth() - args.recallMonths, at.getDate(), at.getHours(), at.getMinutes());

  const flags = new Set<PatientFlag>();
  if (lastVisit != null && lastVisit < recallBefore.getTime() && !hasNext) flags.add('recall');
  if (owed.length > 0) flags.add('balance');
  if (args.patient.phone.trim() === '' && args.patient.email.trim() === '') flags.add('no_contact');
  if (attention.size > 0) flags.add('attention');
  if (age != null) flags.add(age < 18 ? 'pedia' : 'adult');
  return { flags, attention };
}
