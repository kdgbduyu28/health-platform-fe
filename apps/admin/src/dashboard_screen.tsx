import {
  AccountMenuButton,
  AppointmentCard,
  AsyncView,
  Breakpoints,
  CardColumns,
  ClinicTitle,
  Icon,
  type IconName,
  NotificationsButton,
  Page,
  isOnSite,
  refreshAppointments,
  statusMeta,
  useAppTheme,
  useClinicNav,
  useLayoutWidth,
  usePatientCount,
  useReadable,
  useTodayAppointments,
  useUpcomingAppointments,
  withAlpha,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { View } from 'react-native';
import { Button, Text } from 'react-native-paper';

export function DashboardScreen() {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const qc = useQueryClient();
  const nav = useClinicNav();
  const todayAsync = useTodayAppointments();
  const upcomingAsync = useUpcomingAppointments();
  const patientCount = usePatientCount().value ?? null;
  const [width, onLayout] = useLayoutWidth();

  const today = todayAsync.value ?? [];
  const upcoming = upcomingAsync.value ?? [];
  const pending = today.filter((a) => a.status === 'pending').length;
  // Checked in and waiting, or with a doctor.
  const inClinic = today.filter((a) => isOnSite(a.status)).length;
  const completed = today.filter((a) => a.status === 'completed').length;

  const todayRow = (
    <View style={{ flexDirection: 'row', gap: 8 }}>
      <StatCard label="Total" value={today.length} icon="event" color={colors.primary} />
      <StatCard label="Pending" value={pending} icon="schedule" color={readable(statusMeta.pending.color)} />
      <StatCard label="In clinic" value={inClinic} icon="chair" color={readable(statusMeta.arrived.color)} />
      <StatCard label="Done" value={completed} icon="task-alt" color={readable(statusMeta.completed.color)} />
    </View>
  );
  // The clinic at large.
  const overall = (
    <View style={{ flexDirection: 'row', gap: 12 }}>
      <BigStatCard label="Total Patients" value={patientCount ?? 0} icon="group" />
      <BigStatCard label="Upcoming" value={upcoming.length} icon="calendar-month" />
    </View>
  );

  return (
    <Page
      title={
        <View>
          {/* The date on the line above, so it is not in a chip too. */}
          <Text variant="bodyMedium" style={{ color: colors.onSurfaceVariant }}>
            {format(new Date(), 'EEEE, MMMM d')}
          </Text>
          <ClinicTitle page="Dashboard" />
        </View>
      }
      actions={
        <>
          <NotificationsButton />
          <AccountMenuButton />
        </>
      }
    >
      <Text variant="titleMedium" style={{ fontWeight: '700', marginBottom: 12 }}>
        Today's Overview
      </Text>
      {/* Room for both on one line: today on the left, the clinic at large
          on the right. */}
      <View onLayout={onLayout}>
        {width >= Breakpoints.twoPane ? (
          <View style={{ flexDirection: 'row', gap: 12, alignItems: 'stretch' }}>
            <View style={{ flex: 3 }}>{todayRow}</View>
            <View style={{ flex: 2 }}>{overall}</View>
          </View>
        ) : (
          <View style={{ gap: 24 }}>
            {todayRow}
            {overall}
          </View>
        )}
      </View>

      <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 24, marginBottom: 8 }}>
        <Text variant="titleMedium" style={{ flex: 1, fontWeight: '700' }}>
          Today's Schedule
        </Text>
        <Button onPress={() => nav.go('/schedule')}>View All</Button>
      </View>
      {!todayAsync.hasValue ? (
        <AsyncView value={todayAsync} padded onRetry={() => void refreshAppointments(qc)}>
          {() => null}
        </AsyncView>
      ) : today.length === 0 ? (
        <Text style={{ textAlign: 'center', paddingVertical: 24 }}>No appointments scheduled today.</Text>
      ) : (
        <CardColumns>
          {today.map((a) => (
            <AppointmentCard key={a.id} appointment={a} showPatient onPress={() => nav.push(`/appointments/${a.id}`)} />
          ))}
        </CardColumns>
      )}
    </Page>
  );
}

function StatCard({ label, value, icon, color }: { label: string; value: number; icon: IconName; color: string }) {
  return (
    <View
      style={{
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        paddingVertical: 12,
        paddingHorizontal: 8,
        borderRadius: 12,
        backgroundColor: withAlpha(color, 25 / 255),
        borderWidth: 1,
        borderColor: withAlpha(color, 60 / 255),
      }}
    >
      <Icon name={icon} size={20} color={color} />
      <Text style={{ marginTop: 4, fontWeight: '700', fontSize: 18, color }}>{value}</Text>
      <Text style={{ fontSize: 10, color, textAlign: 'center' }}>{label}</Text>
    </View>
  );
}

function BigStatCard({ label, value, icon }: { label: string; value: number; icon: IconName }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ width: 44, height: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.primaryContainer }}>
        <Icon name={icon} color={colors.onPrimaryContainer} />
      </View>
      <View>
        <Text style={{ fontWeight: '700', fontSize: 22 }}>{value}</Text>
        <Text style={{ fontSize: 11, color: colors.onSurfaceVariant }}>{label}</Text>
      </View>
    </View>
  );
}
