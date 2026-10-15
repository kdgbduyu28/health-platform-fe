import { useRouter } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';
import { Button, Divider, ProgressBar, SegmentedButtons, Switch, Text } from 'react-native-paper';

import { ContentWidth } from '../app/adaptive';
import { privacyPolicy, termsAndConditions } from '../legal/documents';
import { isStaffRole, registersPatients, roleDisplayName, takesStaffCodes } from '../models/app_role';
import { toothNumberingLabel, type ToothNumbering } from '../models/dental_chart';
import { useCurrentClinic, useMyProfile } from '../queries/clinic';
import {
  type PushState,
  useNotificationMutes,
  usePushActions,
  usePushState,
  useSetNotificationEnabled,
} from '../queries/misc';
import { notificationTopicsFor } from '../models/app_notification';
import { useAppRole, useCurrentUser, usePlatform } from '../state/platform';
import { preferences, textSizeMeta, textSizes, type TextSize, type ThemeMode, usePreference } from '../state/preferences';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, Avatar, ListTile } from '../ui/kit';
import { useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { useChangePasswordDialog } from '../widgets/chrome';
import { useQueryClient } from '@tanstack/react-query';
import { JoinClinicScreen } from './join_clinic_screen';
import { StaffCodeScreen } from './staff_code_screen';
import { useStaffPin } from './staff_pin';

/// `/:clinic/preferences`: how this app looks and what it tells you, plus
/// the account's own chores. The same page in all four apps; what is on it
/// follows the app and the clinic.
///
/// Two kinds of setting live here, and the page says which is which:
///   this device   theme, text size, push, tooth numbering — in the
///                 browser's storage, so a shared front desk tablet keeps its
///                 own
///   your account  which notifications to get — in the database, so they
///                 follow the person to every device
export function SettingsScreen({ back }: { back?: string }) {
  const clinic = useCurrentClinic().value ?? null;
  return (
    <Page title="Settings" maxWidth={ContentWidth.list} back={back}>
      <AccountHeader />
      <SectionTitle title="Appearance" note="On this device" />
      <AppearanceCard />
      <SectionTitle title="Notifications" />
      <NotificationsCard />
      {clinic?.isDental && (
        <>
          <SectionTitle title="Dental chart" note="On this device" />
          <DentalCard />
        </>
      )}
      <SectionTitle title="Account" />
      <AccountCard />
      <SectionTitle title="About" />
      <AboutCard />
    </Page>
  );
}

function SectionTitle({ title, note }: { title: string; note?: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 8, paddingHorizontal: 4, paddingTop: 24, paddingBottom: 8 }}>
      <Text variant="titleSmall" style={{ color: colors.primary, fontWeight: '700' }}>
        {title}
      </Text>
      {note != null && (
        <Text variant="bodySmall" style={{ color: colors.outline }}>
          {note}
        </Text>
      )}
    </View>
  );
}

/// Who is signed in, and where.
function AccountHeader() {
  const { colors } = useAppTheme();
  const profile = useMyProfile().value ?? null;
  const email = useCurrentUser()?.email ?? '';
  const clinic = useCurrentClinic().value ?? null;
  const app = useAppRole();
  const name = profile?.fullName ? profile.fullName : email;
  const where = [...(isStaffRole(app) ? [roleDisplayName(app)] : []), ...(clinic != null ? [clinic.name] : [])].join(' · ');
  return (
    <AppCard padding={16}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16 }}>
        <Avatar label={profile?.initials ?? '?'} size={56} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text variant="titleMedium" numberOfLines={1} style={{ fontWeight: '600' }}>
            {name}
          </Text>
          {name !== email && email !== '' && (
            <Text numberOfLines={1} style={{ color: colors.onSurfaceVariant }}>
              {email}
            </Text>
          )}
          {where !== '' && (
            <Text variant="bodySmall" style={{ marginTop: 2, color: colors.outline }}>
              {where}
            </Text>
          )}
        </View>
      </View>
    </AppCard>
  );
}

function Label({ text }: { text: string }) {
  return <Text style={{ fontWeight: '600', marginBottom: 8 }}>{text}</Text>;
}

function Hint({ text }: { text: string }) {
  const { colors } = useAppTheme();
  return <Text style={{ marginTop: 8, fontSize: 12, color: colors.onSurfaceVariant }}>{text}</Text>;
}

function AppearanceCard() {
  const mode = usePreference((p) => p.themeMode);
  const size = usePreference((p) => p.textSize);
  return (
    <AppCard padding={16}>
      <Label text="Theme" />
      <SegmentedButtons
        value={mode}
        onValueChange={(v) => preferences.setThemeMode(v as ThemeMode)}
        buttons={[
          { value: 'system', icon: 'brightness-auto', label: 'Auto' },
          { value: 'light', icon: 'light-mode', label: 'Light' },
          { value: 'dark', icon: 'dark-mode', label: 'Dark' },
        ]}
      />
      {mode === 'system' && <Hint text="Switches with your device's light or dark setting." />}
      <View style={{ height: 20 }} />
      <Label text="Text size" />
      <SegmentedButtons
        value={size}
        onValueChange={(v) => preferences.setTextSize(v as TextSize)}
        buttons={textSizes.map((s) => ({ value: s, label: textSizeMeta[s].label }))}
      />
    </AppCard>
  );
}

function NotificationsCard() {
  const { colors } = useAppTheme();
  const app = useAppRole();
  const overlay = useOverlay();
  const qc = useQueryClient();
  const topics = notificationTopicsFor(app);
  const mutes = useNotificationMutes();
  const setEnabled = useSetNotificationEnabled();

  const toggle = async (kind: string, on: boolean) => {
    try {
      await setEnabled(kind, on);
    } catch (e) {
      overlay.snack(`Could not save: ${describeError(e)}`);
    }
  };

  return (
    <AppCard>
      <PushTile />
      <Divider />
      <Text style={{ fontWeight: '600', paddingHorizontal: 16, paddingTop: 16, paddingBottom: 4 }}>Tell me about</Text>
      <Text style={{ paddingHorizontal: 16, paddingBottom: 4, fontSize: 12, color: colors.onSurfaceVariant }}>
        For your account, on every device. Anything switched off here is neither shown in the inbox nor pushed.
      </Text>
      {mutes.hasError && !mutes.hasValue ? (
        <View style={{ flexDirection: 'row', alignItems: 'center', paddingLeft: 16, paddingRight: 8, paddingTop: 4, paddingBottom: 12 }}>
          <Text style={{ flex: 1, color: colors.error, fontSize: 13 }}>These choices could not be loaded. Everything is on.</Text>
          <Button onPress={() => void qc.invalidateQueries({ queryKey: ['notificationMutes'] })}>Retry</Button>
        </View>
      ) : (
        topics.map((t) => {
          const on = !(mutes.value?.has(t.kind) ?? false);
          return (
            <ListTile
              key={t.kind}
              title={t.label}
              subtitle={t.description}
              onPress={mutes.hasValue ? () => void toggle(t.kind, !on) : undefined}
              trailing={<Switch value={on} disabled={!mutes.hasValue} onValueChange={(v) => void toggle(t.kind, v)} />}
            />
          );
        })
      )}
      <View style={{ height: 4 }} />
    </AppCard>
  );
}

/// Push for this browser: a switch when there is a choice to make, and the
/// reason when there is not.
function PushTile() {
  const { colors } = useAppTheme();
  const state = usePushState();
  const actions = usePushActions();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  // A failed turn-on leaves no value behind; offer to try again.
  const s: PushState | null = state.value ?? (state.hasError ? 'off' : null);
  const subtitle: Record<PushState | 'checking', string> = {
    on: 'On for this device, even when the app is closed.',
    off: 'Off for this device. Turn on to get alerts when the app is closed.',
    blocked: "Blocked for this site. Allow notifications in your browser's site settings, then come back.",
    needs_home_screen: 'On iPhone, tap Share → Add to Home Screen, open the app from there, then turn this on.',
    unsupported: 'This browser cannot show push notifications. The inbox (the bell) still gets everything.',
    checking: 'Checking this device…',
  };
  const loading = busy || state.isLoading;
  const canToggle = !loading && (s === 'on' || s === 'off');
  const toggle = async (on: boolean) => {
    setBusy(true);
    setError(null);
    try {
      await (on ? actions.enable() : actions.disable());
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  };
  const shownError = error ?? (state.hasError ? state.error : null);
  return (
    <View>
      <ListTile
        leading={<Icon name={s === 'on' ? 'notifications-active' : 'notifications-off'} color={colors.primary} />}
        title="Push notifications"
        subtitle={subtitle[s ?? 'checking']}
        onPress={canToggle ? () => void toggle(s !== 'on') : undefined}
        trailing={<Switch value={s === 'on'} disabled={!canToggle} onValueChange={(v) => void toggle(v)} />}
      />
      {loading && <ProgressBar indeterminate style={{ height: 2 }} />}
      {shownError != null && (
        <Text style={{ paddingLeft: 72, paddingRight: 16, paddingBottom: 12, color: colors.error, fontSize: 12 }}>{describeError(shownError)}</Text>
      )}
    </View>
  );
}

function DentalCard() {
  const numbering = usePreference((p) => p.toothNumbering);
  return (
    <AppCard padding={16}>
      <Label text="Tooth numbering" />
      <SegmentedButtons
        value={numbering}
        onValueChange={(v) => preferences.setToothNumbering(v as ToothNumbering)}
        buttons={(['fdi', 'universal'] as const).map((n) => ({ value: n, label: toothNumberingLabel[n] }))}
      />
      <Hint
        text={
          numbering === 'fdi'
            ? 'Two digits: quadrant, then tooth. Upper right molar is 18.'
            : '1–32 from the upper right. Upper right molar is 1.'
        }
      />
    </AppCard>
  );
}

function AccountCard() {
  const { colors } = useAppTheme();
  const { app, repo } = usePlatform();
  const overlay = useOverlay();
  const changePassword = useChangePasswordDialog();
  const pin = useStaffPin();
  const chevron = <Icon name="chevron-right" color={colors.onSurfaceVariant} />;
  const leading = (icon: IconName) => <Icon name={icon} color={colors.onSurfaceVariant} />;

  const confirmSignOut = async () => {
    const ok = await overlay.confirm({
      title: 'Sign out?',
      message: 'Push notifications stop on this device until you sign in again.',
      confirmLabel: 'Sign out',
    });
    // Signing out drops every RLS grant; the router takes it from there.
    if (ok) await repo.signOut();
  };

  return (
    <AppCard>
      <ListTile leading={leading('password')} title="Change password" trailing={chevron} onPress={changePassword} />
      {registersPatients(app) && (
        <ListTile
          leading={leading('pin')}
          title="Tablet PIN"
          subtitle="Takes the tablet back after a patient fills in their form"
          trailing={chevron}
          onPress={async () => {
            if (await pin.setPin()) overlay.snack('PIN saved');
          }}
        />
      )}
      {app === 'patient' && (
        <ListTile
          leading={leading('add-business')}
          title="Join another clinic"
          trailing={chevron}
          onPress={() => void overlay.showPage((close) => <JoinClinicScreen close={close} />)}
        />
      )}
      {takesStaffCodes(app) && (
        <ListTile
          leading={leading('add-business')}
          title="Join another clinic"
          subtitle="With a staff code from its admin"
          trailing={chevron}
          onPress={() => void overlay.showPage((close) => <StaffCodeScreen close={close} />)}
        />
      )}
      <Divider />
      <ListTile
        leading={<Icon name="logout" color={colors.error} />}
        title={<Text style={{ color: colors.error }}>Sign out</Text>}
        onPress={() => void confirmSignOut()}
      />
    </AppCard>
  );
}

function AboutCard() {
  const { colors } = useAppTheme();
  const app = useAppRole();
  const router = useRouter();
  const overlay = useOverlay();
  const clinic = useCurrentClinic().value ?? null;
  const chevron = <Icon name="chevron-right" color={colors.onSurfaceVariant} />;
  return (
    <AppCard>
      <ListTile leading={<Icon name="apps" color={colors.onSurfaceVariant} />} title={`${roleDisplayName(app)} app`} subtitle={clinic?.name} />
      {(
        [
          ['privacy-tip', privacyPolicy],
          ['gavel', termsAndConditions],
        ] as const
      ).map(([icon, document]) => (
        <ListTile
          key={document.id}
          leading={<Icon name={icon} color={colors.onSurfaceVariant} />}
          title={document.title}
          trailing={chevron}
          onPress={() => router.push(`/${document.id}` as never)}
        />
      ))}
      <ListTile
        leading={<Icon name="restart-alt" color={colors.onSurfaceVariant} />}
        title="Reset this device's settings"
        subtitle="Theme, text size and tooth numbering"
        onPress={() => {
          preferences.resetDisplay();
          overlay.snack('Settings reset');
        }}
      />
    </AppCard>
  );
}
