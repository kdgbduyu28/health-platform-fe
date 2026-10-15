import { useQuery, useQueryClient } from '@tanstack/react-query';
import { usePathname } from 'expo-router';
import { type ReactNode, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { ActivityIndicator, Button, Text } from 'react-native-paper';

import type { User } from '@supabase/supabase-js';

import { privacyPolicyVersion, termsVersion } from '../legal/documents';
import { useRouteBrandClinic } from '../queries/clinic';
import { useCurrentUser, usePlatform, usePasswordResetInProgress } from '../state/platform';
import { recordPendingPolicyAck } from '../state/pending_policy_ack';
import { ClinicMark } from '../theme/brand';
import { useAppTheme } from '../theme/clinic_theme';
import { ErrorView, describeError } from '../ui/async_view';
import { Gap } from '../ui/kit';
import { PoliciesBox } from './sign_in_screen';

/// Signs in through Google rather than the create-account form.
function usesGoogle(user: User): boolean {
  const providers = (user.app_metadata?.providers as string[] | undefined) ?? [user.app_metadata?.provider];
  return providers.includes('google');
}

/// Holds a Google account at the Terms and Privacy Policy until it has
/// agreed to the current versions.
///
/// An email account cannot be made without ticking the box. A Google one
/// can: "Continue with Google" on the sign-in form creates the account the
/// first time. So the box is asked here instead, once — or never, when the
/// person ticked it on the create-account form before going to Google.
export function PolicyGate({ children }: { children: ReactNode }) {
  const user = useCurrentUser();
  const resetting = usePasswordResetInProgress();
  // The box links to both documents; they have to open.
  const reading = /\/(privacy|terms)$/.test(usePathname());
  if (user == null || resetting || reading || !usesGoogle(user)) return <>{children}</>;
  return <GoogleAccountPolicyGate userId={user.id}>{children}</GoogleAccountPolicyGate>;
}

function GoogleAccountPolicyGate({ userId, children }: { userId: string; children: ReactNode }) {
  const { repo } = usePlatform();
  const acks = useQuery({
    queryKey: ['policyAcknowledgements', userId],
    queryFn: async () => {
      await recordPendingPolicyAck((document, version) => repo.acknowledgePolicy(document, version));
      return repo.fetchMyPolicyAcknowledgements();
    },
    staleTime: Infinity,
  });

  if (acks.data != null) {
    const agreed = acks.data.has(`privacy@${privacyPolicyVersion}`) && acks.data.has(`terms@${termsVersion}`);
    return agreed ? <>{children}</> : <AgreeScreen userId={userId} />;
  }
  if (acks.error != null) return <ErrorView error={acks.error} onRetry={() => void acks.refetch()} />;
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <ActivityIndicator />
    </View>
  );
}

function AgreeScreen({ userId }: { userId: string }) {
  const { colors } = useAppTheme();
  const { repo } = usePlatform();
  const qc = useQueryClient();
  const clinic = useRouteBrandClinic();
  const email = useCurrentUser()?.email ?? 'your Google account';
  const [agreed, setAgreed] = useState(false);
  const [agreedError, setAgreedError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    if (busy) return;
    if (!agreed) {
      setAgreedError('Tick the box to agree to the Terms and Conditions');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await repo.acknowledgePolicy('privacy', privacyPolicyVersion);
      await repo.acknowledgePolicy('terms', termsVersion);
      await qc.invalidateQueries({ queryKey: ['policyAcknowledgements', userId] });
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: colors.surface }}
      contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', padding: 24 }}
    >
      <View style={{ width: '100%', maxWidth: 420, alignSelf: 'center' }}>
        <View style={{ alignItems: 'center' }}>
          <ClinicMark clinic={clinic} size={72} />
        </View>
        <Text variant="headlineSmall" style={{ marginTop: 24, textAlign: 'center', fontWeight: '700' }}>
          One more step
        </Text>
        <Text style={{ marginTop: 12, textAlign: 'center', color: colors.onSurfaceVariant, lineHeight: 20 }}>
          {`You are signed in with Google as ${email}. Before you go on, please read and agree to how this platform handles your account.`}
        </Text>
        <Gap size={24} />
        <PoliciesBox
          value={agreed}
          disabled={busy}
          error={agreedError}
          onChange={(v) => {
            setAgreed(v);
            if (v) setAgreedError(null);
          }}
        />
        {error != null && <Text style={{ marginTop: 12, color: colors.error, fontSize: 13 }}>{error}</Text>}
        <Gap size={24} />
        <Button mode="contained" onPress={submit} disabled={busy} contentStyle={{ height: 52 }}>
          {busy ? <ActivityIndicator size={20} /> : 'Continue'}
        </Button>
        <Gap size={8} />
        <Button disabled={busy} onPress={() => void repo.signOut()}>
          Sign out
        </Button>
      </View>
    </ScrollView>
  );
}
