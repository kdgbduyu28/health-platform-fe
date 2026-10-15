import { type QueryClient, useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/react-query';
import { useMemo } from 'react';

import type { Appointment } from '../models/appointment';
import { type AppointmentStatus, holdsTime } from '../models/appointment_status';
import { useCurrentUserId, useRepository } from '../state/platform';
import { addDays, startOfDay } from '../util/dates';
import { type AsyncValue, fromQuery, mapAsync } from './async_value';
import { useCurrentDoctor, useMyPatient } from './catalog';
import { useCurrentClinicId } from './clinic';

/// Where the working set of appointments begins: a week before today, so the
/// schedule can look back a few days and "last visit" is at hand. Everything
/// older is read on demand — see usePastAppointments.
///
/// Fixed for each signed-in user (like the provider it replaces, which
/// recomputed only on sign-in), so every screen shares one cached list.
const windowStarts = new Map<string | null, Date>();

export function appointmentWindowStart(uid: string | null): Date {
  let start = windowStarts.get(uid);
  if (start == null) {
    start = addDays(startOfDay(new Date()), -7);
    windowStarts.set(uid, start);
  }
  return start;
}

export function useAppointmentWindowStart(): Date {
  return appointmentWindowStart(useCurrentUserId());
}

/// Every appointment the signed-in user is allowed to see from the window
/// start on.
///
/// There is no role filtering here on purpose — RLS decides the rows. A
/// patient gets their own bookings at every clinic they have joined, staff
/// get the bookings of every clinic they work at, and a signed-out caller
/// gets nothing. The hooks below narrow that to the current clinic.
export function useAppointments(): AsyncValue<Appointment[]> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  const since = appointmentWindowStart(uid);
  return fromQuery(
    useQuery({
      queryKey: ['appointments', uid, since.getTime()],
      queryFn: () => (uid == null ? [] : repo.fetchAppointments(since)),
    }),
  );
}

/// Refetches the working set and every other view of the same rows: visits
/// read one by one, older pages, a chart's history, calendar pages.
export async function refreshAppointments(qc: QueryClient): Promise<void> {
  await Promise.all(
    ['appointments', 'appointment', 'pastAppointments', 'patientHistory', 'calendarRange'].map((k) =>
      qc.invalidateQueries({ queryKey: [k] }),
    ),
  );
}

/// What a screen does to visits, each followed by a refresh — even a write
/// that failed half way, since part of it may be on file.
export function useAppointmentActions() {
  const repo = useRepository();
  const qc = useQueryClient();
  const refresh = () => refreshAppointments(qc);
  const after = async <T,>(work: Promise<T>): Promise<T> => {
    try {
      return await work;
    } finally {
      await refresh();
    }
  };

  return {
    refresh,

    book: (args: {
      clinicId: string;
      patientId: string;
      doctorId: string;
      serviceName: string;
      scheduledAt: Date;
      serviceId?: string | null;
      status?: AppointmentStatus;
    }) => after(repo.book(args)),

    /// Enters a visit that happened but was never logged: for [patientId] on
    /// file, or for someone new ([newPatientName], [newPatientPhone]) whose
    /// chart is registered with it. With [complete] (doctors and admins) it
    /// is marked completed; otherwise it stays confirmed for one of them to
    /// close.
    recordMissedVisit: (args: {
      clinicId: string;
      patientId?: string | null;
      newPatientName?: string | null;
      newPatientPhone?: string | null;
      doctorId: string;
      serviceName: string;
      scheduledAt: Date;
      serviceId?: string | null;
      complete: boolean;
    }) =>
      after(
        (async () => {
          const id =
            args.patientId != null
              ? await repo.recordPastVisit({
                  clinicId: args.clinicId,
                  patientId: args.patientId,
                  doctorId: args.doctorId,
                  serviceName: args.serviceName,
                  scheduledAt: args.scheduledAt,
                  serviceId: args.serviceId,
                })
              : await repo.bookWalkIn({
                  clinicId: args.clinicId,
                  fullName: args.newPatientName!,
                  phone: args.newPatientPhone!,
                  doctorId: args.doctorId,
                  serviceName: args.serviceName,
                  scheduledAt: args.scheduledAt,
                  serviceId: args.serviceId,
                });
          if (args.complete) await repo.completeRecordedVisit(id);
        })(),
      ),

    /// Registers a walk-in and books them in one transaction. Returns the new
    /// appointment id.
    bookWalkIn: (args: Parameters<typeof repo.bookWalkIn>[0]) => after(repo.bookWalkIn(args)),

    updateStatus: (id: string, status: AppointmentStatus) => after(repo.updateStatus(id, status)),

    /// Moves a visit; see HealthRepository.reschedule.
    reschedule: (id: string, to: Date, doctorId?: string | null) => after(repo.reschedule(id, to, doctorId)),

    /// The note the patient reads. Blank clears it. The database refuses this
    /// from anyone but the clinic's doctors and admins.
    updatePatientNote: (id: string, note: string | null) => after(repo.updatePatientNote(id, note)),
  };
}

function byTime(a: Appointment, b: Appointment) {
  return a.dateTime.getTime() - b.dateTime.getTime();
}

/// Appointments at the clinic the app is currently showing.
export function useClinicAppointments(): AsyncValue<Appointment[]> {
  const clinicId = useCurrentClinicId();
  const all = useAppointments();
  const list = useMemo(
    () => (all.value ? all.value.filter((a) => a.clinicId === clinicId) : undefined),
    [all.value, clinicId],
  );
  return list === undefined ? all : { ...all, value: list };
}

export function useTodayAppointments(): AsyncValue<Appointment[]> {
  const clinic = useClinicAppointments();
  const list = useMemo(() => clinic.value?.filter((a) => a.isToday).sort(byTime), [clinic.value]);
  return list === undefined ? clinic : { ...clinic, value: list };
}

export function useUpcomingAppointments(): AsyncValue<Appointment[]> {
  const clinic = useClinicAppointments();
  const list = useMemo(() => {
    const now = Date.now();
    return clinic.value?.filter((a) => a.dateTime.getTime() > now && holdsTime(a.status)).sort(byTime);
  }, [clinic.value]);
  return list === undefined ? clinic : { ...clinic, value: list };
}

// ── Patient-scoped views ────────────────────────────────────────────────────
// RLS already limits a signed-in patient to their own rows; filtering by
// patient id as well keeps these correct if a staff account ever opens the
// patient app.

export function useMyAppointments(): AsyncValue<Appointment[]> {
  const mine = useMyPatient().value;
  const clinic = useClinicAppointments();
  const list = useMemo(() => {
    if (!clinic.value) return undefined;
    const rows = mine == null ? [...clinic.value] : clinic.value.filter((a) => a.patient.id === mine.id);
    return rows.sort((a, b) => b.dateTime.getTime() - a.dateTime.getTime());
  }, [clinic.value, mine]);
  return list === undefined ? clinic : { ...clinic, value: list };
}

export function useMyUpcomingAppointments(): AsyncValue<Appointment[]> {
  const mine = useMyAppointments();
  const list = useMemo(() => {
    const now = Date.now();
    return mine.value?.filter((a) => a.dateTime.getTime() > now && holdsTime(a.status)).sort(byTime);
  }, [mine.value]);
  return list === undefined ? mine : { ...mine, value: list };
}

// ── Doctor-scoped views ─────────────────────────────────────────────────────

export function useMyDoctorAppointments(): AsyncValue<Appointment[]> {
  const me = useCurrentDoctor().value;
  const clinic = useClinicAppointments();
  const list = useMemo(() => {
    if (!clinic.value) return undefined;
    const rows = me == null ? [...clinic.value] : clinic.value.filter((a) => a.doctor.id === me.id);
    return rows.sort(byTime);
  }, [clinic.value, me]);
  return list === undefined ? clinic : { ...clinic, value: list };
}

export function useMyDoctorToday(): AsyncValue<Appointment[]> {
  const mine = useMyDoctorAppointments();
  const list = useMemo(() => mine.value?.filter((a) => a.isToday), [mine.value]);
  return list === undefined ? mine : { ...mine, value: list };
}

/// One appointment by id: from the loaded window when it is there, else
/// fetched on its own — a visit opened from a patient's history may be years
/// old.
export function useAppointmentById(id: string): AsyncValue<Appointment | null> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  const loaded = useAppointments();
  const inWindow = loaded.value?.find((a) => a.id === id);
  const fetched = fromQuery(
    useQuery({
      queryKey: ['appointment', uid, id],
      queryFn: () => repo.fetchAppointment(id),
      enabled: loaded.hasValue && inWindow == null,
    }),
  );
  if (!loaded.hasValue) return mapAsync(loaded, () => null);
  if (inWindow) return { ...loaded, value: inWindow };
  return fetched;
}

// ── Older visits, a page at a time ──────────────────────────────────────────

export const pastPageSize = 20;

/// Visits before the loaded window at the current clinic, newest first, as
/// far back as has been asked for: one doctor's, one chart's, or (both null)
/// the whole clinic's.
export function usePastAppointments(query: { doctorId?: string | null; patientId?: string | null }) {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const before = useAppointmentWindowStart();
  const q = useInfiniteQuery({
    queryKey: ['pastAppointments', clinicId, query.doctorId ?? null, query.patientId ?? null, before.getTime()],
    initialPageParam: 0,
    queryFn: ({ pageParam }) =>
      clinicId == null
        ? Promise.resolve([] as Appointment[])
        : repo.fetchPastAppointments({
            clinicId,
            before,
            doctorId: query.doctorId,
            patientId: query.patientId,
            offset: pageParam,
            limit: pastPageSize,
          }),
    getNextPageParam: (last, pages) => (last.length === pastPageSize ? pages.length * pastPageSize : undefined),
  });
  const items = useMemo(() => q.data?.pages.flat() ?? [], [q.data]);
  return {
    items,
    hasValue: q.data !== undefined,
    isLoading: q.isPending,
    /// Why the first page failed; nothing to show.
    error: q.data === undefined ? q.error : null,
    /// Why the last "load more" failed; the pages already shown stay.
    loadMoreError: q.data !== undefined && q.isFetchNextPageError ? q.error : null,
    hasMore: q.hasNextPage,
    loadingMore: q.isFetchingNextPage,
    loadMore: () => {
      if (q.hasNextPage && !q.isFetchingNextPage) void q.fetchNextPage();
    },
    retry: () => void q.refetch(),
  };
}
