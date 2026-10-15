import { AuthError } from '@supabase/supabase-js';
import { useQuery } from '@tanstack/react-query';
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Platform, ScrollView, View } from 'react-native';
import { ActivityIndicator, Button, Checkbox, FAB, HelperText, Text } from 'react-native-paper';

import { HumanCheck, useHumanCheck } from '../captcha/human_check';
import { type DemoLogin, demoLoginsEnabled, demoLoginsFor, demoPassword } from '../config/demo_logins';
import { privacyPolicy, privacyPolicyVersion, termsAndConditions, termsVersion } from '../legal/documents';
import type { LegalDocument } from '../legal/legal_content';
import { isStaffRole, takesStaffCodes } from '../models/app_role';
import type { Clinic } from '../models/clinic';
import { useRouteBrandClinic } from '../queries/clinic';
import { forgetPolicyAckForGoogle, rememberPolicyAckForGoogle } from '../state/pending_policy_ack';
import { clearOAuthErrorFromAddress, usePlatform } from '../state/platform';
import { useStore } from '../state/store';
import { preferences } from '../state/preferences';
import { ClinicMark } from '../theme/brand';
import { useAppTheme, withAlpha } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { TextField, useForm } from '../ui/fields';
import { Icon, type IconName } from '../ui/icon';
import { Gap, ListTile } from '../ui/kit';
import { type Close, useOverlay } from '../ui/overlay';
import { PasswordResetScreen } from './password_reset_screen';

/// Wrong sign-ins on this screen past which the human check comes out into
/// view. Supabase checks a token on every attempt either way; this only
/// decides whether the person sees it happen.
const quietTries = 3;

/// Google sign-in goes by redirect, which only a browser can follow; the
/// apps ship to the web only for now.
const isWeb = Platform.OS === 'web';

/// Shared sign-in for all four apps.
///
/// Every app offers sign-up, because an account grants nothing by itself.
/// Access comes afterwards, per clinic: a patient joins with the clinic's
/// code, and a staff member is added by that clinic's admin — who can only
/// add an account that already exists.
///
/// Reached through a clinic's link (`/:clinic/sign-in`), it wears that
/// clinic's name and logo; at `/` nobody is known yet, so it is unbranded.
export function SignInScreen({ initialSignUp = false }: { initialSignUp?: boolean }) {
  const { colors } = useAppTheme();
  const { app, appName, repo, oauthError } = usePlatform();
  const googleError = useStore(oauthError);
  // The router read the address before createPlatform tidied it, and wrote
  // it back; tidy it again now it has, so a reload does not repeat it.
  useEffect(() => {
    if (googleError != null) clearOAuthErrorFromAddress();
  }, [googleError]);
  // Shown once Google is switched on in Supabase Auth, not before.
  const offersGoogle =
    useQuery({
      queryKey: ['googleSignIn'],
      queryFn: () => repo.googleSignInEnabled(),
      enabled: isWeb,
      staleTime: Infinity,
    }).data === true;
  const overlay = useOverlay();
  const clinic = useRouteBrandClinic();
  const check = useHumanCheck();
  // Most devices sign in the same person every time.
  const form = useForm({ fullName: '', email: preferences.lastEmail ?? '', password: '' });
  const { values } = form;

  const [isSignUp, setSignUp] = useState(initialSignUp);
  const [busy, setBusy] = useState(false);
  /// The Terms and Privacy Policy box on the create-account form. Never
  /// ticked for them: the law wants it read, not skipped past.
  const [agreed, setAgreed] = useState(false);
  const [agreedError, setAgreedError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [failedSignIns, setFailedSignIns] = useState(0);

  /// Off to Google. On the create-account form the box still has to be
  /// ticked first, and the tick goes along (see PolicyGate). From the
  /// sign-in form a first-time Google account is asked on its way in.
  const continueWithGoogle = async () => {
    if (busy) return;
    if (isSignUp && !agreed) {
      setAgreedError('Tick the box to agree to the Terms and Conditions');
      return;
    }
    setBusy(true);
    setError(null);
    setNotice(null);
    oauthError.set(null);
    if (isSignUp) rememberPolicyAckForGoogle();
    else forgetPolicyAckForGoogle();
    try {
      // Back to this very page, so a clinic's link stays that clinic's.
      const here = new URL(window.location.href);
      here.hash = '';
      await repo.signInWithGoogle(here.toString());
      // The browser is leaving; stay busy until it has.
    } catch (e) {
      forgetPolicyAckForGoogle();
      setError(describeError(e));
      setBusy(false);
    }
  };

  const showCheck = isSignUp || failedSignIns >= quietTries;
  const demos = demoLoginsEnabled ? demoLoginsFor(app) : [];

  /// Fills the form with a demo account. It does not sign in: the human
  /// check still has to pass, and the person sees what they are about to use.
  const pickDemo = async () => {
    const picked = await overlay.showSheet<DemoLogin>((close) => <DemoLoginsSheet logins={demos} close={close} />);
    if (picked == null) return;
    setSignUp(false);
    setError(null);
    setNotice(null);
    form.setErrors({});
    form.setValues((v) => ({ ...v, email: picked.email, password: demoPassword }));
  };

  const submit = async () => {
    // Two entry points reach this — the button and the password field's
    // submit — so it has to be re-entrant-safe. A second signInWithPassword
    // issues a fresh token that invalidates the first.
    if (busy) return;
    const ok = form.validate({
      ...(isSignUp ? { fullName: (v: string) => (v.trim() === '' ? 'Enter your name' : null) } : {}),
      email: (v) => (!v.includes('@') ? 'Enter a valid email' : null),
      password: (v) => (v.length < 6 ? 'At least 6 characters' : null),
    });
    const agreedOk = !isSignUp || agreed;
    setAgreedError(agreedOk ? null : 'Tick the box to agree to the Terms and Conditions');
    if (!ok || !agreedOk) return;

    setBusy(true);
    setError(null);
    setNotice(null);
    let captchaToken: string | null = null;
    try {
      captchaToken = await check.token();
      const email = values.email.trim();
      if (isSignUp) {
        await repo.signUp(email, values.password, values.fullName.trim(), {
          captchaToken,
          privacyPolicyVersion,
          termsVersion,
        });
        const nextStep = takesStaffCodes(app)
          ? ' Then sign in and enter the staff code your clinic gave you.'
          : isStaffRole(app)
            ? ` Then ask your clinic administrator to add ${email}.`
            : '';
        setNotice(`Account created. If email confirmation is on, check your inbox before signing in.${nextStep}`);
      } else {
        await repo.signIn(email, values.password, captchaToken);
        preferences.setLastEmail(email);
      }
    } catch (e) {
      const failed = !isSignUp && e instanceof AuthError ? failedSignIns + 1 : failedSignIns;
      setFailedSignIns(failed);
      let message = describeError(e);
      if (!isSignUp && failed >= quietTries) {
        message = `${message}\nToo many tries. Wait for the security check below to pass before you try again.`;
      }
      setError(message);
    } finally {
      // Each token is good for one request.
      if (captchaToken != null) check.reset();
      setBusy(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.surface }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', padding: 24 }}
        keyboardShouldPersistTaps="handled"
      >
        <View style={{ width: '100%', maxWidth: 420, alignSelf: 'center' }}>
          <Header appName={appName} clinic={clinic} />
          <Gap size={32} />
          {isSignUp && (
            <>
              <TextField
                label="Full name"
                icon="person-outline"
                autoCapitalize="words"
                autoComplete="name"
                value={values.fullName}
                onChangeText={form.set('fullName')}
                error={form.errors.fullName}
              />
              <Gap size={12} />
            </>
          )}
          <TextField
            label="Email"
            icon="mail-outline"
            keyboardType="email-address"
            autoCapitalize="none"
            autoComplete="email"
            value={values.email}
            onChangeText={form.set('email')}
            error={form.errors.email}
          />
          <Gap size={12} />
          <TextField
            label="Password"
            icon="lock-outline"
            secure
            autoComplete={isSignUp ? 'new-password' : 'current-password'}
            value={values.password}
            onChangeText={form.set('password')}
            error={form.errors.password}
            onSubmit={submit}
          />
          {!isSignUp && (
            <View style={{ alignItems: 'flex-end' }}>
              <Button
                disabled={busy}
                onPress={() =>
                  overlay.showPage((close) => <PasswordResetScreen initialEmail={values.email.trim()} close={close} />)
                }
              >
                Forgot password?
              </Button>
            </View>
          )}
          {isSignUp && (
            <>
              <Gap size={12} />
              <PoliciesBox
                value={agreed}
                disabled={busy}
                error={agreedError}
                onChange={(v) => {
                  setAgreed(v);
                  if (v) setAgreedError(null);
                }}
              />
            </>
          )}
          {googleError != null && error == null && (
            <>
              <Gap size={16} />
              <Banner text={`Google sign-in did not finish: ${googleError}`} color={colors.error} icon="error-outline" />
            </>
          )}
          {error != null && (
            <>
              <Gap size={16} />
              <Banner text={error} color={colors.error} icon="error-outline" />
            </>
          )}
          {notice != null && (
            <>
              <Gap size={16} />
              <Banner text={notice} color={colors.primary} icon="info-outline" />
            </>
          )}
          <HumanCheck controller={check} action={isSignUp ? 'sign-up' : 'sign-in'} alwaysVisible={showCheck} />
          <Gap size={24} />
          <Button mode="contained" onPress={submit} disabled={busy} contentStyle={{ height: 52 }}>
            {busy ? <ActivityIndicator size={20} /> : isSignUp ? 'Create account' : 'Sign in'}
          </Button>
          {offersGoogle && (
            <>
              <OrDivider />
              <Button
                mode="outlined"
                icon="google"
                onPress={continueWithGoogle}
                disabled={busy}
                contentStyle={{ height: 52 }}
              >
                {isSignUp ? 'Sign up with Google' : 'Continue with Google'}
              </Button>
            </>
          )}
          <Gap size={8} />
          <Button
            disabled={busy}
            onPress={() => {
              setSignUp((s) => !s);
              setError(null);
              setNotice(null);
            }}
          >
            {isSignUp ? 'I already have an account' : 'New here? Create an account'}
          </Button>
          {isStaffRole(app) && (
            <Text style={{ marginTop: 8, textAlign: 'center', fontSize: 12, color: colors.onSurfaceVariant }}>
              {takesStaffCodes(app)
                ? "New staff: create your account, sign in, then enter the staff code from your clinic's admin."
                : 'New staff: create your account, then ask your clinic administrator to add you.'}
            </Text>
          )}
        </View>
        {/* Room for the demo button, so it never covers the last line. */}
        {demos.length > 0 && <Gap size={72} />}
      </ScrollView>
      {demos.length > 0 && (
        <FAB
          icon="key"
          label="Demo logins"
          variant="secondary"
          disabled={busy}
          onPress={pickDemo}
          style={{ position: 'absolute', right: 16, bottom: 16 }}
        />
      )}
    </View>
  );
}

/// The demo accounts for this app, while the platform is a showcase. Picking
/// one answers it to the sign-in form.
function DemoLoginsSheet({ logins, close }: { logins: DemoLogin[]; close: Close<DemoLogin> }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ paddingBottom: 16 }}>
      <View style={{ paddingHorizontal: 16, paddingBottom: 8 }}>
        <Text variant="titleMedium" style={{ fontWeight: '700' }}>
          Demo logins
        </Text>
        <Text style={{ marginTop: 4, fontSize: 13, color: colors.onSurfaceVariant }}>
          Test accounts with sample data. Every one uses the password {demoPassword}. Tap one to fill it in, then sign
          in.
        </Text>
      </View>
      {logins.map((d) => (
        <ListTile
          key={d.email}
          leading={<Icon name="account-circle" color={colors.primary} />}
          title={d.label}
          subtitle={`${d.email}\n${d.detail}`}
          onPress={() => close(d)}
        />
      ))}
    </View>
  );
}

function Header({ appName, clinic }: { appName: string; clinic: Clinic | null }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ alignItems: 'center' }}>
      <ClinicMark clinic={clinic} size={72} />
      <Gap size={16} />
      <Text variant="headlineSmall" style={{ textAlign: 'center', fontWeight: '700' }}>
        {clinic == null ? 'Sign in to your clinic' : `Sign in to ${clinic.name}`}
      </Text>
      <Gap size={8} />
      <Text style={{ color: colors.onSurfaceVariant, letterSpacing: 0.5 }}>{appName}</Text>
    </View>
  );
}

/// "I agree to the Terms and Conditions and have read the Privacy Policy",
/// with both a tap away. The form will not create the account until it is
/// ticked.
///
/// It is not consent to health information: a clinic asks for that on its
/// own form, later.
export function PoliciesBox({
  value,
  onChange,
  disabled,
  error,
}: {
  value: boolean;
  onChange: (v: boolean) => void;
  disabled: boolean;
  error: string | null;
}) {
  const { colors } = useAppTheme();
  const router = useRouter();
  const link = (document: LegalDocument) => (
    <Text
      onPress={() => router.push(`/${document.id}` as never)}
      style={{ color: colors.primary, textDecorationLine: 'underline' }}
      accessibilityRole="link"
    >
      {document.title}
    </Text>
  );
  return (
    <View>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <Checkbox.Android
          status={value ? 'checked' : 'unchecked'}
          onPress={() => onChange(!value)}
          disabled={disabled}
        />
        <Text style={{ flex: 1 }}>
          I agree to the {link(termsAndConditions)} and have read the {link(privacyPolicy)}
        </Text>
      </View>
      {error != null && (
        <HelperText type="error" visible>
          {error}
        </HelperText>
      )}
    </View>
  );
}

function OrDivider() {
  const { colors } = useAppTheme();
  const line = <View style={{ flex: 1, height: 1, backgroundColor: colors.outlineVariant }} />;
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, marginVertical: 16 }}>
      {line}
      <Text style={{ color: colors.onSurfaceVariant, fontSize: 12 }}>or</Text>
      {line}
    </View>
  );
}

function Banner({ text, color, icon }: { text: string; color: string; icon: IconName }) {
  return (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: 8,
        padding: 12,
        borderRadius: 12,
        backgroundColor: withAlpha(color, 25 / 255),
        borderWidth: 1,
        borderColor: withAlpha(color, 70 / 255),
      }}
    >
      <Icon name={icon} size={18} color={color} />
      <Text style={{ flex: 1, color, fontSize: 13 }}>{text}</Text>
    </View>
  );
}
