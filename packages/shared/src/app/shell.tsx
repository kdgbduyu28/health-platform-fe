import MaterialCommunityIcons from '@expo/vector-icons/MaterialCommunityIcons';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { QueryClientProvider, useQueryClient } from '@tanstack/react-query';
import { useFonts } from 'expo-font';
import { Slot, usePathname, useRouter } from 'expo-router';
import { type ReactNode, useEffect, useRef, useState } from 'react';
import { Platform as RNPlatform, ScrollView, StyleSheet, View, useColorScheme } from 'react-native';
import { ActivityIndicator, Button, PaperProvider, Text } from 'react-native-paper';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';

import { type AppRole, roleDisplayName, takesStaffCodes } from '../models/app_role';
import { mapAsync } from '../queries/async_value';
import {
  useClinicPage,
  useCurrentClinic,
  useMyClinics,
  useMyMemberships,
  useMyPatients,
  useRefreshAccess,
  useRouteBrandClinic,
  useRouteClinicSlug,
} from '../queries/clinic';
import { JoinClinicScreen } from '../screens/join_clinic_screen';
import { PolicyGate } from '../screens/policy_gate';
import { SignInScreen } from '../screens/sign_in_screen';
import { StaffCodeScreen } from '../screens/staff_code_screen';
import {
  type Platform,
  PlatformProvider,
  createPlatform,
  useAppRole,
  useAuthState,
  useCurrentUser,
  useIsSignedIn,
  useKiosk,
  usePasswordResetInProgress,
  usePlatform,
} from '../state/platform';
import { preferences, textSizeMeta, usePreference } from '../state/preferences';
import { ClinicMark } from '../theme/brand';
import { buildClinicTheme, useAppTheme } from '../theme/clinic_theme';
import { AsyncView, ErrorView } from '../ui/async_view';
import { PaperIcon } from '../ui/icon';
import { OverlayHost } from '../ui/overlay';
import { decideRedirect } from './redirect';

/// The outer shell shared by all four apps: each app's root layout is this
/// and nothing else.
///
/// The router is always mounted: the URL names the clinic, and the redirect
/// (see decideRedirect) decides what this visitor may see there. The theme
/// follows the clinic in the URL — even signed out, from its public page —
/// so a clinic's link opens in the clinic's colours.
export function ClinicAppRoot({ app, appName, hasLanding = false }: { app: AppRole; appName: string; hasLanding?: boolean }) {
  const [platform] = useState<Platform>(() => createPlatform(app, appName));
  const [fontsLoaded] = useFonts({ ...MaterialIcons.font, ...MaterialCommunityIcons.font });
  return (
    <SafeAreaProvider>
      <QueryClientProvider client={platform.queryClient}>
        <PlatformProvider platform={platform}>
          <ThemedApp hasLanding={hasLanding} ready={fontsLoaded} />
        </PlatformProvider>
      </QueryClientProvider>
    </SafeAreaProvider>
  );
}

function ThemedApp({ hasLanding, ready }: { hasLanding: boolean; ready: boolean }) {
  const { appName } = usePlatform();
  const clinic = useRouteBrandClinic();
  const system = useColorScheme();
  const mode = usePreference((p) => p.themeMode);
  const textSize = usePreference((p) => p.textSize);
  const dark = mode === 'dark' || (mode === 'system' && system === 'dark');
  const theme = buildClinicTheme(clinic, dark, textSizeMeta[textSize].scale);
  // Android draws the app behind the status and gesture bars; the browser does not.
  const insets = useSafeAreaInsets();
  const edges =
    RNPlatform.OS === 'web' ? null : { paddingTop: insets.top, paddingBottom: insets.bottom, paddingLeft: insets.left, paddingRight: insets.right };

  useEffect(() => {
    if (typeof document === 'undefined') return;
    document.title = clinic?.name ?? appName;
    document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
    document.body.style.backgroundColor = theme.colors.surface;
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme.colors.surface);
  }, [clinic?.name, appName, dark, theme]);

  return (
    <PaperProvider theme={theme} settings={{ icon: PaperIcon }}>
      <OverlayHost>
        <View style={[{ flex: 1, backgroundColor: theme.colors.surface }, edges]}>
          {RNPlatform.OS !== 'web' && <StatusBar style={dark ? 'light' : 'dark'} />}
          <RedirectGate hasLanding={hasLanding} ready={ready}>
            <PolicyGate>
              <Slot />
            </PolicyGate>
          </RedirectGate>
        </View>
      </OverlayHost>
    </PaperProvider>
  );
}

/// Runs the redirect on every change of page, sign-in state, clinics or
/// tablet hand-off, and keeps the page covered until it has decided — so no
/// screen ever renders where its visitor may not be.
function RedirectGate({ children, hasLanding, ready }: { children: ReactNode; hasLanding: boolean; ready: boolean }) {
  const { app, push } = usePlatform();
  const router = useRouter();
  const pathname = usePathname();
  const auth = useAuthState();
  const resetting = usePasswordResetInProgress();
  const kiosk = useKiosk();
  const signedIn = auth.session != null && !resetting;
  const slug = useRouteClinicSlug();

  const clinics = useMyClinics();
  const isMember = clinics.value?.some((c) => c.slug === slug) ?? false;
  const needsPage = slug != null && (!signedIn || (clinics.hasValue && !isMember));
  const clinicPage = useClinicPage(slug, needsPage);
  const memberships = useMyMemberships();
  const myPatients = useMyPatients();
  // React Native has a `window` but no `window.location`.
  const search = typeof window === 'undefined' ? '' : (window.location?.search ?? '');

  const decision = auth.ready
    ? decideRedirect({
        app,
        hasLanding,
        path: pathname,
        search,
        signedIn,
        kiosk,
        lastClinicSlug: preferences.lastClinicSlug(app),
        clinics,
        clinicPage,
        memberships,
        myPatients,
      })
    : ({ kind: 'wait' } as const);

  const target = decision.kind === 'go' ? decision.to : null;
  const lastTarget = useRef<string | null>(null);
  useEffect(() => {
    if (decision.kind === 'stay' && decision.memberSlug) preferences.setLastClinicSlug(app, decision.memberSlug);
  }, [decision.kind, decision.kind === 'stay' ? decision.memberSlug : null, app]);
  useEffect(() => {
    if (target == null) {
      lastTarget.current = null;
      return;
    }
    // One navigation per decision, however often this renders meanwhile.
    if (lastTarget.current === target) return;
    lastTarget.current = target;
    if (router.canDismiss()) router.dismissAll();
    router.replace(target as never);
  }, [target, router]);

  // A push notification tapped while this app is already open in a tab.
  // Only links inside the app: the payload is ours, but the check is cheap.
  useEffect(
    () =>
      push.onNotificationOpened((link) => {
        if (link.startsWith('/') && !link.startsWith('//')) router.replace(link as never);
      }),
    [push, router],
  );

  const covered = !ready || decision.kind !== 'stay';
  return (
    <View style={{ flex: 1 }}>
      {children}
      {covered && <LoadingCover />}
    </View>
  );
}

function LoadingCover() {
  const { colors } = useAppTheme();
  return (
    <View style={[StyleSheet.absoluteFill, { backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center' }]}>
      <ActivityIndicator />
    </View>
  );
}

/// Wraps every page under `/:clinic`. The router lets a page through when it
/// could not load what it needed to decide (offline, say); this says so,
/// with a way to try again.
export function ClinicScope({ children }: { children?: ReactNode }) {
  const slug = useRouteClinicSlug();
  const clinics = useMyClinics();
  const current = useCurrentClinic();
  const refresh = useRefreshAccess();
  const page = useClinicPage(slug, current.hasValue && current.value == null);
  const signedIn = useIsSignedIn();
  const qc = useQueryClient();

  if (signedIn && clinics.hasError && !clinics.hasValue) {
    return <ErrorView error={clinics.error} onRetry={() => void refresh()} />;
  }
  if (current.value == null && page.hasError && !page.hasValue) {
    return <ErrorView error={page.error} onRetry={() => void qc.invalidateQueries({ queryKey: ['clinicPage', slug] })} />;
  }
  return <>{children ?? <Slot />}</>;
}

/// `/`: sign in, or — for an account attached to no clinic in this app — the
/// way to get attached. An account with a clinic never sees this; the router
/// sends it to that clinic.
export function ClinicRootScreen() {
  const signedIn = useIsSignedIn();
  const resetting = usePasswordResetInProgress();
  const clinics = useMyClinics();
  const refresh = useRefreshAccess();
  if (!signedIn || resetting) return <SignInScreen />;
  if (clinics.value?.length === 0) return <NoClinicYet />;
  return (
    <AsyncView value={mapAsync(clinics, () => null)} onRetry={() => void refresh()}>
      {/* Clinics exist: the router is already on its way to the first. */}
      {() => (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <ActivityIndicator />
        </View>
      )}
    </AsyncView>
  );
}

/// Signed in, but attached to no clinic this app can be used at.
///
/// For a patient that is the normal state right after signing up, and the
/// next step is theirs: enter a clinic's code. A doctor or assistant enters
/// the single-use staff code their admin gave them and waits for approval.
/// An admin cannot fix it themselves — a full admin adds them — so the
/// screen says exactly what to ask for.
function NoClinicYet() {
  const app = useAppRole();
  if (app === 'patient') return <JoinClinicScreen />;
  if (takesStaffCodes(app)) return <StaffCodeScreen />;
  return <NoClinicAccessScreen />;
}

/// An admin-app account that is not an administrator here — or, at `/`,
/// anywhere.
export function NoClinicAccessScreen() {
  const app = useAppRole();
  const { repo } = usePlatform();
  const clinic = useRouteBrandClinic();
  const refresh = useRefreshAccess();
  const email = useCurrentUser()?.email ?? 'this account';
  const role = roleDisplayName(app).toLowerCase();
  const where = clinic == null ? 'at any clinic' : `at ${clinic.name}`;
  const article = app === 'assistant' || app === 'admin' ? 'an' : 'a';
  return (
    <MessageScreen
      mark={<ClinicMark clinic={clinic} size={72} />}
      title="No clinic access yet"
      body={`You are signed in as ${email}, but this account is not set up as ${article} ${role} ${where}.\n\nAsk the clinic's administrator to add ${email}, then tap Try again.`}
    >
      <Button mode="contained" icon="refresh" onPress={() => void refresh()} contentStyle={{ height: 52 }}>
        Try again
      </Button>
      <View style={{ height: 8 }} />
      <Button onPress={() => void repo.signOut()}>Sign out</Button>
    </MessageScreen>
  );
}

/// `/not-found`: no active clinic has the slug that was asked for. A
/// suspended clinic lands here too, on purpose — it looks like a typo.
export function ClinicNotFoundScreen() {
  const router = useRouter();
  return (
    <MessageScreen
      mark={<ClinicMark size={72} />}
      title="Clinic not found"
      body="There is no clinic at this address. Check the link your clinic sent you, or ask them for it again."
    >
      <Button mode="contained" onPress={() => router.replace('/')} contentStyle={{ height: 52 }}>
        Go to start
      </Button>
    </MessageScreen>
  );
}

export function MessageScreen({ mark, title, body, children }: { mark: ReactNode; title: string; body: string; children: ReactNode }) {
  const { colors } = useAppTheme();
  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: colors.surface }}
      contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', padding: 24 }}
    >
      <View style={{ width: '100%', maxWidth: 420, alignSelf: 'center', alignItems: 'stretch' }}>
        <View style={{ alignItems: 'center' }}>{mark}</View>
        <Text variant="headlineSmall" style={{ marginTop: 24, textAlign: 'center', fontWeight: '700' }}>
          {title}
        </Text>
        <Text style={{ marginTop: 12, textAlign: 'center', color: colors.onSurfaceVariant, lineHeight: 20 }}>{body}</Text>
        <View style={{ height: 28 }} />
        {children}
      </View>
    </ScrollView>
  );
}
