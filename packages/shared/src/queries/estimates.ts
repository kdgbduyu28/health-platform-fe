import { type QueryClient, useQuery } from '@tanstack/react-query';

import type { TreatmentEstimate } from '../models/estimate';
import { useRepository } from '../state/platform';
import { type AsyncValue, fromQuery, mapAsync } from './async_value';
import { useMyPatient } from './catalog';
import { useCurrentClinicId } from './clinic';
import { useCurrentClinicRole } from './clinical';

/// One chart's estimates, newest first. Staff see drafts and voided ones;
/// the patient only what was sent to them.
export function usePatientEstimates(patientId: string): AsyncValue<TreatmentEstimate[]> {
  const repo = useRepository();
  return fromQuery(useQuery({ queryKey: ['estimates', 'patient', patientId], queryFn: () => repo.fetchPatientEstimates(patientId) }));
}

export function useEstimate(id: string): AsyncValue<TreatmentEstimate | null> {
  const repo = useRepository();
  return fromQuery(useQuery({ queryKey: ['estimates', 'one', id], queryFn: () => repo.fetchEstimate(id) }));
}

/// The signed-in patient's estimates at the current clinic.
export function useMyEstimates(): AsyncValue<TreatmentEstimate[]> {
  const repo = useRepository();
  const chart = useMyPatient().value;
  return fromQuery(
    useQuery({
      queryKey: ['estimates', 'patient', chart?.id ?? null],
      queryFn: () => (chart == null ? [] : repo.fetchPatientEstimates(chart.id)),
    }),
  );
}

/// Accepted estimates at the current clinic not yet billed. Staff.
export function useUnbilledEstimates(): AsyncValue<TreatmentEstimate[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({
      queryKey: ['estimates', 'unbilled', clinicId],
      queryFn: () => (clinicId == null ? [] : repo.fetchUnbilledEstimates(clinicId)),
    }),
  );
}

/// Whether the signed-in account writes estimates here. Mirrors
/// `private.can_estimate`: everyone on staff.
export function useCanEstimate(): AsyncValue<boolean> {
  return mapAsync(useCurrentClinicRole(), (role) => role === 'doctor' || role === 'assistant' || role === 'admin');
}

export function invalidateEstimates(qc: QueryClient): Promise<void> {
  return qc.invalidateQueries({ queryKey: ['estimates'] });
}
