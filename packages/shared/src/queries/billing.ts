import { type QueryClient, useQuery } from '@tanstack/react-query';

import type { BillingSummary, Invoice } from '../models/invoice';
import type { LedgerEntry, LedgerSummary } from '../models/ledger';
import { useRepository } from '../state/platform';
import { formatDay } from '../util/dates';
import { type AsyncValue, fromQuery, mapAsync } from './async_value';
import { useMyPatient } from './catalog';
import { useCurrentClinicId } from './clinic';
import { useCurrentClinicRole } from './clinical';

/// Whether the signed-in account may write bills at the current clinic.
/// Mirrors `private.can_bill`: the front desk and admins.
export function useCanBill(): AsyncValue<boolean> {
  return mapAsync(useCurrentClinicRole(), (role) => role === 'assistant' || role === 'admin');
}

/// The current clinic's bills, newest first. Staff.
export function useClinicInvoices(): AsyncValue<Invoice[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({ queryKey: ['invoices', clinicId], queryFn: () => (clinicId == null ? [] : repo.fetchInvoices(clinicId)) }),
  );
}

export function useInvoice(id: string): AsyncValue<Invoice | null> {
  const repo = useRepository();
  return fromQuery(useQuery({ queryKey: ['invoice', id], queryFn: () => repo.fetchInvoice(id) }));
}

/// A visit's live bill, or null if it has none yet.
export function useAppointmentInvoice(appointmentId: string): AsyncValue<Invoice | null> {
  const repo = useRepository();
  return fromQuery(
    useQuery({
      queryKey: ['appointmentInvoice', appointmentId],
      queryFn: () => repo.fetchAppointmentInvoice(appointmentId),
    }),
  );
}

/// Bills on one chart, newest first. What a patient sees of their own chart
/// excludes drafts; staff see everything.
export function usePatientInvoices(patientId: string): AsyncValue<Invoice[]> {
  const repo = useRepository();
  return fromQuery(
    useQuery({ queryKey: ['patientInvoices', patientId], queryFn: () => repo.fetchPatientInvoices(patientId) }),
  );
}

/// The signed-in patient's bills at the current clinic.
export function useMyInvoices(): AsyncValue<Invoice[]> {
  const repo = useRepository();
  const chart = useMyPatient().value;
  return fromQuery(
    useQuery({
      queryKey: ['patientInvoices', chart?.id ?? null],
      queryFn: () => (chart == null ? [] : repo.fetchPatientInvoices(chart.id)),
    }),
  );
}

export type BillingRange = { from: Date; to: Date };

function rangeKey(r: BillingRange): [string, string] {
  return [formatDay(r.from), formatDay(r.to)];
}

export function useBillingSummary(range: BillingRange): AsyncValue<BillingSummary | null> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({
      queryKey: ['billingSummary', clinicId, ...rangeKey(range)],
      queryFn: () => (clinicId == null ? null : repo.fetchBillingSummary(clinicId, range)),
    }),
  );
}

export function useLedgerSummary(range: BillingRange): AsyncValue<LedgerSummary | null> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({
      queryKey: ['ledgerSummary', clinicId, ...rangeKey(range)],
      queryFn: () => (clinicId == null ? null : repo.fetchLedgerSummary(clinicId, range)),
    }),
  );
}

export function useLedgerEntries(range: BillingRange): AsyncValue<LedgerEntry[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({
      queryKey: ['ledgerEntries', clinicId, ...rangeKey(range)],
      queryFn: () => (clinicId == null ? [] : repo.fetchLedgerEntries(clinicId, range)),
    }),
  );
}

/// After any change to a bill, a payment or an expense, every view of them
/// refetches.
export function invalidateBilling(qc: QueryClient): Promise<void> {
  return Promise.all(
    ['ledgerSummary', 'ledgerEntries', 'invoices', 'invoice', 'appointmentInvoice', 'patientInvoices', 'billingSummary'].map(
      (k) => qc.invalidateQueries({ queryKey: [k] }),
    ),
  ).then(() => undefined);
}
