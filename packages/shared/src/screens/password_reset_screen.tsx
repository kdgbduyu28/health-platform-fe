import { useRef, useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, Text } from 'react-native-paper';

import { HumanCheck, useHumanCheck } from '../captcha/human_check';
import { usePlatform } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { TextField, useForm } from '../ui/fields';
import { Icon } from '../ui/icon';
import { Gap } from '../ui/kit';
import { Page } from '../ui/page';

/// Self-service password reset, opened from the sign-in screen.
///
/// Two steps: email a code, then enter it with a new password. A code rather
/// than a link, because a reset link only works in the browser tab that asked
/// for it (the PKCE verifier lives there) and needs every app's URL on the
/// redirect allow-list, while a code works from any device the email opens
/// on.
export function PasswordResetScreen({ initialEmail = '', close }: { initialEmail?: string; close: () => void }) {
  const { colors } = useAppTheme();
  const { repo, passwordReset } = usePlatform();
  const check = useHumanCheck();
  const form = useForm({ email: initialEmail, code: '', password: '', confirm: '' });
  const { values } = form;

  const [codeSent, setCodeSent] = useState(false);
  /// The code has been spent and the user is signed in; only the new
  /// password is left to save. A retry must not verify the code again.
  const verified = useRef(false);
  const [isVerified, setVerified] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const validEmail = (v: string) => (!v.includes('@') ? 'Enter a valid email' : null);

  const sendCode = async () => {
    if (busy) return;
    if (!form.validate({ email: validEmail })) return;
    setBusy(true);
    setError(null);
    setNotice(null);
    let captchaToken: string | null = null;
    try {
      captchaToken = await check.token();
      await repo.sendPasswordResetCode(values.email, captchaToken);
      setCodeSent(true);
      setNotice(
        `If ${values.email.trim()} has an account, a code is on its way. It can take a minute — check your spam folder too.`,
      );
    } catch (e) {
      setError(describeError(e));
    } finally {
      // Each token is good for one request, and "Send a new code" needs one.
      if (captchaToken != null) check.reset();
      setBusy(false);
    }
  };

  const reset = async () => {
    if (busy) return;
    const ok = form.validate({
      email: validEmail,
      code: (v) => (/^\d{6,10}$/.test(v.trim()) ? null : 'Enter the code from the email'),
      password: (v) => (v.length < 6 ? 'At least 6 characters' : null),
      confirm: (v, all) => (v !== all.password ? 'The passwords do not match' : null),
    });
    if (!ok) return;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      if (!verified.current) {
        passwordReset.set(true);
        await repo.verifyPasswordResetCode(values.email, values.code);
        verified.current = true;
        setVerified(true);
      }
      await repo.changePassword(values.password);
      // Signed in with the new password: lifting the gate opens the app.
      passwordReset.set(false);
      close();
    } catch (e) {
      if (!verified.current) passwordReset.set(false);
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  /// Leaves after the code was verified but the password was not saved. The
  /// session the code opened is closed, so nobody is left signed in on a
  /// password they never chose.
  const abandon = async () => {
    await repo.signOut();
    passwordReset.set(false);
    close();
  };

  return (
    <Page title="Reset password" maxWidth={420} padding={24} onBack={isVerified ? () => !busy && abandon() : close}>
      <View style={{ alignItems: 'center' }}>
        <Icon name="lock-reset" size={56} color={colors.primary} />
      </View>
      <Gap size={16} />
      <Text style={{ textAlign: 'center', color: colors.onSurfaceVariant, lineHeight: 20 }}>
        {codeSent
          ? 'Enter the code from your email and choose a new password.'
          : 'Enter the email you sign in with. We will send you a code to reset your password.'}
      </Text>
      <Gap size={24} />
      <TextField
        label="Email"
        icon="mail-outline"
        value={values.email}
        onChangeText={form.set('email')}
        error={form.errors.email}
        disabled={codeSent}
        keyboardType="email-address"
        autoCapitalize="none"
        autoComplete="email"
        onSubmit={codeSent ? undefined : sendCode}
      />
      {codeSent && (
        <>
          <Gap size={12} />
          <TextField
            label="Code from the email"
            icon="pin"
            value={values.code}
            onChangeText={form.set('code')}
            error={form.errors.code}
            disabled={isVerified}
            keyboardType="number-pad"
            autoComplete="one-time-code"
          />
          <Gap size={12} />
          <TextField
            label="New password"
            icon="lock-outline"
            secure
            autoComplete="new-password"
            value={values.password}
            onChangeText={form.set('password')}
            error={form.errors.password}
          />
          <Gap size={12} />
          <TextField
            label="Confirm new password"
            icon="lock-outline"
            secure
            value={values.confirm}
            onChangeText={form.set('confirm')}
            error={form.errors.confirm}
            onSubmit={reset}
          />
        </>
      )}
      {error != null && <Text style={{ marginTop: 16, textAlign: 'center', color: colors.error }}>{error}</Text>}
      {notice != null && <Text style={{ marginTop: 16, textAlign: 'center', color: colors.primary }}>{notice}</Text>}
      {/* Guards sending a code, which is also what "Send a new code" does, so
          it stays until the code is used. Out of sight on the second step
          unless Cloudflare wants a click. */}
      {!isVerified && <HumanCheck controller={check} action="reset" alwaysVisible={!codeSent} />}
      <Gap size={24} />
      <Button mode="contained" onPress={codeSent ? reset : sendCode} disabled={busy} contentStyle={{ height: 52 }}>
        {busy ? <ActivityIndicator size={20} /> : codeSent ? 'Set new password' : 'Send code'}
      </Button>
      {codeSent && !isVerified && (
        <>
          <Gap size={8} />
          <Button onPress={sendCode} disabled={busy}>
            Send a new code
          </Button>
          <Button
            onPress={() => {
              setCodeSent(false);
              setNotice(null);
              setError(null);
            }}
            disabled={busy}
          >
            Use a different email
          </Button>
        </>
      )}
      {isVerified && (
        <>
          <Gap size={8} />
          <Button onPress={abandon} disabled={busy}>
            Cancel
          </Button>
        </>
      )}
    </Page>
  );
}
