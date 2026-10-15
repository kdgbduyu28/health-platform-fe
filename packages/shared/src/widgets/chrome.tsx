import { format } from 'date-fns';
import { useState } from 'react';
import { FlatList, Pressable, View } from 'react-native';
import { Badge, Button, Dialog, Divider, IconButton, ProgressBar, Text, Tooltip } from 'react-native-paper';

import { useRailShowsClinic } from '../app/adaptive';
import { useClinicNav } from '../app/navigation';
import { clinicHome } from '../app/paths';
import { registersPatients, takesStaffCodes } from '../models/app_role';
import type { AppNotification } from '../models/app_notification';
import type { Clinic } from '../models/clinic';
import { useCurrentClinic, useCurrentClinicId, useMyClinics } from '../queries/clinic';
import {
  type PushState,
  useNotifications,
  usePushActions,
  usePushState,
  useUnreadNotifications,
} from '../queries/misc';
import { StaffCodeScreen } from '../screens/staff_code_screen';
import { useStaffPin } from '../screens/staff_pin';
import { useAppRole, useCurrentUser, usePlatform } from '../state/platform';
import { ClinicMark } from '../theme/brand';
import { useAppTheme } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { TextField, useForm } from '../ui/fields';
import { Icon, type IconName } from '../ui/icon';
import { Avatar, ListTile, MenuButton } from '../ui/kit';
import { type Close, useOverlay } from '../ui/overlay';

/// The current clinic's mark and name, for an app bar title.
///
/// When the user belongs to more than one clinic in this app, the title is
/// also the switcher: tap it to pick another clinic, and the whole app —
/// data and theme — follows.
///
/// With [page], a desktop — whose side rail already names the clinic, and
/// switches it — shows [page] here instead, so the name is not there twice.
export function ClinicTitle({ page, markSize = 28 }: { page?: string; markSize?: number }) {
  const railShowsClinic = useRailShowsClinic();
  const clinic = useCurrentClinic().value ?? null;
  const clinics = useMyClinics().value ?? [];
  const switcher = useClinicSwitcher();
  if (page != null && railShowsClinic) {
    return (
      <Text variant="titleLarge" numberOfLines={1}>
        {page}
      </Text>
    );
  }
  const canSwitch = clinics.length > 1;
  const content = (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
      <ClinicMark clinic={clinic} size={markSize} />
      <Text variant="titleLarge" numberOfLines={1} style={{ flexShrink: 1 }}>
        {clinic?.name ?? ''}
      </Text>
      {canSwitch && <Icon name="expand-more" />}
    </View>
  );
  if (!canSwitch) return content;
  return (
    <Pressable accessibilityRole="button" accessibilityLabel="Switch clinic" onPress={switcher} style={{ borderRadius: 8, alignSelf: 'flex-start' }}>
      {content}
    </Pressable>
  );
}

/// A sheet listing every clinic this user can use the current app at.
/// Picking one opens it at its own URL.
export function useClinicSwitcher(): () => void {
  const overlay = useOverlay();
  const clinics = useMyClinics().value ?? [];
  const currentId = useCurrentClinicId();
  const app = useAppRole();
  const nav = useClinicNav();
  return () =>
    void overlay.showSheet((close) => (
      <ClinicSwitcherSheet
        clinics={clinics}
        currentId={currentId}
        onPick={(c) => {
          close();
          nav.goTo(clinicHome(c.slug, app));
        }}
      />
    ));
}

function ClinicSwitcherSheet({ clinics, currentId, onPick }: { clinics: Clinic[]; currentId: string | null; onPick: (c: Clinic) => void }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ paddingBottom: 16 }}>
      <Text variant="titleMedium" style={{ fontWeight: '700', paddingHorizontal: 24, paddingBottom: 8 }}>
        Switch clinic
      </Text>
      {clinics.map((clinic) => (
        <ListTile
          key={clinic.id}
          paddingHorizontal={24}
          leading={<ClinicMark clinic={clinic} size={36} />}
          title={clinic.name}
          subtitle={clinic.typeName}
          trailing={clinic.id === currentId ? <Icon name="check" color={colors.primary} /> : undefined}
          onPress={() => onPick(clinic)}
        />
      ))}
    </View>
  );
}

/// The signed-in account's menu, for an app bar: who is signed in, settings,
/// change password, sign out — and in the doctor and assistant apps, joining
/// another clinic with a staff code; where patients are registered, the PIN
/// that takes the tablet back from one.
export function AccountMenuButton() {
  const email = useCurrentUser()?.email;
  const { app, repo } = usePlatform();
  const nav = useClinicNav();
  const overlay = useOverlay();
  const pin = useStaffPin();
  const changePassword = useChangePasswordDialog();
  return (
    <MenuButton
      icon="account-circle"
      label="Account"
      items={[
        { header: email ?? 'Signed in' },
        'divider',
        { label: 'Settings', icon: 'settings', onPress: () => nav.push('/preferences') },
        ...(takesStaffCodes(app)
          ? [
              {
                label: 'Join another clinic',
                icon: 'add-business' as IconName,
                onPress: () => void overlay.showPage((close) => <StaffCodeScreen close={close} />),
              },
            ]
          : []),
        // Knowing the old PIN is not asked: whoever holds this menu is signed
        // in as the account already, which is more than a PIN.
        ...(registersPatients(app) ? [{ label: 'Set tablet PIN', icon: 'pin' as IconName, onPress: () => void pin.setPin() }] : []),
        { label: 'Change password', icon: 'password', onPress: changePassword },
        // Signing out drops every RLS grant; the router returns to the
        // sign-in screen on its own.
        { label: 'Sign out', icon: 'logout', onPress: () => void repo.signOut() },
      ]}
    />
  );
}

/// Asks for a new password for the signed-in account and saves it.
export function useChangePasswordDialog(): () => void {
  const overlay = useOverlay();
  return async () => {
    const changed = await overlay.showDialog<boolean>((close) => <ChangePasswordDialog close={close} />);
    if (changed) overlay.snack('Password changed');
  };
}

function ChangePasswordDialog({ close }: { close: Close<boolean> }) {
  const { colors } = useAppTheme();
  const { repo } = usePlatform();
  const form = useForm({ password: '', confirm: '' });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    if (busy) return;
    const ok = form.validate({
      password: (v) => (v.length < 6 ? 'At least 6 characters' : null),
      confirm: (v, all) => (v !== all.password ? 'The passwords do not match' : null),
    });
    if (!ok) return;
    setBusy(true);
    setError(null);
    try {
      await repo.changePassword(form.values.password);
      close(true);
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <Dialog.Title>Change password</Dialog.Title>
      <Dialog.Content style={{ gap: 12 }}>
        <TextField
          label="New password"
          secure
          autoFocus
          autoComplete="new-password"
          value={form.values.password}
          onChangeText={form.set('password')}
          error={form.errors.password}
        />
        <TextField
          label="Confirm new password"
          secure
          value={form.values.confirm}
          onChangeText={form.set('confirm')}
          error={form.errors.confirm}
          onSubmit={save}
        />
        {error != null && <Text style={{ color: colors.error }}>{error}</Text>}
      </Dialog.Content>
      <Dialog.Actions>
        <Button disabled={busy} onPress={() => close(false)}>
          Cancel
        </Button>
        <Button mode="contained" disabled={busy} onPress={save}>
          Save
        </Button>
      </Dialog.Actions>
    </>
  );
}

/// A bell for an app bar: the unread count, and the inbox on tap.
export function NotificationsButton({ color }: { color?: string }) {
  const unread = useUnreadNotifications();
  const nav = useClinicNav();
  const open = useNotificationsSheet();
  return (
    <View>
      <Tooltip title="Notifications">
        <IconButton
          icon={unread > 0 ? 'notifications-active' : 'notifications-none'}
          iconColor={color}
          accessibilityLabel="Notifications"
          onPress={() => open(nav.path('/preferences'))}
        />
      </Tooltip>
      {unread > 0 && (
        <Badge size={18} style={{ position: 'absolute', top: 4, right: 4 }}>
          {unread > 99 ? '99+' : unread}
        </Badge>
      )}
    </View>
  );
}

/// The inbox. [settingsPath] adds a gear that opens Settings.
export function useNotificationsSheet(): (settingsPath?: string) => void {
  const overlay = useOverlay();
  return (settingsPath) => void overlay.showSheet((close) => <NotificationsSheet close={close} settingsPath={settingsPath} />);
}

function NotificationsSheet({ close, settingsPath }: { close: Close<void>; settingsPath?: string }) {
  const { colors } = useAppTheme();
  const { app, repo } = usePlatform();
  const nav = useClinicNav();
  const unread = useUnreadNotifications();
  const notifications = useNotifications();

  return (
    <View style={{ maxHeight: '100%', flexShrink: 1 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', paddingLeft: 20, paddingRight: 8, paddingBottom: 8 }}>
        <Text variant="titleLarge" style={{ flex: 1, fontWeight: '700' }}>
          Notifications
        </Text>
        {unread > 0 && <Button onPress={() => void repo.markNotificationsRead(app)}>Mark all read</Button>}
        {settingsPath != null && (
          <IconButton
            icon="settings"
            accessibilityLabel="Notification settings"
            onPress={() => {
              close();
              nav.pushTo(settingsPath);
            }}
          />
        )}
      </View>
      <View style={{ paddingHorizontal: 16 }}>
        <PushSettingsCard />
      </View>
      <View style={{ height: 8 }} />
      <AsyncView value={notifications} padded>
        {(list) =>
          list.length === 0 ? (
            <Text style={{ textAlign: 'center', padding: 32, color: colors.onSurfaceVariant }}>
              Nothing yet. Updates about visits and bills show up here.
            </Text>
          ) : (
            <FlatList
              data={list}
              keyExtractor={(n) => n.id}
              style={{ flexShrink: 1 }}
              ItemSeparatorComponent={() => <Divider style={{ marginLeft: 72 }} />}
              renderItem={({ item }) => (
                <NotificationTile
                  notification={item}
                  onOpen={() => {
                    if (!item.isRead) void repo.markNotificationsRead(item.app, [item.id]);
                    close();
                    if (item.link != null) nav.goTo(item.link);
                  }}
                />
              )}
            />
          )
        }
      </AsyncView>
    </View>
  );
}

function NotificationTile({ notification: n, onOpen }: { notification: AppNotification; onOpen: () => void }) {
  const { colors } = useAppTheme();
  return (
    <ListTile
      paddingHorizontal={20}
      leading={
        <Avatar
          icon={n.icon}
          color={n.isRead ? colors.surfaceContainerHighest : colors.primaryContainer}
          textColor={n.isRead ? colors.onSurfaceVariant : colors.onPrimaryContainer}
        />
      }
      title={<Text style={{ fontWeight: n.isRead ? '400' : '600' }}>{n.title}</Text>}
      subtitle={
        <View>
          <Text style={{ color: colors.onSurfaceVariant }}>{n.body}</Text>
          <Text style={{ fontSize: 12, color: colors.outline, marginTop: 2 }}>{ago(n.createdAt)}</Text>
        </View>
      }
      onPress={onOpen}
    />
  );
}

export function ago(t: Date, now: Date = new Date()): string {
  const minutes = Math.floor((now.getTime() - t.getTime()) / 60_000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  if (Math.floor(hours / 24) < 7) return format(t, 'EEEE');
  return format(t, 'MMM d');
}

/// Turns push notifications on or off for this browser, or says why it
/// cannot.
export function PushSettingsCard() {
  const { colors } = useAppTheme();
  const state = usePushState();
  const actions = usePushActions();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const run = async (work: () => Promise<void>) => {
    setBusy(true);
    setError(null);
    try {
      await work();
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  };

  if (busy || state.isLoading) return <ProgressBar indeterminate />;
  // A failed turn-on leaves no value behind; offer to try again.
  const s: PushState | null = state.value ?? (state.hasError ? 'off' : null);
  const look: Record<PushState, [IconName, string, React.ReactNode]> = {
    on: [
      'notifications-active',
      'Push notifications are on for this device.',
      <Button key="off" onPress={() => run(actions.disable)}>
        Turn off
      </Button>,
    ],
    off: [
      'notifications-off',
      'Get these on this device even when the app is closed.',
      <Button key="on" mode="contained-tonal" onPress={() => run(actions.enable)}>
        Turn on
      </Button>,
    ],
    blocked: ['block', "Notifications are blocked for this site. Allow them in your browser's site settings.", null],
    needs_home_screen: [
      'ios-share',
      'On iPhone, tap Share → Add to Home Screen, open the app from there, then turn notifications on.',
      null,
    ],
    unsupported: ['info-outline', 'This browser cannot show push notifications. Check back here for updates.', null],
  };
  const [icon, text, action] = look[s ?? 'unsupported'];
  const shownError = error ?? (state.hasError ? state.error : null);
  return (
    <View style={{ padding: 8, paddingLeft: 12, borderRadius: 12, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
        <Icon name={icon} size={20} color={colors.primary} />
        <Text style={{ flex: 1, fontSize: 13 }}>{text}</Text>
        {action}
      </View>
      {shownError != null && (
        <Text style={{ marginTop: 6, marginLeft: 30, color: colors.error, fontSize: 12 }}>{describeError(shownError)}</Text>
      )}
    </View>
  );
}
