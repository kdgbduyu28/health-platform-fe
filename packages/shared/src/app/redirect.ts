import { type AppRole, registersPatients } from '../models/app_role';
import type { Clinic } from '../models/clinic';
import type { ClinicPage } from '../models/clinic_page';
import type { ClinicMembership } from '../models/membership';
import type { Patient } from '../models/patient';
import type { AsyncValue } from '../queries/async_value';
import { type KioskSession, kioskPath } from '../state/kiosk';
import { clinicHome, reservedSlugs, safeNext } from './paths';

/// Who may see which page is decided in one place, here, and re-decided
/// whenever sign-in state or the user's clinics change:
///
///   /                      sign in, or straight to the user's first clinic
///   /not-found             no active clinic has that slug
///   /privacy, /terms       the Privacy Policy and the Terms, for anyone
///   /:clinic               the public page (patient app); the app's home
///                          tab everywhere else
///   /:clinic/sign-in       that clinic's branded sign-in; `?next=` returns
///   /:clinic/join          patient app: join with the clinic's code
///   /:clinic/staff-code    doctor and assistant apps: request access
///   /:clinic/no-access     admin app: signed in, but not an admin here
///   /:clinic/intake        patient app: the information form; until it is
///                          filled in, every page at the clinic leads here
///   /:clinic/kiosk         staff apps: the tablet handed to a patient;
///                          while one is on, EVERY page leads here
///   /:clinic/…             the app's own pages
export type RedirectInput = {
  app: AppRole;
  /// The patient app shows a public page at `/:clinic`.
  hasLanding: boolean;
  path: string;
  /// The query string, with its `?`, or empty.
  search: string;
  /// Signed in, and not in the middle of a password reset — which signs the
  /// user in before they have chosen a new password.
  signedIn: boolean;
  kiosk: KioskSession | null;
  lastClinicSlug: string | null;
  /// The clinics this app can be used at. Only read when signed in.
  clinics: AsyncValue<Clinic[]>;
  /// The public page of the clinic in the path. Only read when it is not one
  /// of the user's clinics.
  clinicPage: AsyncValue<ClinicPage | null>;
  /// Only read by the admin app, at a clinic the user is not an admin of.
  memberships: AsyncValue<ClinicMembership[]>;
  /// Only read by the patient app, for its first-visit form gate.
  myPatients: AsyncValue<Patient[]>;
};

export type RedirectDecision =
  /// Show the page asked for.
  | { kind: 'stay'; memberSlug?: string }
  /// Show [to] instead.
  | { kind: 'go'; to: string }
  /// Not enough is known yet to decide.
  | { kind: 'wait' };

const stay = (memberSlug?: string): RedirectDecision => ({ kind: 'stay', memberSlug });
const go = (to: string): RedirectDecision => ({ kind: 'go', to });
const wait: RedirectDecision = { kind: 'wait' };

/// Gates a member never needs: `kiosk` without a session (ended, or a stale
/// link) is one too.
const memberGates = new Set(['join', 'staff-code', 'no-access', 'kiosk']);

export function pathSegments(path: string): string[] {
  return path.split('/').filter((s) => s !== '');
}

export function decideRedirect(input: RedirectInput): RedirectDecision {
  const { app, signedIn, path } = input;
  const segments = pathSegments(path);

  // ── The tablet is in a patient's hands ──
  // Before anything else, so no URL — typed, bookmarked or the back
  // button's — reaches the app until a staff PIN ends the session.
  if (signedIn && registersPatients(app) && input.kiosk != null) {
    const target = kioskPath(input.kiosk);
    return path === target ? stay() : go(target);
  }

  // ── `/` ──
  if (segments.length === 0) {
    if (!signedIn) return stay();
    const clinics = input.clinics;
    // The list failed to load: the root screen shows that and offers a retry.
    if (!clinics.hasValue) return clinics.hasError ? stay() : wait;
    const list = clinics.value!;
    // Nothing yet: the root screen asks for a join or staff code.
    if (list.length === 0) return stay();
    // Back to where they were last time, if they still belong there.
    const last = input.lastClinicSlug;
    const slug = list.some((c) => c.slug === last) ? last! : list[0].slug;
    return go(clinicHome(slug, app));
  }

  const first = decodeURIComponent(segments[0]);
  const slug = first.toLowerCase();
  // Pages that belong to no clinic.
  if (reservedSlugs.has(slug)) return stay();
  // One spelling per clinic, so a link typed in capitals still matches.
  if (slug !== first) return go(`/${[slug, ...segments.slice(1)].join('/')}${input.search}`);
  const sub = segments.length > 1 ? segments[1] : null;

  let clinics: Clinic[] = [];
  if (signedIn) {
    // The list failed to load; let the screen show that and offer a retry
    // rather than guess where to send them.
    if (!input.clinics.hasValue) return input.clinics.hasError ? stay() : wait;
    clinics = input.clinics.value!;
  }
  const isMember = clinics.some((c) => c.slug === slug);

  // Members pass even if the public page would not show (a suspended
  // clinic): deciding access is the database's job, not the URL's.
  if (!isMember) {
    const page = input.clinicPage;
    // Offline, say: ClinicScope shows the error.
    if (!page.hasValue) return page.hasError ? stay() : wait;
    if (page.value == null) return go('/not-found');
  }

  // ── Signed out ──
  if (!signedIn) {
    if (sub === 'sign-in') return stay();
    if (sub == null && input.hasLanding) return stay();
    return go(`/${slug}/sign-in?next=${encodeURIComponent(path + input.search)}`);
  }

  // ── Signed in ──
  const home = clinicHome(slug, app);
  if (sub === 'sign-in') {
    const next = new URLSearchParams(input.search).get('next');
    return go(safeNext(next) ?? home);
  }

  if (isMember) {
    if (sub != null && memberGates.has(sub)) return go(home);
    if (app === 'patient' && sub !== 'intake') {
      const clinicId = clinics.find((c) => c.slug === slug)!.id;
      const charts = input.myPatients;
      // The gate is for first-time patients, and not worth locking anyone
      // out over: when it cannot be told (offline), they pass.
      if (!charts.hasValue && !charts.hasError) return wait;
      const chart = charts.value?.find((c) => c.clinicId === clinicId);
      if (chart?.hasIntake === false) return go(`/${slug}/intake`);
    }
    return stay(slug);
  }

  // Signed in at a clinic this app is not theirs at. The patient app still
  // shows the public page, which offers to join.
  if (sub == null && input.hasLanding) return stay();
  switch (app) {
    case 'patient':
      return sub === 'join' ? stay() : go(`/${slug}/join`);
    case 'doctor':
    case 'assistant':
      return sub === 'staff-code' ? stay() : go(`/${slug}/staff-code`);
    case 'admin': {
      // A branch admin has exactly one branch; any other is a wrong turn,
      // not a request for access.
      const memberships = input.memberships;
      if (!memberships.hasValue && !memberships.hasError) return wait;
      for (const m of memberships.value ?? []) {
        if (!m.branchLocked) continue;
        const branch = clinics.find((c) => c.id === m.clinicId);
        if (branch) return go(clinicHome(branch.slug, app));
      }
      return sub === 'no-access' ? stay() : go(`/${slug}/no-access`);
    }
  }
}
