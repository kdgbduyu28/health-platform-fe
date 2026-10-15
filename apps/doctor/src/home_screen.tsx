import {
  AccountMenuButton,
  AppCard,
  type Appointment,
  AppointmentBoard,
  AppointmentViewToggle,
  type AppointmentStatus,
  AsyncView,
  CardColumns,
  ClinicTitle,
  ContentWidth,
  EmptyState,
  Icon,
  NotificationsButton,
  Page,
  PastAppointmentsList,
  SplitColumns,
  StatusBadge,
  Tabs,
  holdsTime,
  isOpenStatus,
  refreshAppointments,
  statusMeta,
  useAppTheme,
  useAppointmentView,
  useClinicNav,
  useCompleteVisitSheet,
  useCurrentClinic,
  useCurrentDoctor,
  useMyDoctorAppointments,
  useMyDoctorToday,
  useReadable,
  useStatusActions,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { type ReactNode, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { Button, Text, TouchableRipple } from 'react-native-paper';

type Tab = 'today' | 'upcoming' | 'past';

const miniStats: [string, AppointmentStatus][] = [
  ['Waiting', 'arrived'],
  ['With you', 'in_consultation'],
  ['Expected', 'confirmed'],
  ['Done', 'completed'],
];

export function DoctorHomeScreen() {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const qc = useQueryClient();
  const clinic = useCurrentClinic().value ?? null;
  const doctor = useCurrentDoctor().value ?? null;
  const todayAsync = useMyDoctorToday();
  const allAsync = useMyDoctorAppointments();
  const board = useAppointmentView() === 'board';
  const [tab, setTab] = useState<Tab>('today');
  const retry = () => void refreshAppointments(qc);

  // The tabs show counts, so they need values before the lists below can
  // render. Empty is the right stand-in while loading; the tab bodies still
  // show a spinner or a real error through AsyncView.
  const now = Date.now();
  const todayAppts = todayAsync.value ?? [];
  const all = allAsync.value ?? [];
  const upcoming = all.filter((a) => a.dateTime.getTime() > now && !a.isToday && holdsTime(a.status));
  // Newest first: the visit a doctor looks back at is usually the last one.
  const past = all.filter((a) => a.dateTime.getTime() < now && !a.isToday).reverse();

  return (
    <Page
      scroll={false}
      title={
        <View>
          {/* Doctors may practise at several clinics; the clinic line is
              also where they switch between them. */}
          <ClinicTitle page="Schedule" markSize={20} />
          <Text variant="titleMedium" numberOfLines={1} style={{ fontWeight: '700' }}>
            {doctor == null ? 'Doctor' : `Dr. ${doctor.name}`}
          </Text>
        </View>
      }
      actions={
        <>
          <View
            style={{
              marginRight: 8,
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
            <Text numberOfLines={1} style={{ fontSize: 12, fontWeight: '600', color: colors.onPrimaryContainer }}>
              {doctor?.specialty || clinic?.typeName || ''}
            </Text>
          </View>
          <AppointmentViewToggle />
          <NotificationsButton />
          <AccountMenuButton />
        </>
      }
      belowAppBar={
        <>
          <Tabs
            value={tab}
            onChange={setTab}
            tabs={[
              { value: 'today', label: `Today (${todayAppts.length})` },
              { value: 'upcoming', label: `Upcoming (${upcoming.length})` },
              { value: 'past', label: 'Past' },
            ]}
          />
          {tab === 'today' && (
            <View style={{ paddingHorizontal: 16, paddingVertical: 12, backgroundColor: colors.surfaceContainerLow }}>
              <View style={{ flexDirection: 'row', gap: 12, width: '100%', maxWidth: ContentWidth.wide, alignSelf: 'center' }}>
                {miniStats.map(([label, status]) => {
                  const color = readable(statusMeta[status].color);
                  return (
                    <View key={status} style={{ alignItems: 'center' }}>
                      <Text style={{ fontWeight: '700', fontSize: 20, color }}>{todayAppts.filter((a) => a.status === status).length}</Text>
                      <Text style={{ fontSize: 11, color }}>{label}</Text>
                    </View>
                  );
                })}
              </View>
            </View>
          )}
        </>
      }
    >
      {tab === 'today' ? (
        <AsyncView value={todayAsync} onRetry={retry}>
          {/* Only this doctor's visits: see useMyDoctorToday. */}
          {(today) => (board && today.length > 0 ? <AppointmentBoard appointments={today} showDoctor={false} /> : <TodayQueue appointments={today} />)}
        </AsyncView>
      ) : tab === 'upcoming' ? (
        <AsyncView value={allAsync} onRetry={retry}>
          {() => <AppointmentListTab appointments={upcoming} emptyMessage="No upcoming appointments" showTime={false} />}
        </AsyncView>
      ) : (
        <AsyncView value={allAsync} onRetry={retry}>
          {/* Recent visits from the loaded window, then older ones a page
              at a time. */}
          {() => (
            <PastAppointmentsList
              recent={past}
              query={{ doctorId: doctor?.id ?? null, patientId: null }}
              emptyMessage="No past appointments"
              renderItem={(a) => <DoctorApptCard appointment={a} showTime={false} />}
            />
          )}
        </AsyncView>
      )}
    </Page>
  );
}

function Scroll({ children }: { children: ReactNode }) {
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16 }}>
      <View style={{ width: '100%', maxWidth: ContentWidth.wide, alignSelf: 'center' }}>{children}</View>
    </ScrollView>
  );
}

function AppointmentListTab({ appointments, emptyMessage, showTime }: { appointments: Appointment[]; emptyMessage: string; showTime: boolean }) {
  if (appointments.length === 0) return <EmptyState icon="event-available" title={emptyMessage} />;
  return (
    <Scroll>
      <CardColumns>
        {appointments.map((a) => (
          <DoctorApptCard key={a.id} appointment={a} showTime={showTime} />
        ))}
      </CardColumns>
    </Scroll>
  );
}

function DoctorApptCard({
  appointment: a,
  showTime,
  action,
  highlight = false,
}: {
  appointment: Appointment;
  showTime: boolean;
  /// The next step for this visit (Start, Complete), under its details.
  action?: ReactNode;
  /// The patient to call in next.
  highlight?: boolean;
}) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const nav = useClinicNav();
  const statusColor = readable(statusMeta[a.status].color);
  return (
    <AppCard style={highlight ? { borderColor: statusColor, borderWidth: 2 } : undefined}>
      <TouchableRipple onPress={() => nav.push(`/appointments/${a.id}`)} accessibilityRole="button">
        <View style={{ flexDirection: 'row', alignItems: 'center', padding: 16 }}>
          {showTime && (
            <View style={{ width: 56, marginRight: 12, paddingVertical: 8, borderRadius: 10, alignItems: 'center', backgroundColor: colors.primaryContainer }}>
              <Text style={{ fontWeight: '700', fontSize: 16, color: colors.onPrimaryContainer }}>{format(a.dateTime, 'h:mm')}</Text>
              <Text style={{ fontSize: 11, color: colors.onPrimaryContainer }}>{format(a.dateTime, 'a')}</Text>
            </View>
          )}
          <View style={{ flex: 1, minWidth: 0 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <Text variant="titleMedium" numberOfLines={1} style={{ flex: 1, fontWeight: '600' }}>
                {a.patient.name}
              </Text>
              <StatusBadge status={a.status} small />
            </View>
            <Text style={{ marginTop: 4, color: colors.onSurfaceVariant }}>{a.service}</Text>
            {!showTime && <Text style={{ fontSize: 12, color: colors.primary }}>{format(a.dateTime, 'EEE, MMM d')}</Text>}
            {a.status === 'arrived' && a.arrivedAt != null && (
              <Text style={{ fontSize: 12, color: statusColor }}>Arrived {format(a.arrivedAt, 'h:mm a')}</Text>
            )}
            {action != null && <View style={{ marginTop: 8, alignItems: 'flex-start' }}>{action}</View>}
          </View>
          <Icon name="chevron-right" />
        </View>
      </TouchableRipple>
    </AppCard>
  );
}

/// Today, as a doctor works through it: who is in with them, who is in the
/// waiting room (in order of arrival), who is still to come, and who is done.
function TodayQueue({ appointments }: { appointments: Appointment[] }) {
  const status = useStatusActions();
  const completeVisit = useCompleteVisitSheet();
  if (appointments.length === 0) return <AppointmentListTab appointments={[]} emptyMessage="No appointments today" showTime />;

  const where = (test: (s: AppointmentStatus) => boolean) => appointments.filter((a) => test(a.status));
  const withMe = where((s) => s === 'in_consultation');
  const waiting = where((s) => s === 'arrived').sort(
    (a, b) => (a.arrivedAt ?? a.dateTime).getTime() - (b.arrivedAt ?? b.dateTime).getTime(),
  );
  const later = where((s) => s === 'pending' || s === 'confirmed');
  const done = where((s) => !isOpenStatus(s));

  const start = (a: Appointment) => (
    <Button
      mode="contained-tonal"
      icon="play-arrow"
      compact
      onPress={() => void status.change(a, 'in_consultation', `Consultation with ${a.patient.name} started`)}
    >
      Start consultation
    </Button>
  );

  const nowItems: ReactNode[] = [];
  if (withMe.length > 0) {
    nowItems.push(<QueueHeader key="h-with">With you now</QueueHeader>);
    for (const a of withMe) {
      nowItems.push(
        <DoctorApptCard
          key={a.id}
          appointment={a}
          showTime
          highlight
          action={
            <Button mode="contained" icon="task-alt" compact onPress={() => void completeVisit(a)}>
              Mark done
            </Button>
          }
        />,
      );
    }
  }
  if (waiting.length > 0) {
    nowItems.push(<QueueHeader key="h-wait">{`Waiting room (${waiting.length})`}</QueueHeader>);
    waiting.forEach((a, i) =>
      nowItems.push(<DoctorApptCard key={a.id} appointment={a} showTime highlight={i === 0 && withMe.length === 0} action={start(a)} />),
    );
  }
  const restItems: ReactNode[] = [];
  if (later.length > 0) {
    restItems.push(<QueueHeader key="h-later">Later today</QueueHeader>);
    for (const a of later) {
      // Clinics with nobody at the desk start straight from here.
      restItems.push(<DoctorApptCard key={a.id} appointment={a} showTime action={a.status === 'confirmed' ? start(a) : undefined} />);
    }
  }
  if (done.length > 0) {
    restItems.push(<QueueHeader key="h-done">Done today</QueueHeader>);
    for (const a of done) restItems.push(<DoctorApptCard key={a.id} appointment={a} showTime />);
  }

  const column = (items: ReactNode[]) => <View style={{ gap: 8 }}>{items}</View>;
  // On a wide screen, who is here now sits beside the rest of the day, so
  // the next patient to call is never scrolled out of sight.
  return (
    <Scroll>
      {nowItems.length === 0 || restItems.length === 0 ? (
        column([...nowItems, ...restItems])
      ) : (
        <SplitColumns start={column(nowItems)} end={column(restItems)} />
      )}
    </Scroll>
  );
}

function QueueHeader({ children }: { children: string }) {
  return (
    <Text variant="titleSmall" style={{ paddingHorizontal: 4, paddingTop: 12, paddingBottom: 0, fontWeight: '700' }}>
      {children}
    </Text>
  );
}
