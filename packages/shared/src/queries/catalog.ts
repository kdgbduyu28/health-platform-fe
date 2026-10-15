import { type QueryClient, keepPreviousData, useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';

import type { Doctor } from '../models/doctor';
import type { ClinicMembership } from '../models/membership';
import { type Patient, type PatientFlag, PatientPage, type PatientSort } from '../models/patient';
import type { Service } from '../models/service';
import type { TimeOff } from '../models/time_off';
import { useCurrentUserId, useRepository } from '../state/platform';
import { formatDay, startOfDay } from '../util/dates';
import { type AsyncValue, fromQuery, mapAsync } from './async_value';
import { useCurrentClinicId, useMyPatients } from './clinic';

/// [value], once it has stopped changing for [ms]. Typing a name sends one
/// request rather than one per letter.
export function useDebounced<T>(value: T, ms: number): T {
  const [settled, setSettled] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setSettled(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return settled;
}

/// Active doctors at the current clinic. Empty until the clinic resolves.
export function useDoctors(): AsyncValue<Doctor[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({ queryKey: ['doctors', clinicId], queryFn: () => (clinicId == null ? [] : repo.fetchDoctors(clinicId)) }),
  );
}

/// The bookable service catalogue at the current clinic.
export function useServices(): AsyncValue<Service[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({ queryKey: ['services', clinicId], queryFn: () => (clinicId == null ? [] : repo.fetchServices(clinicId)) }),
  );
}

/// Charts at the current clinic matching what was typed — the first few, for
/// a picker. Searched in the database, so the clinic's whole patient list is
/// never downloaded to find one person.
///
/// Waits a moment before asking, so typing a name sends one request rather
/// than one per letter.
export function usePatientSearch(query: string, enabled = true): AsyncValue<Patient[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const q = useDebounced(query, 250);
  return fromQuery(
    useQuery({
      queryKey: ['patientSearch', clinicId, q],
      queryFn: async () => {
        if (clinicId == null) return [];
        const page = await repo.searchPatients(clinicId, { query: q.trim() === '' ? null : q, limit: 8 });
        return page.patients.map((l) => l.patient);
      },
      placeholderData: keepPreviousData,
      enabled,
    }),
  );
}

/// How many charts the current clinic holds.
export function usePatientCount(): AsyncValue<number> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({
      queryKey: ['patientCount', clinicId],
      queryFn: async () => (clinicId == null ? 0 : (await repo.searchPatients(clinicId, { limit: 1 })).total),
    }),
  );
}

/// What the patient list is showing: the search, the remark filters, the
/// sort, and which page (zero-based).
export type PatientTableQuery = {
  search: string;
  filters: ReadonlySet<PatientFlag>;
  sort: PatientSort;
  descending: boolean;
  page: number;
  pageSize: number;
};

export const defaultPatientTableQuery: PatientTableQuery = {
  search: '',
  filters: new Set(),
  sort: 'name',
  descending: false,
  page: 0,
  pageSize: 25,
};

/// One page of the patient list. Searching waits a moment, like
/// usePatientSearch, so typing a name sends one request.
export function usePatientTable(query: PatientTableQuery): AsyncValue<PatientPage> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const search = useDebounced(query.search.trim(), query.search.trim() === '' ? 0 : 250);
  const filters = [...query.filters].sort();
  return fromQuery(
    useQuery({
      queryKey: ['patientTable', clinicId, search, filters, query.sort, query.descending, query.page, query.pageSize],
      queryFn: () =>
        clinicId == null
          ? new PatientPage([], 0)
          : repo.searchPatients(clinicId, {
              query: search === '' ? null : search,
              offset: query.page * query.pageSize,
              limit: query.pageSize,
              filters: query.filters,
              sort: query.sort,
              descending: query.descending,
            }),
      placeholderData: keepPreviousData,
    }),
  );
}

/// After registering a patient, every list of them is stale.
export function invalidatePatientLists(qc: QueryClient): void {
  for (const k of ['patientSearch', 'patientCount', 'patientTable']) void qc.invalidateQueries({ queryKey: [k] });
}

/// The signed-in patient's chart at the current clinic. Null for staff.
export function useMyPatient(): AsyncValue<Patient | null> {
  const clinicId = useCurrentClinicId();
  return mapAsync(useMyPatients(), (charts) => charts.find((c) => c.clinicId === clinicId) ?? null);
}

/// Roster rows linked to the signed-in account, across every clinic.
export function useMyDoctors(): AsyncValue<Doctor[]> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(useQuery({ queryKey: ['myDoctors', uid], queryFn: () => repo.fetchMyDoctors() }));
}

/// The signed-in doctor's roster row at the current clinic.
export function useCurrentDoctor(): AsyncValue<Doctor | null> {
  const clinicId = useCurrentClinicId();
  return mapAsync(useMyDoctors(), (rows) => rows.find((r) => r.clinicId === clinicId) ?? null);
}

/// Everyone on staff at the current clinic. Admin app only.
export function useStaff(): AsyncValue<ClinicMembership[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({ queryKey: ['staff', clinicId], queryFn: () => (clinicId == null ? [] : repo.fetchStaff(clinicId)) }),
  );
}

/// The whole roster at the current clinic, inactive doctors included. Admin.
export function useRoster(): AsyncValue<Doctor[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({ queryKey: ['roster', clinicId], queryFn: () => (clinicId == null ? [] : repo.fetchRoster(clinicId)) }),
  );
}

/// The whole catalogue at the current clinic, retired services included.
export function useCatalogue(): AsyncValue<Service[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({
      queryKey: ['catalogue', clinicId],
      queryFn: () => (clinicId == null ? [] : repo.fetchCatalogue(clinicId)),
    }),
  );
}

/// Leave and closures at the current clinic that have not ended yet.
export function useTimeOff(): AsyncValue<TimeOff[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({ queryKey: ['timeOff', clinicId], queryFn: () => (clinicId == null ? [] : repo.fetchTimeOff(clinicId)) }),
  );
}

/// What a booking screen may offer: see `public.available_slots`. When
/// moving a visit, [ignore] is that visit, so it does not block itself.
export type SlotQuery = { doctorId: string; day: Date; serviceId?: string | null; ignore?: string | null };

export function useAvailableSlots(q: SlotQuery | null): AsyncValue<Date[]> {
  const repo = useRepository();
  const day = q == null ? null : startOfDay(q.day);
  return fromQuery(
    useQuery({
      queryKey: ['slots', q?.doctorId, day == null ? null : formatDay(day), q?.serviceId ?? null, q?.ignore ?? null],
      queryFn: () =>
        repo.fetchAvailableSlots({
          doctorId: q!.doctorId,
          day: day!,
          serviceId: q!.serviceId,
          ignoreAppointmentId: q!.ignore,
        }),
      enabled: q != null,
      staleTime: 0,
    }),
  );
}

/// After an admin changes the roster, catalogue or time off, every view of
/// them — booking screens included — must refetch.
export function invalidateCatalog(qc: QueryClient): void {
  for (const k of ['doctors', 'services', 'roster', 'catalogue', 'timeOff', 'slots']) {
    void qc.invalidateQueries({ queryKey: [k] });
  }
}
