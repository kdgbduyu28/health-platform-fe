import {
  AppCard,
  type Appointment,
  AppointmentCard,
  AsyncView,
  Avatar,
  ClinicTitle,
  ContentWidth,
  GradientBox,
  Icon,
  type IconName,
  ListTile,
  NotificationsButton,
  Page,
  StatusBadge,
  refreshAppointments,
  useAppTheme,
  useClinicChartsTeeth,
  useClinicNav,
  useCurrentClinic,
  useDentalChart,
  useMyPatient,
  useMyProfile,
  useMyUpcomingAppointments,
  withAlpha,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { View } from 'react-native';
import { Button, Text, TouchableRipple } from 'react-native-paper';

export function HomeScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const nav = useClinicNav();
  const clinic = useCurrentClinic().value ?? null;
  const upcomingAsync = useMyUpcomingAppointments();
  const profile = useMyProfile().value ?? null;
  const chartsTeeth = useClinicChartsTeeth();

  return (
    <Page
      maxWidth={ContentWidth.list}
      title={
        <View>
          <Text variant="bodyMedium" style={{ color: colors.onSurfaceVariant }}>
            Good day, {profile?.firstName ?? 'there'}
          </Text>
          <ClinicTitle />
        </View>
      }
      actions={
        <>
          <NotificationsButton />
          <View
            style={{
              marginRight: 16,
              marginLeft: 4,
              flexDirection: 'row',
              alignItems: 'center',
              gap: 4,
              paddingHorizontal: 12,
              paddingVertical: 6,
              borderRadius: 20,
              backgroundColor: colors.primaryContainer,
            }}
          >
            <Icon name={clinic?.icon ?? 'local-hospital'} size={16} color={colors.onPrimaryContainer} />
            <Text style={{ fontSize: 12, fontWeight: '600', color: colors.onPrimaryContainer }}>{clinic?.typeName ?? ''}</Text>
          </View>
        </>
      }
    >
      <AsyncView value={upcomingAsync} padded onRetry={() => void refreshAppointments(qc)}>
        {(upcoming) => (
          <View>
            {upcoming.length > 0 ? (
              <NextAppointmentCard appointment={upcoming[0]} onPress={() => nav.push(`/appointments/${upcoming[0].id}`)} />
            ) : (
              <EmptyCard icon={clinic?.icon ?? 'local-hospital'} />
            )}
            <Button mode="contained" icon="add" onPress={() => nav.push('/book')} style={{ marginTop: 16 }} contentStyle={{ height: 48 }}>
              Book Appointment
            </Button>
            {chartsTeeth && (
              <View style={{ marginTop: 16 }}>
                <MyTeethCard />
              </View>
            )}
            {upcoming.length > 1 && (
              <>
                <Text variant="titleMedium" style={{ marginTop: 24, marginBottom: 12, fontWeight: '700' }}>
                  Upcoming
                </Text>
                <View style={{ gap: 8 }}>
                  {upcoming.slice(1, 4).map((a) => (
                    <AppointmentCard key={a.id} appointment={a} onPress={() => nav.push(`/appointments/${a.id}`)} />
                  ))}
                </View>
              </>
            )}
          </View>
        )}
      </AsyncView>
    </Page>
  );
}

function NextAppointmentCard({ appointment: a, onPress }: { appointment: Appointment; onPress: () => void }) {
  const { colors } = useAppTheme();
  const on = colors.onPrimary;
  return (
    <GradientBox>
      <TouchableRipple onPress={onPress} style={{ padding: 20 }} accessibilityRole="button">
        <View>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Text style={{ flex: 1, color: withAlpha(on, 200 / 255), fontSize: 12 }}>Next Appointment</Text>
            <View style={{ backgroundColor: colors.surface, borderRadius: 20 }}>
              <StatusBadge status={a.status} />
            </View>
          </View>
          <Text variant="titleLarge" style={{ marginTop: 12, color: on, fontWeight: '700' }}>
            {a.service}
          </Text>
          <Text style={{ marginTop: 4, color: withAlpha(on, 220 / 255), fontSize: 14 }}>Dr. {a.doctor.name}</Text>
          <View style={{ marginTop: 16, flexDirection: 'row', gap: 8 }}>
            <Chip icon="calendar-today" text={format(a.dateTime, 'EEE, MMM d')} color={on} />
            <Chip icon="access-time" text={format(a.dateTime, 'h:mm a')} color={on} />
          </View>
        </View>
      </TouchableRipple>
    </GradientBox>
  );
}

function Chip({ icon, text, color }: { icon: IconName; text: string; color: string }) {
  return (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        gap: 4,
        paddingHorizontal: 10,
        paddingVertical: 5,
        borderRadius: 20,
        backgroundColor: withAlpha(color, 50 / 255),
      }}
    >
      <Icon name={icon} size={12} color={color} />
      <Text style={{ color, fontSize: 12 }}>{text}</Text>
    </View>
  );
}

function EmptyCard({ icon }: { icon: IconName }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ padding: 28, borderRadius: 20, backgroundColor: colors.surfaceContainerHighest, alignItems: 'center' }}>
      <Icon name={icon} size={48} color={colors.outline} />
      <Text variant="titleMedium" style={{ marginTop: 12 }}>
        No upcoming appointments
      </Text>
      <Text style={{ marginTop: 4, color: colors.outline }}>Book your first appointment below</Text>
    </View>
  );
}

/// At a dental clinic: the way to the patient's own chart, with what the
/// dentist has recommended next.
function MyTeethCard() {
  const { colors } = useAppTheme();
  const nav = useClinicNav();
  const me = useMyPatient().value ?? null;
  return (
    <AppCard>
      <ListTile
        onPress={() => nav.push('/teeth')}
        leading={<Avatar icon="grid-view" color={colors.primaryContainer} textColor={colors.onPrimaryContainer} />}
        title={<Text style={{ fontWeight: '600' }}>My teeth</Text>}
        subtitle={me == null ? 'Your dental chart and treatment history' : <PlanLine patientId={me.id} />}
        trailing={<Icon name="chevron-right" />}
      />
    </AppCard>
  );
}

function PlanLine({ patientId }: { patientId: string }) {
  const { colors } = useAppTheme();
  const plan = useDentalChart(patientId).value?.plan ?? [];
  return (
    <Text variant="bodyMedium" style={{ color: colors.onSurfaceVariant }}>
      {plan.length === 0
        ? 'Your dental chart and treatment history'
        : `${plan.length} recommended treatment${plan.length === 1 ? '' : 's'}`}
    </Text>
  );
}
