import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useMemo } from 'react';

import { calendarFeedUrl } from '../calendar/calendar_links';
import type { CalendarRange } from '../calendar/calendar_math';
import { SupabaseConfig } from '../config/supabase_config';
import type { AppNotification } from '../models/app_notification';
import type { AppRole } from '../models/app_role';
import type { Appointment } from '../models/appointment';
import { type AuditArea, AuditEntry, type AuditPage, auditAreaMeta } from '../models/audit_entry';
import type { ImportBatch } from '../models/data_import';
import { DentalChart, type DentalEntry } from '../models/dental_chart';
import type { PatientIntake } from '../models/patient_intake';
import { useAppRole, useCurrentUserId, usePlatform, useRepository } from '../state/platform';
import { type AsyncValue, fromQuery } from './async_value';
import { useAppointmentWindowStart, useClinicAppointments } from './appointments';
import { useCurrentClinic, useCurrentClinicId } from './clinic';
import { useCurrentClinicRole } from './clinical';

// ── Imports ─────────────────────────────────────────────────────────────────

/// The current clinic's recent imports, newest first.
export function useImportBatches(): AsyncValue<ImportBatch[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({
      queryKey: ['importBatches', clinicId],
      queryFn: () => (clinicId == null ? [] : repo.fetchImportBatches(clinicId)),
    }),
  );
}

// ── Dental chart ────────────────────────────────────────────────────────────

/// Whether the clinic being shown charts teeth — its vertical's `chart_kind`
/// is `dental`. Every dental screen checks this, so an eye clinic never sees
/// a tooth.
export function useClinicChartsTeeth(): boolean {
  return useCurrentClinic().value?.isDental ?? false;
}

/// Every entry on one chart's dental chart, oldest first.
///
/// Staff read the table (with notes); the patient app reads the patient's own
/// chart through `patient_dental_chart`, which leaves the notes out — a
/// patient has no direct read of the table at all.
export function useDentalEntries(patientId: string): AsyncValue<DentalEntry[]> {
  const repo = useRepository();
  const app = useAppRole();
  const uid = useCurrentUserId();
  return fromQuery(
    useQuery({
      queryKey: ['dentalEntries', uid, app, patientId],
      queryFn: () => (app === 'patient' ? repo.fetchMyDentalChart(patientId) : repo.fetchDentalEntries(patientId)),
    }),
  );
}

/// One chart's entries folded into the picture: see DentalChart.
export function useDentalChart(patientId: string): AsyncValue<DentalChart> {
  const entries = useDentalEntries(patientId);
  const chart = useMemo(() => (entries.value ? new DentalChart(entries.value) : undefined), [entries.value]);
  return chart === undefined ? (entries as unknown as AsyncValue<DentalChart>) : { ...entries, value: chart };
}

// ── Patient information form ────────────────────────────────────────────────

/// The patient information form on one chart; null if never filled in.
export function useIntake(patientId: string): AsyncValue<PatientIntake | null> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(useQuery({ queryKey: ['intake', uid, patientId], queryFn: () => repo.fetchIntake(patientId) }));
}

/// Whether the signed-in staff account has set its tablet PIN.
export function useHasStaffPin(): AsyncValue<boolean> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(
    useQuery({ queryKey: ['hasStaffPin', uid], queryFn: () => (uid == null ? false : repo.hasStaffPin()) }),
  );
}

// ── Notifications ───────────────────────────────────────────────────────────

/// This app's inbox for the signed-in account, newest first, kept live over
/// Realtime: any change to the account's rows refetches it.
export function useNotifications(): AsyncValue<AppNotification[]> {
  const { repo, app } = usePlatform();
  const uid = useCurrentUserId();
  const qc = useQueryClient();
  const key = ['notifications', uid, app];
  useEffect(() => {
    if (uid == null) return;
    return repo.watchNotifications(uid, () => void qc.invalidateQueries({ queryKey: ['notifications', uid, app] }));
  }, [repo, qc, uid, app]);
  return fromQuery(useQuery({ queryKey: key, queryFn: () => (uid == null ? [] : repo.fetchNotifications(app)) }));
}

export function useUnreadNotifications(): number {
  const list = useNotifications().value;
  return useMemo(() => (list ?? []).filter((n) => !n.isRead).length, [list]);
}

/// Where this browser stands on push notifications for this app.
///
/// `unsupported`: the browser has no Push API. `needs_home_screen`: iPhone or
/// iPad Safari, where push works once the site is on the home screen.
/// `blocked`: the person blocked notifications for this site; only browser
/// settings can undo that.
export type PushState = 'unsupported' | 'needs_home_screen' | 'blocked' | 'off' | 'on';

export function usePushState(): AsyncValue<PushState> {
  const { repo, push, app } = usePlatform();
  const uid = useCurrentUserId();
  return fromQuery(
    useQuery({
      queryKey: ['pushState', uid, app],
      queryFn: async (): Promise<PushState> => {
        if (!push.supported) return push.needsHomeScreenInstall ? 'needs_home_screen' : 'unsupported';
        if (push.permission === 'denied') return 'blocked';
        const keys = await push.current();
        if (keys == null || uid == null) return 'off';
        // Re-register on every start: it costs one call, and heals a row
        // lost to an expired subscription or a sign-in by someone else.
        await repo.savePushSubscription({ app, ...keys, userAgent: push.userAgent });
        return 'on';
      },
      staleTime: Infinity,
    }),
  );
}

export function usePushActions() {
  const { repo, push, app } = usePlatform();
  const uid = useCurrentUserId();
  const qc = useQueryClient();
  const key = ['pushState', uid, app];
  return {
    /// Asks the browser, subscribes, and registers the subscription.
    enable: async () => {
      const keys = await push.subscribe(SupabaseConfig.vapidPublicKey);
      if (keys == null) {
        qc.setQueryData(key, push.permission === 'denied' ? 'blocked' : 'off');
        return;
      }
      await repo.savePushSubscription({ app, ...keys, userAgent: push.userAgent });
      qc.setQueryData(key, 'on');
    },
    disable: async () => {
      const keys = await push.current();
      if (keys != null) await repo.deletePushSubscription(keys.endpoint);
      await push.unsubscribe();
      qc.setQueryData(key, 'off');
    },
  };
}

/// The kinds switched off in this app for the signed-in account.
export function useNotificationMutes(): AsyncValue<Set<string>> {
  const { repo, app } = usePlatform();
  const uid = useCurrentUserId();
  return fromQuery(
    useQuery({ queryKey: ['notificationMutes', uid, app], queryFn: () => repo.fetchNotificationMutes(app) }),
  );
}

/// Flips a kind on screen at once, and back if the save fails.
export function useSetNotificationEnabled(): (kind: string, enabled: boolean) => Promise<void> {
  const { repo, app } = usePlatform();
  const uid = useCurrentUserId();
  const qc = useQueryClient();
  const key = ['notificationMutes', uid, app];
  return async (kind, enabled) => {
    const before = qc.getQueryData<Set<string>>(key) ?? new Set<string>();
    const next = new Set(before);
    if (enabled) next.delete(kind);
    else next.add(kind);
    qc.setQueryData(key, next);
    try {
      await repo.setNotificationMuted(app, kind, !enabled);
    } catch (e) {
      qc.setQueryData(key, before);
      throw e;
    }
  };
}

// ── Activity log ────────────────────────────────────────────────────────────

export const auditPageSize = 50;

/// Reads the activity log (`public.audit_entries`), newest first. The
/// database returns rows to the clinic's admins only; for anyone else every
/// page is empty. [beforeId] continues from the last entry of the previous
/// page, so entries logged while someone reads do not shift the pages.
export async function fetchAuditPage(
  client: ReturnType<typeof usePlatform>['supabase'],
  args: { clinicId: string; patientId?: string | null; area?: AuditArea | null; beforeId?: number | null },
): Promise<AuditPage> {
  let q = client.from('audit_entries').select().eq('clinic_id', args.clinicId);
  if (args.patientId != null) q = q.eq('patient_id', args.patientId);
  if (args.area != null) q = q.in('table_name', [...auditAreaMeta[args.area].tables]);
  if (args.beforeId != null) q = q.lt('id', args.beforeId);
  const { data, error } = await q.order('id', { ascending: false }).limit(auditPageSize + 1);
  if (error) throw error;
  const rows = (data ?? []) as Record<string, unknown>[];
  return { entries: rows.slice(0, auditPageSize).map(AuditEntry.fromJson), hasMore: rows.length > auditPageSize };
}

/// Whether the signed-in user may read the activity log here: admins only,
/// as `audit_log_select_admin` decides.
export function useCanSeeAuditLog(): boolean {
  return useCurrentClinicRole().value === 'admin';
}

// ── Calendar ────────────────────────────────────────────────────────────────

/// The visits at the current clinic in [range] that the signed-in user may
/// see — RLS decides whose; the calendar screen narrows further (one doctor,
/// one patient).
///
/// A page inside the loaded working set (a week ago onward) is read from it,
/// so it moves the moment a visit is booked, checked in or moved. A page that
/// reaches further back is fetched on its own, and fetched again whenever the
/// working set reloads (refreshAppointments includes it).
export function useCalendarAppointments(range: CalendarRange): AsyncValue<Appointment[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const windowStart = useAppointmentWindowStart();
  const inWindow = range.from.getTime() >= windowStart.getTime();
  const working = useClinicAppointments();
  const fetched = fromQuery(
    useQuery({
      queryKey: ['calendarRange', clinicId, range.from.getTime(), range.to.getTime()],
      queryFn: () => (clinicId == null ? [] : repo.fetchAppointmentsBetween(clinicId, range.from, range.to)),
      enabled: !inWindow,
    }),
  );
  const from = range.from.getTime();
  const to = range.to.getTime();
  const sliced = useMemo(
    () => working.value?.filter((a) => a.dateTime.getTime() >= from && a.dateTime.getTime() < to),
    [working.value, from, to],
  );
  if (!inWindow) return fetched;
  return sliced === undefined ? working : { ...working, value: sliced };
}

/// The signed-in account's calendar feed URL. Asking makes the feed on the
/// first call, so this is read only once the patient opens the subscribe
/// sheet, never on a screen they merely pass through.
export function useCalendarFeedUrl(): AsyncValue<string | null> {
  const { supabase } = usePlatform();
  const uid = useCurrentUserId();
  return fromQuery(
    useQuery({
      queryKey: ['calendarFeedUrl', uid],
      queryFn: async () => {
        if (uid == null) return null;
        const { data, error } = await supabase.rpc('my_calendar_feed_token');
        if (error) throw error;
        return calendarFeedUrl(data as string);
      },
    }),
  );
}

/// A new URL for the feed; every copy of the old one stops working.
export function useResetCalendarFeed(): () => Promise<void> {
  const { supabase } = usePlatform();
  const qc = useQueryClient();
  return async () => {
    const { error } = await supabase.rpc('reset_calendar_feed_token');
    if (error) throw error;
    await qc.invalidateQueries({ queryKey: ['calendarFeedUrl'] });
  };
}
