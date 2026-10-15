import { useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query';
import { usePathname } from 'expo-router';
import { useMemo } from 'react';

import type { Clinic } from '../models/clinic';
import { type ClinicMembership, eligibleClinicIds } from '../models/membership';
import type { Profile } from '../models/profile';
import type { StaffInvite } from '../models/staff_invite';
import { clinicSlugOf } from '../app/paths';
import { useAppRole, useCurrentUserId, useRepository } from '../state/platform';
import { type AsyncValue, asyncData, combineAsync, fromQuery, mapAsync } from './async_value';

/// The clinic slug in the URL. The URL is the only record of which clinic
/// is open: that is what makes a clinic bookmarkable and survive a reload.
export function useRouteClinicSlug(): string | null {
  return clinicSlugOf(usePathname());
}

/// The signed-in user's profile row.
export function useMyProfile(): AsyncValue<Profile | null> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(useQuery({ queryKey: ['profile', uid], queryFn: () => repo.fetchMyProfile() }));
}

/// The signed-in account's staff roles, one per clinic.
export function useMyMemberships(): AsyncValue<ClinicMembership[]> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(useQuery({ queryKey: ['memberships', uid], queryFn: () => repo.fetchMyMemberships() }));
}

/// Every chart the signed-in account holds, one per clinic joined.
export function useMyPatients() {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(useQuery({ queryKey: ['myPatients', uid], queryFn: () => repo.fetchMyPatients() }));
}

/// Every clinic RLS lets this user read — as staff anywhere or as a patient
/// anywhere. Broader than what any one app should offer; see useMyClinics.
export function useVisibleClinics(): AsyncValue<Clinic[]> {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(useQuery({ queryKey: ['visibleClinics', uid], queryFn: () => repo.fetchClinics() }));
}

/// The clinics this user can use THIS app at.
///
/// An account can be a doctor at one clinic and a patient at another. The
/// doctor app must not offer the second, and the patient app must not offer
/// the first — so the clinics RLS returns are narrowed by the app's role:
/// charts for the patient app, a matching membership for the staff apps.
export function useMyClinics(): AsyncValue<Clinic[]> {
  const app = useAppRole();
  const uid = useCurrentUserId();
  const repo = useRepository();
  const signedIn = uid != null;
  // Signed out, RLS would return nothing anyway; skip the round trips.
  const charts = fromQuery(
    useQuery({ queryKey: ['myPatients', uid], queryFn: () => repo.fetchMyPatients(), enabled: signedIn && app === 'patient' }),
  );
  const memberships = fromQuery(
    useQuery({
      queryKey: ['memberships', uid],
      queryFn: () => repo.fetchMyMemberships(),
      enabled: signedIn && app !== 'patient',
    }),
  );
  const clinics = fromQuery(
    useQuery({ queryKey: ['visibleClinics', uid], queryFn: () => repo.fetchClinics(), enabled: signedIn }),
  );

  const eligible: AsyncValue<string[]> =
    app === 'patient'
      ? mapAsync(charts, (list) => eligibleClinicIds(app, list, []))
      : mapAsync(memberships, (list) => eligibleClinicIds(app, [], list));

  const combined = combineAsync<[string[], Clinic[]]>([eligible, clinics]);
  const [ids, all] = combined.value ?? [undefined, undefined];
  const mine = useMemo(() => {
    if (ids == null || all == null) return undefined;
    const set = new Set(ids);
    return all.filter((c) => set.has(c.id));
  }, [ids, all]);

  if (!signedIn) return SIGNED_OUT;
  return mine === undefined ? (combined as unknown as AsyncValue<Clinic[]>) : { ...combined, value: mine };
}

const SIGNED_OUT: AsyncValue<Clinic[]> = asyncData([]);

/// Drops what decides which clinics this user can use here, so it is asked
/// again: after joining a clinic, being approved or removed.
export function refreshAccess(qc: QueryClient): Promise<void> {
  return Promise.all([
    qc.invalidateQueries({ queryKey: ['memberships'] }),
    qc.invalidateQueries({ queryKey: ['myPatients'] }),
    qc.invalidateQueries({ queryKey: ['visibleClinics'] }),
  ]).then(() => undefined);
}

export function useRefreshAccess(): () => Promise<void> {
  const qc = useQueryClient();
  return () => refreshAccess(qc);
}

/// The public page of the clinic at a slug; null when no active clinic has
/// it. Readable signed out.
export function useClinicPage(slug: string | null, enabled = true) {
  const repo = useRepository();
  return fromQuery(
    useQuery({
      queryKey: ['clinicPage', slug],
      queryFn: () => repo.fetchClinicPage(slug!),
      enabled: enabled && slug != null,
      staleTime: 5 * 60_000,
    }),
  );
}

/// The clinic in the URL, if this user may use this app there.
///
/// Null at a clinic they do not belong to (the router shows them the join or
/// staff-code screen instead), and never a clinic outside useMyClinics.
export function useCurrentClinic(): AsyncValue<Clinic | null> {
  const slug = useRouteClinicSlug();
  const clinics = useMyClinics();
  return mapAsync(clinics, (list) => list.find((c) => c.slug === slug) ?? null);
}

/// The clinic to brand the screen with: the user's own row when they belong
/// to the clinic in the URL, otherwise its public page — so the sign-in, join
/// and landing screens wear the clinic's colours too. Null outside a clinic.
export function useRouteBrandClinic(): Clinic | null {
  const slug = useRouteClinicSlug();
  const current = useCurrentClinic();
  const page = useClinicPage(slug, slug != null);
  if (slug == null) return null;
  return current.value ?? page.value?.clinic ?? null;
}

/// Every write needs the clinic's id; screens read it from here.
export function useCurrentClinicId(): string | null {
  return useCurrentClinic().value?.id ?? null;
}

/// The signed-in account's staff membership at the current clinic, if any.
export function useCurrentMembership(): ClinicMembership | null {
  const clinicId = useCurrentClinicId();
  const memberships = useMyMemberships();
  return memberships.value?.find((m) => m.clinicId === clinicId) ?? null;
}

/// Whether the signed-in account may manage the current clinic's admins —
/// false for a branch admin. Mirrors `private.is_full_admin`.
export function useIsFullAdmin(): boolean {
  return useCurrentMembership()?.isFullAdmin ?? false;
}

/// Every staff code issued at the current clinic. Admin app only.
export function useStaffInvites(): AsyncValue<StaffInvite[]> {
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  return fromQuery(
    useQuery({
      queryKey: ['staffInvites', clinicId],
      queryFn: () => (clinicId == null ? [] : repo.fetchStaffInvites(clinicId)),
    }),
  );
}

/// Requests at the current clinic still waiting for an admin.
export function usePendingStaffRequests(): StaffInvite[] {
  const invites = useStaffInvites().value;
  return useMemo(() => (invites ?? []).filter((i) => i.status === 'pending'), [invites]);
}

/// The signed-in account's own requests to join clinics as staff.
export function useMyStaffRequests() {
  const repo = useRepository();
  const uid = useCurrentUserId();
  return fromQuery(useQuery({ queryKey: ['myStaffRequests', uid], queryFn: () => repo.fetchMyStaffRequests() }));
}

/// Any clinic this user can see, by id — for labelling records (an
/// appointment's clinic) without refetching.
export function useClinicById(id: string | null): Clinic | null {
  const clinics = useVisibleClinics().value;
  return clinics?.find((c) => c.id === id) ?? null;
}
