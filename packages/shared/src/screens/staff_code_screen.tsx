import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { ScrollView, View } from 'react-native';
import { ActivityIndicator, Button, Text } from 'react-native-paper';

import { useClinicNav } from '../app/navigation';
import { isGrantedBy, roleDisplayName } from '../models/app_role';
import type { StaffInviteStatus, StaffRequest } from '../models/staff_invite';
import { useMyStaffRequests, useRouteBrandClinic, useRouteClinicSlug } from '../queries/clinic';
import { useCurrentUser, useCurrentUserId, usePlatform } from '../state/platform';
import { ClinicMark } from '../theme/brand';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, Gap, ListTile } from '../ui/kit';
import { Page } from '../ui/page';
import { CodeInput } from './join_clinic_screen';

/// Where a doctor or assistant asks to join a clinic with the single-use
/// code its admin gave them, and waits for the admin to approve.
///
/// Shown as the whole app when the account has no clinic in this app yet,
/// and opened from the account menu (with [close]) to join another one.
export function StaffCodeScreen({ close }: { close?: () => void }) {
  const { colors } = useAppTheme();
  const { app, repo } = usePlatform();
  const qc = useQueryClient();
  const uid = useCurrentUserId();
  const nav = useClinicNav();
  const here = useRouteClinicSlug();
  const isGate = close == null;
  const brand = useRouteBrandClinic();
  const email = useCurrentUser()?.email ?? 'this account';
  const requests = useMyStaffRequests().value ?? [];
  const anyWaiting = requests.some((r) => r.status === 'pending' || r.status === 'approved');

  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const submit = async () => {
    if (busy) return;
    const value = code.trim();
    if (value === '') {
      setError('Enter the staff code from your clinic.');
      return;
    }
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      await repo.redeemStaffInvite(value, app);
      void qc.invalidateQueries({ queryKey: ['myStaffRequests'] });
      setCode('');
      setNotice('Request sent. You will get access as soon as an admin at the clinic approves it.');
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  /// Approval creates a membership (and a doctor's roster row), so every one
  /// of those has to be refetched for the clinic to appear.
  ///
  /// Approval at the clinic in the URL moves the router on by itself. A code
  /// can belong to a different clinic, though, so if that is where access
  /// arrived, go to `/` and let the router pick it.
  const refresh = async () => {
    await Promise.all(
      ['myStaffRequests', 'memberships', 'myDoctors', 'visibleClinics'].map((k) => qc.invalidateQueries({ queryKey: [k] })),
    );
    const [memberships, clinics] = await Promise.all([
      qc.fetchQuery({ queryKey: ['memberships', uid], queryFn: () => repo.fetchMyMemberships() }),
      qc.fetchQuery({ queryKey: ['visibleClinics', uid], queryFn: () => repo.fetchClinics() }),
    ]);
    const mine = clinics.filter((c) => memberships.some((m) => m.clinicId === c.id && isGrantedBy(app, m.role)));
    if (mine.length === 0 || !isGate) return;
    if (!mine.some((c) => c.slug === here)) nav.goTo('/');
  };

  const body = (
    <View style={{ width: '100%', maxWidth: 420, alignSelf: 'center' }}>
      <View style={{ alignItems: 'center' }}>
        <ClinicMark clinic={isGate ? brand : null} size={72} />
      </View>
      <Gap size={24} />
      <Text variant="headlineSmall" style={{ textAlign: 'center', fontWeight: '700' }}>
        {isGate ? 'Join your clinic' : 'Join another clinic'}
      </Text>
      <Gap size={8} />
      <Text style={{ textAlign: 'center', color: colors.onSurfaceVariant, lineHeight: 20 }}>
        Enter the staff code your clinic's admin gave you. Each code works once, and an admin approves the request
        before you can see anything.
      </Text>
      <Gap size={28} />
      <CodeInput value={code} onChange={setCode} onSubmit={submit} placeholder="STAFF CODE" autoFocus={requests.length === 0} />
      {error != null && <Text style={{ marginTop: 12, textAlign: 'center', color: colors.error }}>{error}</Text>}
      {notice != null && <Text style={{ marginTop: 12, textAlign: 'center', color: colors.primary }}>{notice}</Text>}
      <Gap size={20} />
      <Button mode="contained" onPress={submit} disabled={busy} contentStyle={{ height: 52 }}>
        {busy ? <ActivityIndicator size={20} /> : 'Send request'}
      </Button>
      {requests.length > 0 && (
        <>
          <Gap size={32} />
          <Text variant="titleMedium" style={{ fontWeight: '700' }}>
            Your requests
          </Text>
          <Gap size={8} />
          <View style={{ gap: 8 }}>
            {requests.map((r) => (
              <RequestTile key={r.id} request={r} />
            ))}
          </View>
        </>
      )}
      {anyWaiting && (
        <>
          <Gap size={12} />
          <Button mode="outlined" icon="refresh" onPress={refresh}>
            Check again
          </Button>
        </>
      )}
      {isGate && (
        <>
          <Gap size={24} />
          <Text style={{ textAlign: 'center', fontSize: 12, color: colors.onSurfaceVariant }}>Signed in as {email}</Text>
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

function RequestTile({ request }: { request: StaffRequest }) {
  const { colors } = useAppTheme();
  const look: Record<StaffInviteStatus, [IconName, string, string]> = {
    pending: ['hourglass-top', colors.tertiary, 'Waiting for approval'],
    approved: ['check-circle-outline', colors.primary, 'Approved — tap Check again'],
    rejected: ['block', colors.error, 'Not approved'],
    revoked: ['undo', colors.onSurfaceVariant, 'Withdrawn by the clinic'],
    open: ['hourglass-empty', colors.onSurfaceVariant, 'Not sent'],
  };
  const [icon, color, text] = look[request.status];
  return (
    <AppCard>
      <ListTile
        leading={<Icon name={icon} color={color} />}
        title={request.clinicName}
        subtitle={`${roleDisplayName(request.role)} · ${text}`}
      />
    </AppCard>
  );
}
