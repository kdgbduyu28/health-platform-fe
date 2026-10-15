import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { ScrollView, View } from 'react-native';
import { ActivityIndicator, Button, Text, TextInput } from 'react-native-paper';

import { useClinicNav } from '../app/navigation';
import { clinicHome } from '../app/paths';
import { useRouteBrandClinic } from '../queries/clinic';
import { useCurrentUserId, usePlatform } from '../state/platform';
import { ClinicMark } from '../theme/brand';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { Gap } from '../ui/kit';
import { Page } from '../ui/page';

/// Where a patient attaches their account to a clinic, using the code the
/// clinic gave them.
///
/// Shown in two ways. As the whole app, when a signed-in patient belongs to
/// no clinic yet — there is nothing else they could see. And opened from the
/// profile screen (with [close]), to add another clinic; then it closes
/// itself on success.
export function JoinClinicScreen({ close }: { close?: () => void }) {
  const { colors } = useAppTheme();
  const { repo } = usePlatform();
  const qc = useQueryClient();
  const uid = useCurrentUserId();
  const nav = useClinicNav();
  const isGate = close == null;
  // Reached from a clinic's page, the screen is about that clinic.
  const brand = useRouteBrandClinic();
  const clinic = isGate ? brand : null;
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    if (busy) return;
    const value = code.trim();
    if (value === '') {
      setError('Enter the code from your clinic.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const clinicId = await repo.joinClinic(value);
      // The new chart is what makes the clinic visible at all, so both lists
      // have to be refetched.
      await qc.invalidateQueries({ queryKey: ['myPatients'] });
      const clinics = await qc.fetchQuery({ queryKey: ['visibleClinics', uid], queryFn: () => repo.fetchClinics() });
      // Then open the clinic just joined — which is not necessarily the one
      // in the URL: a code is the clinic's, whichever page it was typed on.
      close?.();
      const joined = clinics.find((c) => c.id === clinicId);
      if (joined) nav.goTo(clinicHome(joined.slug, 'patient'));
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  const body = (
    <View style={{ width: '100%', maxWidth: 420, alignSelf: 'center' }}>
      <View style={{ alignItems: 'center' }}>
        <ClinicMark clinic={clinic} size={72} />
      </View>
      <Gap size={24} />
      <Text variant="headlineSmall" style={{ textAlign: 'center', fontWeight: '700' }}>
        {clinic != null ? `Join ${clinic.name}` : isGate ? 'Join your clinic' : 'Add another clinic'}
      </Text>
      <Gap size={8} />
      <Text style={{ textAlign: 'center', color: colors.onSurfaceVariant, lineHeight: 20 }}>
        Enter the code your clinic gave you. Once you have joined, you can book and see your appointments there.
      </Text>
      <Gap size={28} />
      <CodeInput value={code} onChange={setCode} onSubmit={submit} placeholder="CLINIC CODE" autoFocus />
      {error != null && <Text style={{ marginTop: 12, textAlign: 'center', color: colors.error }}>{error}</Text>}
      <Gap size={20} />
      <Button mode="contained" onPress={submit} disabled={busy} contentStyle={{ height: 52 }}>
        {busy ? <ActivityIndicator size={20} /> : 'Join clinic'}
      </Button>
      {isGate && (
        <>
          <Gap size={8} />
          <Button disabled={busy} onPress={() => void repo.signOut()}>
            Sign out
          </Button>
        </>
      )}
    </View>
  );

  if (!isGate) {
    return (
      <Page title="Join a clinic" padding={24}>
        {body}
      </Page>
    );
  }
  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: colors.surface }}
      contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', padding: 24 }}
      keyboardShouldPersistTaps="handled"
    >
      {body}
    </ScrollView>
  );
}

/// A code typed in capitals, spaced out and centred, as clinics print them.
export function CodeInput({
  value,
  onChange,
  onSubmit,
  placeholder,
  autoFocus,
}: {
  value: string;
  onChange: (v: string) => void;
  onSubmit: () => void;
  placeholder: string;
  autoFocus?: boolean;
}) {
  const { colors } = useAppTheme();
  return (
    <TextInput
      mode="outlined"
      value={value}
      onChangeText={(t) => onChange(t.toUpperCase())}
      onSubmitEditing={onSubmit}
      placeholder={placeholder}
      autoFocus={autoFocus}
      autoCapitalize="characters"
      autoCorrect={false}
      autoComplete="off"
      returnKeyType="go"
      outlineColor="transparent"
      outlineStyle={{ borderRadius: 12 }}
      style={{ backgroundColor: colors.surfaceContainerHighest, textAlign: 'center' }}
      contentStyle={{ textAlign: 'center', letterSpacing: 4, fontWeight: '600', fontSize: 20 }}
    />
  );
}
