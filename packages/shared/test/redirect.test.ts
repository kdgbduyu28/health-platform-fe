import { clinicHome, clinicSlugOf, safeNext } from '../src/app/paths';
import { type RedirectDecision, type RedirectInput, decideRedirect } from '../src/app/redirect';
import type { AppRole } from '../src/models/app_role';
import { Clinic } from '../src/models/clinic';
import { ClinicPage } from '../src/models/clinic_page';
import { ClinicMembership, eligibleClinicIds } from '../src/models/membership';
import { Patient } from '../src/models/patient';
import { type AsyncValue, asyncData } from '../src/queries/async_value';
import { parseKioskSession } from '../src/state/kiosk';

// The rules the router applies on every navigation, fed fixed data. A page
// "stays" when it is shown as asked; "go" names where it is sent instead.

const clinic = (id: string, name: string, slug: string) => Clinic.fromJson({ id, name, slug, type: 'dental', clinic_type: { display_name: 'Dental' } });
const dtouch = clinic('dt', 'D-Touch Dental Clinic', 'dtouchdental');
const other = clinic('ot', 'BrightSmile Dental Studio', 'brightsmile');
const publicPages: Record<string, ClinicPage> = { dtouchdental: new ClinicPage(dtouch), brightsmile: new ClinicPage(other) };

const chartAt = (clinicId: string, hasIntake: boolean | null = null) =>
  new Patient(`chart-${clinicId}`, 'person-1', clinicId, 'Juan dela Cruz', '0917', '', null, null, null, null, null, null, hasIntake);
const staffAt = (clinicId: string, role: AppRole, branchLocked = false) =>
  ClinicMembership.fromJson({ profile_id: 'u1', clinic_id: clinicId, role, branch_locked: branchLocked });

type Setup = {
  app: AppRole;
  signedIn?: boolean;
  visible?: Clinic[];
  charts?: Patient[];
  memberships?: ClinicMembership[];
  lastClinicSlug?: string | null;
  kiosk?: string | null;
};

/// Where [location] ends up for [setup], following redirects the way the
/// router does until a page stays.
function land(location: string, setup: Setup): string {
  const { app, signedIn = false, visible = [], charts = [], memberships = [] } = setup;
  // What useMyClinics hands the router: the visible clinics narrowed to
  // this app.
  const ids = new Set(eligibleClinicIds(app, charts, memberships));
  const mine = visible.filter((c) => ids.has(c.id));
  let at = location;
  for (let hops = 0; hops < 10; hops++) {
    const [path, query = ''] = at.split('?');
    const slug = clinicSlugOf(path);
    const input: RedirectInput = {
      app,
      hasLanding: app === 'patient',
      path,
      search: query === '' ? '' : `?${query}`,
      signedIn,
      kiosk: signedIn ? parseKioskSession(setup.kiosk ?? null) : null,
      lastClinicSlug: setup.lastClinicSlug ?? null,
      clinics: asyncData(mine),
      clinicPage: asyncData(slug == null ? null : publicPages[slug] ?? null) as AsyncValue<ClinicPage | null>,
      memberships: asyncData(memberships),
      myPatients: asyncData(charts),
    };
    const d: RedirectDecision = decideRedirect(input);
    if (d.kind === 'stay') return at;
    if (d.kind === 'wait') throw new Error(`waiting at ${at}`);
    at = d.to;
  }
  throw new Error(`redirect loop from ${location}`);
}

describe('signed out, patient app', () => {
  const setup: Setup = { app: 'patient' };

  test('/dtouchdental is the public landing page', () => {
    expect(land('/dtouchdental', setup)).toBe('/dtouchdental');
  });

  test('anything deeper asks them to sign in, then comes back', () => {
    expect(land('/dtouchdental/book', setup)).toBe('/dtouchdental/sign-in?next=%2Fdtouchdental%2Fbook');
  });

  test('an unknown clinic is not found', () => {
    expect(land('/no-such-clinic', setup)).toBe('/not-found');
  });

  test('a slug typed in capitals still opens the clinic', () => {
    expect(land('/DTouchDental', setup)).toBe('/dtouchdental');
  });

  test('/ is the unbranded sign-in, and the legal pages are open to anyone', () => {
    expect(land('/', setup)).toBe('/');
    expect(land('/privacy', setup)).toBe('/privacy');
    expect(land('/terms', setup)).toBe('/terms');
  });
});

describe('signed in, patient app', () => {
  const member: Setup = { app: 'patient', signedIn: true, visible: [dtouch], charts: [chartAt('dt')] };

  test('/ opens their clinic', () => {
    expect(land('/', member)).toBe('/dtouchdental/home');
  });

  test('/ returns to the clinic they used last…', () => {
    const two: Setup = { ...member, visible: [dtouch, other], charts: [chartAt('dt'), chartAt('ot')] };
    expect(land('/', two)).toBe('/dtouchdental/home');
    expect(land('/', { ...two, lastClinicSlug: 'brightsmile' })).toBe('/brightsmile/home');
  });

  test('…but not to one they no longer belong to', () => {
    expect(land('/', { ...member, lastClinicSlug: 'brightsmile' })).toBe('/dtouchdental/home');
  });

  test('signing in follows ?next=', () => {
    expect(land('/dtouchdental/sign-in?next=%2Fdtouchdental%2Fbook', member)).toBe('/dtouchdental/book');
  });

  test('?next= cannot leave the app', () => {
    expect(land('/dtouchdental/sign-in?next=//evil.example', member)).toBe('/dtouchdental/home');
    expect(land('/dtouchdental/sign-in?next=https://evil.example', member)).toBe('/dtouchdental/home');
  });

  test("signing out returns to that clinic's sign-in", () => {
    expect(land('/dtouchdental/home', { app: 'patient' })).toBe('/dtouchdental/sign-in?next=%2Fdtouchdental%2Fhome');
  });

  test('members still see the public page', () => {
    expect(land('/dtouchdental', member)).toBe('/dtouchdental');
  });

  test('at a clinic they have not joined, the app asks for its code', () => {
    const both: Setup = { ...member, visible: [dtouch, other] };
    expect(land('/brightsmile/book', both)).toBe('/brightsmile/join');
    // …but the public page is still theirs to read.
    expect(land('/brightsmile', both)).toBe('/brightsmile');
  });

  test('a member has no business on the join screen', () => {
    expect(land('/dtouchdental/join', member)).toBe('/dtouchdental/home');
  });

  test('no clinic yet: / stays, to ask for a code', () => {
    expect(land('/', { app: 'patient', signedIn: true })).toBe('/');
  });
});

describe('staff apps', () => {
  const doctor: Setup = { app: 'doctor', signedIn: true, visible: [dtouch], memberships: [staffAt('dt', 'doctor')] };

  test('signed out, the clinic link is its sign-in (no landing page)', () => {
    expect(land('/dtouchdental', { app: 'doctor' })).toBe('/dtouchdental/sign-in?next=%2Fdtouchdental');
  });

  test("/:clinic stays, for the index route to send on to the home tab", () => {
    expect(land('/dtouchdental', doctor)).toBe('/dtouchdental');
    expect(land('/', doctor)).toBe('/dtouchdental/schedule');
  });

  test('a doctor at another clinic is offered the staff code', () => {
    expect(land('/brightsmile/schedule', { ...doctor, visible: [dtouch, other] })).toBe('/brightsmile/staff-code');
  });

  test('the front desk lands on check-in', () => {
    expect(land('/', { app: 'assistant', signedIn: true, visible: [dtouch], memberships: [staffAt('dt', 'assistant')] })).toBe('/dtouchdental/check-in');
  });
});

describe('admin app', () => {
  test('a full admin at a clinic that is not theirs has no access', () => {
    const setup: Setup = { app: 'admin', signedIn: true, visible: [dtouch, other], memberships: [staffAt('dt', 'admin')] };
    expect(land('/brightsmile/dashboard', setup)).toBe('/brightsmile/no-access');
  });

  test('a branch admin is always returned to their branch', () => {
    const setup: Setup = { app: 'admin', signedIn: true, visible: [dtouch, other], memberships: [staffAt('dt', 'admin', true)] };
    expect(land('/brightsmile/settings', setup)).toBe('/dtouchdental/dashboard');
  });

  test('a full admin of two branches switches by URL', () => {
    const setup: Setup = { app: 'admin', signedIn: true, visible: [dtouch, other], memberships: [staffAt('dt', 'admin'), staffAt('ot', 'admin')] };
    expect(land('/brightsmile/dashboard', setup)).toBe('/brightsmile/dashboard');
    expect(land('/dtouchdental/dashboard', setup)).toBe('/dtouchdental/dashboard');
  });
});

describe('patient information form', () => {
  test('a patient who never filled it in is sent there first', () => {
    const setup: Setup = { app: 'patient', signedIn: true, visible: [dtouch], charts: [chartAt('dt', false)] };
    expect(land('/', setup)).toBe('/dtouchdental/intake');
    expect(land('/dtouchdental/book', setup)).toBe('/dtouchdental/intake');
  });

  test('…and once they have, the app opens as usual', () => {
    const setup: Setup = { app: 'patient', signedIn: true, visible: [dtouch], charts: [chartAt('dt', true)] };
    expect(land('/', setup)).toBe('/dtouchdental/home');
    // Still there to update from the profile.
    expect(land('/dtouchdental/intake', setup)).toBe('/dtouchdental/intake');
  });

  test('the form is per clinic', () => {
    const setup: Setup = { app: 'patient', signedIn: true, visible: [dtouch, other], charts: [chartAt('dt', true), chartAt('ot', false)] };
    expect(land('/dtouchdental/home', setup)).toBe('/dtouchdental/home');
    expect(land('/brightsmile/home', setup)).toBe('/brightsmile/intake');
  });
});

describe('the tablet handed to a patient', () => {
  const kiosk = '{"slug":"dtouchdental","patient_id":null,"submitted":false}';
  const handedOver = (app: AppRole = 'assistant'): Setup => ({
    app,
    signedIn: true,
    visible: [dtouch, other],
    memberships: [staffAt('dt', app), staffAt('ot', app)],
    kiosk,
  });

  test('every URL leads back to the form', () => {
    const setup = handedOver();
    expect(land('/', setup)).toBe('/dtouchdental/kiosk');
    expect(land('/dtouchdental/patients', setup)).toBe('/dtouchdental/kiosk');
    expect(land('/brightsmile/check-in', setup)).toBe('/dtouchdental/kiosk');
  });

  test('…in the admin app too', () => {
    expect(land('/dtouchdental/dashboard', handedOver('admin'))).toBe('/dtouchdental/kiosk');
  });

  test('ending it opens the app again, and a stale link to the tablet goes home', () => {
    const ended = { ...handedOver(), kiosk: null };
    expect(land('/dtouchdental/patients', ended)).toBe('/dtouchdental/patients');
    expect(land('/dtouchdental/kiosk', ended)).toBe('/dtouchdental/check-in');
  });

  test('signed out, a saved session is not obeyed', () => {
    expect(land('/dtouchdental/patients', { ...handedOver(), signedIn: false })).toBe('/dtouchdental/sign-in?next=%2Fdtouchdental%2Fpatients');
  });

  test('a damaged saved session is ignored', () => {
    expect(parseKioskSession('{oops')).toBeNull();
    expect(parseKioskSession('{"patient_id":"x"}')).toBeNull();
    expect(parseKioskSession(kiosk)).toEqual({ slug: 'dtouchdental', patientId: null, submitted: false });
  });
});

describe('while data is loading', () => {
  test('the decision waits rather than guessing', () => {
    const loading: AsyncValue<never> = { hasValue: false, value: undefined, hasError: false, error: null, isLoading: true };
    const base: RedirectInput = {
      app: 'patient',
      hasLanding: true,
      path: '/',
      search: '',
      signedIn: true,
      kiosk: null,
      lastClinicSlug: null,
      clinics: loading,
      clinicPage: loading,
      memberships: loading,
      myPatients: loading,
    };
    expect(decideRedirect(base).kind).toBe('wait');
    expect(decideRedirect({ ...base, path: '/dtouchdental/home' }).kind).toBe('wait');
  });

  test('a failed load lets the page through, to show the error', () => {
    const failed: AsyncValue<never> = { hasValue: false, value: undefined, hasError: true, error: new Error('offline'), isLoading: false };
    const input: RedirectInput = {
      app: 'doctor',
      hasLanding: false,
      path: '/dtouchdental/schedule',
      search: '',
      signedIn: true,
      kiosk: null,
      lastClinicSlug: null,
      clinics: failed,
      clinicPage: failed,
      memberships: failed,
      myPatients: failed,
    };
    expect(decideRedirect(input).kind).toBe('stay');
  });
});

describe('paths', () => {
  test('each app lands on its own home tab', () => {
    expect(clinicHome('dtouchdental', 'patient')).toBe('/dtouchdental/home');
    expect(clinicHome('dtouchdental', 'doctor')).toBe('/dtouchdental/schedule');
    expect(clinicHome('dtouchdental', 'assistant')).toBe('/dtouchdental/check-in');
    expect(clinicHome('dtouchdental', 'admin')).toBe('/dtouchdental/dashboard');
  });

  test('the clinic in a path, lower-cased; pages of their own are none', () => {
    expect(clinicSlugOf('/DTouchDental/book')).toBe('dtouchdental');
    expect(clinicSlugOf('/')).toBeNull();
    expect(clinicSlugOf('/not-found')).toBeNull();
    expect(clinicSlugOf('/privacy')).toBeNull();
  });

  test('?next= keeps to paths inside the app', () => {
    expect(safeNext('/dtouchdental/book')).toBe('/dtouchdental/book');
    expect(safeNext('//evil.example')).toBeNull();
    expect(safeNext('https://evil.example')).toBeNull();
    expect(safeNext(null)).toBeNull();
  });
});
