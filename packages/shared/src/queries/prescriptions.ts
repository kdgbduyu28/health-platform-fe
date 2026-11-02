import { type QueryClient, useQuery } from '@tanstack/react-query';

import type { Prescription } from '../models/prescription';
import { useRepository } from '../state/platform';
import { type AsyncValue, fromQuery, mapAsync } from './async_value';
import { useCurrentDoctor, useMyPatient } from './catalog';

/// One chart's prescriptions, newest first. Clinicians see voided ones too;
/// the patient does not.
export function usePatientPrescriptions(patientId: string): AsyncValue<Prescription[]> {
  const repo = useRepository();
  return fromQuery(
    useQuery({ queryKey: ['prescriptions', 'patient', patientId], queryFn: () => repo.fetchPatientPrescriptions(patientId) }),
  );
}

/// Those written at one visit.
export function useVisitPrescriptions(appointmentId: string): AsyncValue<Prescription[]> {
  const repo = useRepository();
  return fromQuery(
    useQuery({ queryKey: ['prescriptions', 'visit', appointmentId], queryFn: () => repo.fetchVisitPrescriptions(appointmentId) }),
  );
}

export function usePrescription(id: string): AsyncValue<Prescription | null> {
  const repo = useRepository();
  return fromQuery(useQuery({ queryKey: ['prescriptions', 'one', id], queryFn: () => repo.fetchPrescription(id) }));
}

/// The signed-in patient's prescriptions at the current clinic.
export function useMyPrescriptions(): AsyncValue<Prescription[]> {
  const repo = useRepository();
  const chart = useMyPatient().value;
  return fromQuery(
    useQuery({
      queryKey: ['prescriptions', 'patient', chart?.id ?? null],
      queryFn: () => (chart == null ? [] : repo.fetchPatientPrescriptions(chart.id)),
    }),
  );
}

/// Whether the signed-in account may write one here: only a doctor on this
/// clinic's roster, in their own name.
export function useCanPrescribe(): AsyncValue<boolean> {
  return mapAsync(useCurrentDoctor(), (d) => d != null);
}

export function invalidatePrescriptions(qc: QueryClient): Promise<void> {
  return qc.invalidateQueries({ queryKey: ['prescriptions'] });
}
