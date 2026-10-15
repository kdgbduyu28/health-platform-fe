import { type QueryClient, useQuery } from '@tanstack/react-query';

import { type AppRole, seesClinicalNotes } from '../models/app_role';
import type { Appointment } from '../models/appointment';
import type { ClinicalNote } from '../models/clinical_note';
import type { Patient } from '../models/patient';
import { useAppRole, useCurrentUserId, useRepository } from '../state/platform';
import { type AsyncValue, fromQuery, mapAsync } from './async_value';
import { useCurrentClinicId, useMyMemberships } from './clinic';

/// The signed-in account's staff role at the clinic being shown.
///
/// Null in the patient app — even for an account that is also staff at this
/// clinic, since the patient app must never show clinic-side content — and
/// for anyone with no membership here.
export function useCurrentClinicRole(): AsyncValue<AppRole | null> {
  const app = useAppRole();
  const clinicId = useCurrentClinicId();
  const memberships = useMyMemberships();
  if (app === 'patient') return { hasValue: true, value: null, hasError: false, error: null, isLoading: false };
  return mapAsync(memberships, (list) => list.find((m) => m.clinicId === clinicId)?.role ?? null);
}

/// Whether this user may see clinical notes at the current clinic.
///
/// The database enforces this on its own (20260915120000). The screens still
/// need to know, because for anyone else a notes query returns nothing — and
/// "Nothing on file" is not something to show a receptionist about a patient
/// who has a latex allergy recorded.
export function useCanSeeClinicalNotes(): AsyncValue<boolean> {
  return mapAsync(useCurrentClinicRole(), (role) => (role == null ? false : seesClinicalNotes(role)));
}

/// One chart, with its person.
export function usePatientById(patientId: string, enabled = true): AsyncValue<Patient | null> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(useQuery({ queryKey: ['patient', uid, patientId], queryFn: () => repo.fetchPatient(patientId), enabled }));
}

/// Every appointment on one chart, newest first, carrying consultation notes
/// when the user may see them. Refreshed with the working set (see
/// refreshAppointments), so a booking or a status change made elsewhere in
/// the app shows up here too.
export function usePatientHistory(patientId: string): AsyncValue<Appointment[]> {
  const repo = useRepository();
  const withNotes = useCanSeeClinicalNotes();
  return fromQuery(
    useQuery({
      queryKey: ['patientHistory', patientId, withNotes.value ?? false],
      queryFn: () => repo.fetchPatientHistory(patientId, withNotes.value ?? false),
      enabled: withNotes.hasValue,
    }),
  );
}

/// The standing medical note on a chart. Null when there is none, and always
/// null — without a request — for users who may not see it.
export function useChartNote(patientId: string): AsyncValue<ClinicalNote | null> {
  const repo = useRepository();
  const allowed = useCanSeeClinicalNotes();
  return fromQuery(
    useQuery({
      queryKey: ['chartNote', patientId, allowed.value ?? false],
      queryFn: () => (allowed.value ? repo.fetchChartNote(patientId) : null),
      enabled: allowed.hasValue,
    }),
  );
}

/// The consultation note on one appointment. Same rules as useChartNote.
export function useVisitNote(appointmentId: string): AsyncValue<ClinicalNote | null> {
  const repo = useRepository();
  const allowed = useCanSeeClinicalNotes();
  return fromQuery(
    useQuery({
      queryKey: ['visitNote', appointmentId, allowed.value ?? false],
      queryFn: () => (allowed.value ? repo.fetchVisitNote(appointmentId) : null),
      enabled: allowed.hasValue,
    }),
  );
}

export function invalidateNotes(qc: QueryClient): void {
  void qc.invalidateQueries({ queryKey: ['chartNote'] });
  void qc.invalidateQueries({ queryKey: ['visitNote'] });
  void qc.invalidateQueries({ queryKey: ['patientHistory'] });
}
