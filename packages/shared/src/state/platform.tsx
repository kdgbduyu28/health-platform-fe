import { type Session, type SupabaseClient, type User, createClient } from '@supabase/supabase-js';
import { QueryClient } from '@tanstack/react-query';
import { type ReactNode, createContext, useContext } from 'react';

import { SupabaseConfig } from '../config/supabase_config';
import { HealthRepository } from '../data/health_repository';
import { type AppRole, registersPatients } from '../models/app_role';
import { type BrowserPush, createBrowserPush } from '../platform/browser_push';
import { type KioskSession, parseKioskSession } from './kiosk';
import { preferences } from './preferences';
import { type Store, createStore, useStore } from './store';

/// The signed-in session as the apps see it. [ready] turns true once
/// Supabase has read any saved session back, so the first screen never
/// flashes the sign-in form at someone already signed in.
export type AuthState = { ready: boolean; session: Session | null };

/// Everything one app shares across its screens: which app it is, the
/// database, and the client-side state that is not server data. Each app
/// makes one at start-up with [createPlatform].
export type Platform = {
  /// Which of the four apps is running. The only thing a build decides:
  /// WHICH clinic it shows comes from the signed-in user at runtime, so four
  /// builds serve every clinic on the platform.
  app: AppRole;
  appName: string;
  supabase: SupabaseClient;
  repo: HealthRepository;
  push: BrowserPush;
  queryClient: QueryClient;
  auth: Store<AuthState>;
  /// True while a password reset has verified its emailed code but not yet
  /// saved the new password.
  ///
  /// Verifying the code signs the user in, and the router would normally
  /// swap the sign-in screen for the app at that moment — before they have
  /// chosen a new password. While this is set, the sign-in screens stay up.
  passwordReset: Store<boolean>;
  /// Why the last trip to Google came back without signing in (they
  /// cancelled, say), for the sign-in screen to show. Null otherwise.
  oauthError: Store<string | null>;
  kiosk: Store<KioskSession | null>;
};

export function createPlatform(app: AppRole, appName: string): Platform {
  const oauthError = createStore<string | null>(initialOAuthError);
  // PKCE: Google's sign-in comes back as `?code=`, which the client trades
  // for a session as it starts, then strips from the address. It only does
  // so while it holds the matching verifier, i.e. after signInWithGoogle in
  // this browser — no other link is mistaken for a sign-in.
  const supabase = createClient(SupabaseConfig.url, SupabaseConfig.publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' },
  });
  const push = createBrowserPush();

  // eslint-disable-next-line prefer-const
  let repo: HealthRepository;
  repo = new HealthRepository(supabase, async () => {
    // Forget this browser's subscription while the session can still prove
    // whose it is, then drop it from the browser too.
    const keys = await push.current();
    if (keys == null) return;
    await repo.deletePushSubscription(keys.endpoint);
    await push.unsubscribe();
  });

  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        // One retry, quickly: an RLS refusal or a missing row will not
        // succeed on the fifth try, and the screen should say so.
        retry: 1,
        staleTime: 30_000,
        refetchOnWindowFocus: false,
      },
    },
  });

  const auth = createStore<AuthState>({ ready: false, session: null });
  const kiosk = createStore<KioskSession | null>(null);

  const writeKiosk = (session: KioskSession | null) => {
    kiosk.set(session);
    preferences.setKioskSession(
      app,
      session == null
        ? null
        : JSON.stringify({ slug: session.slug, patient_id: session.patientId, submitted: session.submitted }),
    );
  };

  supabase.auth.onAuthStateChange((event, session) => {
    const before = auth.get();
    const wasUser = before.session?.user.id ?? null;
    const nowUser = session?.user.id ?? null;

    if (!before.ready) {
      // Opened signed out (the session expired): nothing to hand back.
      if (registersPatients(app)) {
        if (nowUser == null) writeKiosk(null);
        else kiosk.set(parseKioskSession(preferences.kioskSession(app)));
      }
    } else if (wasUser != null && nowUser == null) {
      // Signing out ends the hand-off: whoever signs in next starts clean.
      writeKiosk(null);
    }

    auth.set({ ready: true, session });

    // Another account's data must not linger on screen; the queries are
    // keyed by user, but the old user's rows would still be in memory.
    if (event === 'SIGNED_OUT' || (wasUser != null && nowUser != null && wasUser !== nowUser)) {
      queryClient.removeQueries({ predicate: (q) => !isPublicQuery(q.queryKey) });
    }
  });

  return {
    app,
    appName,
    supabase,
    repo,
    push,
    queryClient,
    auth,
    passwordReset: createStore(false),
    oauthError,
    kiosk: {
      get: kiosk.get,
      subscribe: kiosk.subscribe,
      set: (next) => writeKiosk(typeof next === 'function' ? next(kiosk.get()) : next),
    },
  };
}

/// Taken as this module loads — before the router reads the address and
/// before any Supabase client starts, which would see it too, refuse the
/// URL, and leave it in the address bar.
const oauthErrorKeys = ['error', 'error_code', 'error_description'];
const initialOAuthError = takeOAuthError();

/// An OAuth error Supabase sent back in the address (`?error_description=`
/// or `#error_description=`), removed from it so a reload does not show it
/// again.
function takeOAuthError(): string | null {
  if (typeof window === 'undefined' || !window.location || !window.history) return null;
  const url = new URL(window.location.href);
  const hash = new URLSearchParams(url.hash.replace(/^#/, ''));
  const from = oauthErrorKeys.some((k) => url.searchParams.has(k))
    ? url.searchParams
    : oauthErrorKeys.some((k) => hash.has(k))
      ? hash
      : null;
  if (from == null) return null;
  const message = from.get('error_description') || from.get('error') || 'Sign-in with Google did not finish.';
  clearOAuthErrorFromAddress();
  return message;
}

/// Takes an OAuth error out of the address bar, leaving the rest.
export function clearOAuthErrorFromAddress(): void {
  if (typeof window === 'undefined' || !window.location || !window.history) return;
  const url = new URL(window.location.href);
  const hash = new URLSearchParams(url.hash.replace(/^#/, ''));
  if (!oauthErrorKeys.some((k) => url.searchParams.has(k) || hash.has(k))) return;
  for (const k of oauthErrorKeys) {
    url.searchParams.delete(k);
    hash.delete(k);
  }
  const rest = hash.toString();
  url.hash = rest === '' ? '' : `#${rest}`;
  window.history.replaceState(window.history.state, '', url.toString());
}

/// Queries anyone may make signed out: kept across a change of account.
function isPublicQuery(key: readonly unknown[]): boolean {
  return key[0] === 'clinicPage' || key[0] === 'googleSignIn';
}

const PlatformContext = createContext<Platform | null>(null);

export function PlatformProvider({ platform, children }: { platform: Platform; children: ReactNode }) {
  return <PlatformContext.Provider value={platform}>{children}</PlatformContext.Provider>;
}

export function usePlatform(): Platform {
  const p = useContext(PlatformContext);
  if (p == null) throw new Error('usePlatform needs a PlatformProvider above it.');
  return p;
}

export function useAppRole(): AppRole {
  return usePlatform().app;
}

export function useRepository(): HealthRepository {
  return usePlatform().repo;
}

export function useAuthState(): AuthState {
  return useStore(usePlatform().auth);
}

/// The signed-in user, or null.
export function useCurrentUser(): User | null {
  return useAuthState().session?.user ?? null;
}

/// Identity of the signed-in user as a plain value. Queries key on this
/// rather than the whole User so they refetch on sign-in and sign-out but not
/// on every token refresh.
export function useCurrentUserId(): string | null {
  return useAuthState().session?.user.id ?? null;
}

export function useIsSignedIn(): boolean {
  return useCurrentUserId() != null;
}

export function usePasswordResetInProgress(): boolean {
  return useStore(usePlatform().passwordReset);
}

export function useKiosk(): KioskSession | null {
  return useStore(usePlatform().kiosk);
}

/// Starting, finishing and ending the tablet hand-off.
export function useKioskActions() {
  const { kiosk } = usePlatform();
  return {
    start: (slug: string, patientId: string | null = null) => kiosk.set({ slug, patientId, submitted: false }),
    /// The patient sent the form; [patientId] is their chart (new or not).
    submitted: (patientId: string) =>
      kiosk.set((s) => (s == null ? null : { slug: s.slug, patientId, submitted: true })),
    /// Staff took the tablet back.
    end: () => kiosk.set(null),
  };
}
