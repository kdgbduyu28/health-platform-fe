import {
  ContentWidth,
  GradientBox,
  Icon,
  type IconName,
  JoinClinicScreen,
  ListTile,
  useAppTheme,
  useCalendarFeedSheet,
  useChangePasswordDialog,
  useClinicNav,
  useCurrentClinic,
  useMyPatient,
  useMyProfile,
  useOverlay,
  useRepository,
  withAlpha,
} from '@health/shared';
import { ScrollView, View } from 'react-native';
import { Appbar, Button, Text } from 'react-native-paper';

export function ProfileScreen() {
  const { colors } = useAppTheme();
  const nav = useClinicNav();
  const overlay = useOverlay();
  const repo = useRepository();
  const openFeed = useCalendarFeedSheet();
  const changePassword = useChangePasswordDialog();
  const clinic = useCurrentClinic().value ?? null;
  const profile = useMyProfile().value ?? null;
  const patient = useMyPatient().value ?? null;
  const on = colors.onPrimary;

  // Name and contact come from the person record behind this clinic's chart
  // — what the clinic itself sees. The profile stands in while that loads.
  const displayName = patient?.name ?? profile?.fullName ?? '';
  const initials = patient?.initials ?? profile?.initials ?? '?';
  const phone = patient?.phone ?? profile?.phone ?? '—';
  const email = patient != null && patient.email !== '' ? patient.email : profile?.email ?? '—';
  const age = patient?.age ?? null;

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.surface }}>
      <GradientBox radius={0} style={{ height: 200 }}>
        <View style={{ position: 'absolute', top: 4, right: 4 }}>
          <Appbar.Action icon="settings" color={on} accessibilityLabel="Settings" onPress={() => nav.push('/preferences')} />
        </View>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', paddingTop: 24 }}>
          <View
            style={{
              width: 80,
              height: 80,
              borderRadius: 40,
              backgroundColor: withAlpha(on, 50 / 255),
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <Text style={{ fontSize: 32, fontWeight: '700', color: on }}>{initials}</Text>
          </View>
          <Text variant="titleLarge" style={{ marginTop: 8, color: on, fontWeight: '700' }}>
            {displayName}
          </Text>
          <Text style={{ color: withAlpha(on, 200 / 255), fontSize: 13 }}>{clinic?.name ?? ''}</Text>
        </View>
      </GradientBox>
      <View style={{ width: '100%', maxWidth: ContentWidth.list + 32, alignSelf: 'center', padding: 16, paddingBottom: 32 }}>
        <ProfileTile icon="phone" label="Phone" value={phone} />
        <ProfileTile icon="email" label="Email" value={email} />
        {age != null && <ProfileTile icon="cake" label="Age" value={`${age} years old`} />}
        <View style={{ height: 24 }} />
        <View style={{ gap: 12 }}>
          <Button mode="contained-tonal" icon="receipt-long" onPress={() => nav.push('/bills')}>
            Bills & payments
          </Button>
          <Button mode="contained-tonal" icon="event-available" onPress={openFeed}>
            Visits in my calendar
          </Button>
          <Button mode="outlined" icon="add-business" onPress={() => void overlay.showPage((close) => <JoinClinicScreen close={close} />)}>
            Join another clinic
          </Button>
          <Button mode="outlined" icon="assignment-ind" onPress={() => nav.push('/intake')}>
            My information & health form
          </Button>
          <Button mode="outlined" icon="settings" onPress={() => nav.push('/preferences')}>
            Settings
          </Button>
          <Button mode="outlined" icon="password" onPress={changePassword}>
            Change password
          </Button>
          {/* Signing out clears the session, which drops every RLS grant
              with it — the router then returns to the sign-in screen. */}
          <Button
            mode="outlined"
            icon="logout"
            textColor={colors.error}
            style={{ borderColor: colors.error }}
            onPress={() => void repo.signOut()}
          >
            Sign Out
          </Button>
        </View>
      </View>
    </ScrollView>
  );
}

function ProfileTile({ icon, label, value }: { icon: IconName; label: string; value: string }) {
  const { colors } = useAppTheme();
  return (
    <ListTile
      paddingHorizontal={0}
      leading={
        <View
          style={{
            width: 40,
            height: 40,
            borderRadius: 10,
            backgroundColor: colors.primaryContainer,
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Icon name={icon} size={20} color={colors.onPrimaryContainer} />
        </View>
      }
      title={<Text style={{ fontSize: 12, color: colors.onSurfaceVariant }}>{label}</Text>}
      subtitle={<Text style={{ fontWeight: '600', fontSize: 15 }}>{value}</Text>}
    />
  );
}
