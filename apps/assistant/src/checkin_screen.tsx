import {
  AccountMenuButton,
  AppCard,
  type Appointment,
  AppointmentBoard,
  AppointmentViewToggle,
  type AppointmentStatus,
  AsyncView,
  Avatar,
  CardColumns,
  ClinicTitle,
  ContentWidth,
  EmptyState,
  Icon,
  type IconName,
  NotificationsButton,
  Page,
  StatusBadge,
  TextField,
  Wrap,
  describeError,
  invalidateBilling,
  refreshAppointments,
  staffCanCancel,
  statusMeta,
  useAppTheme,
  useAppointmentById,
  useAppointmentView,
  useClinicNav,
  useCompleteVisitSheet,
  useOverlay,
  useReadable,
  useRepository,
  useRescheduleSheet,
  useStatusActions,
  useTodayAppointments,
  withAlpha,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { ScrollView, View } from 'react-native';
import { Button, Text, TextInput } from 'react-native-paper';

const stats: [string, AppointmentStatus][] = [
  ['To confirm', 'pending'],
  ['Expected', 'confirmed'],
  ['Waiting', 'arrived'],
  ['Seen', 'completed'],
];

export function CheckInScreen() {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const todayAsync = useTodayAppointments();
  const board = useAppointmentView() === 'board';
  const [query, setQuery] = useState('');

  // Header stats need numbers before the list renders; empty is the honest
  // stand-in while loading, and the list below still reports real errors.
  const today = todayAsync.value ?? [];
  const q = query.toLowerCase();
  const filtered = today.filter((a) => query === '' || a.patient.name.toLowerCase().includes(q) || a.patient.phone.includes(query));
  const count = (s: AppointmentStatus) => today.filter((a) => a.status === s).length;

  /// A board card's front-desk actions (bill, move, cancel, no-show) — the
  /// same card the list shows. There is no page for one visit in this app.
  const showActions = (id: string) =>
    void overlay.showSheet(() => (
      <View style={{ paddingHorizontal: 16, paddingBottom: 16 }}>
        <LiveCheckInCard appointmentId={id} />
      </View>
    ));

  const header = (
    <View style={{ width: '100%', maxWidth: ContentWidth.wide + 32, alignSelf: 'center' }}>
      <View style={{ flexDirection: 'row', gap: 8, paddingHorizontal: 16, paddingVertical: 8 }}>
        {stats.map(([label, status]) => {
          const color = readable(statusMeta[status].color);
          return (
            <View
              key={status}
              style={{
                flex: 1,
                alignItems: 'center',
                paddingVertical: 10,
                paddingHorizontal: 8,
                borderRadius: 12,
                backgroundColor: withAlpha(color, 25 / 255),
                borderWidth: 1,
                borderColor: withAlpha(color, 60 / 255),
              }}
            >
              <Text style={{ fontWeight: '700', fontSize: 20, color }}>{count(status)}</Text>
              <Text style={{ fontSize: 11, color, textAlign: 'center' }}>{label}</Text>
            </View>
          );
        })}
      </View>
      <View style={{ paddingHorizontal: 16, paddingTop: 4, paddingBottom: 12 }}>
        <TextField
          value={query}
          onChangeText={setQuery}
          placeholder="Search patient by name or phone…"
          icon="search"
          right={query === '' ? undefined : <TextInput.Icon icon="clear" accessibilityLabel="Clear" onPress={() => setQuery('')} />}
        />
      </View>
    </View>
  );

  let body;
  // "No appointments today" is only true once the data has actually
  // arrived — while loading or after a failure it would be a lie.
  if (!todayAsync.hasValue) {
    body = (
      <AsyncView value={todayAsync} onRetry={() => void refreshAppointments(qc)}>
        {() => null}
      </AsyncView>
    );
  } else if (filtered.length === 0) {
    body = <EmptyState icon="event-available" title={query !== '' ? `No results for "${query}"` : 'No appointments today'} />;
  } else if (board) {
    body = <AppointmentBoard appointments={filtered} onOpen={(a) => showActions(a.id)} />;
  }

  return (
    <Page
      scroll={false}
      title={
        <View>
          <Text variant="bodyMedium" style={{ color: colors.onSurfaceVariant }}>
            {format(new Date(), 'EEEE, MMMM d')}
          </Text>
          <ClinicTitle page="Check-in" />
        </View>
      }
      actions={
        <>
          <AppointmentViewToggle />
          <NotificationsButton />
          <AccountMenuButton />
        </>
      }
    >
      {body != null ? (
        <View style={{ flex: 1 }}>
          {header}
          <View style={{ flex: 1 }}>{body}</View>
        </View>
      ) : (
        // One day's visits: few enough to lay out at once, in two or three
        // columns on a tablet or desktop.
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 16 }}>
          {header}
          <View style={{ width: '100%', maxWidth: ContentWidth.wide, alignSelf: 'center', paddingHorizontal: 16 }}>
            <CardColumns>
              {filtered.map((a) => (
                <CheckInCard key={a.id} appointment={a} />
              ))}
            </CardColumns>
          </View>
        </ScrollView>
      )}
    </Page>
  );
}

/// Follows the visit as it changes, so the buttons stay current.
function LiveCheckInCard({ appointmentId }: { appointmentId: string }) {
  const a = useAppointmentById(appointmentId).value ?? null;
  if (a == null) return <View style={{ height: 120 }} />;
  return <CheckInCard appointment={a} />;
}

function CheckInCard({ appointment: a }: { appointment: Appointment }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const qc = useQueryClient();
  const nav = useClinicNav();
  const overlay = useOverlay();
  const repo = useRepository();
  const status = useStatusActions();
  const completeVisit = useCompleteVisitSheet();
  const reschedule = useRescheduleSheet();

  /// Marks the visit done with the services performed, then opens its bill
  /// to take payment.
  const markDone = async () => {
    const id = await completeVisit(a);
    if (id != null && id !== '') nav.push(`/billing/${id}`);
  };

  /// The visit's bill — started with its service as the first line if it
  /// has none yet.
  const openBill = async () => {
    try {
      const id = await repo.createInvoiceForAppointment(a.id);
      void invalidateBilling(qc);
      nav.push(`/billing/${id}`);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  const since =
    a.status === 'arrived' && a.arrivedAt != null
      ? `Waiting since ${format(a.arrivedAt, 'h:mm a')}`
      : a.status === 'in_consultation' && a.startedAt != null
        ? `With the doctor since ${format(a.startedAt, 'h:mm a')}`
        : null;

  const primary = (icon: IconName, label: string, onPress: () => void) => (
    <Button key={label} mode="contained" icon={icon} compact onPress={onPress} labelStyle={{ fontSize: 13 }}>
      {label}
    </Button>
  );
  const buttons = [
    a.status === 'pending' && primary('check', 'Confirm', () => void status.change(a, 'confirmed', 'Appointment confirmed')),
    a.status === 'confirmed' &&
      primary('how-to-reg', 'Check in', () => void status.change(a, 'arrived', `${a.patient.name} is in the waiting room`)),
    // Only once the time has come: the database refuses it earlier.
    a.status === 'confirmed' && a.dateTime.getTime() <= Date.now() && (
      <Button key="no-show" compact onPress={() => void status.change(a, 'no_show', 'Marked as a no-show')}>
        No-show
      </Button>
    ),
    (a.status === 'arrived' || a.status === 'in_consultation') && primary('task-alt', 'Mark done', () => void markDone()),
    a.status === 'completed' && primary('receipt-long', 'Bill', () => void openBill()),
    a.canReschedule && (
      <Button key="move" compact onPress={() => void reschedule(a, true)}>
        Move
      </Button>
    ),
    staffCanCancel(a.status) && (
      <Button
        key="cancel"
        mode="outlined"
        compact
        textColor={colors.error}
        style={{ borderColor: colors.error }}
        labelStyle={{ fontSize: 13 }}
        onPress={() => void status.confirmAndCancel(a, a.patient.name)}
      >
        Cancel
      </Button>
    ),
  ].filter(Boolean);

  return (
    <AppCard padding={16}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
        <Avatar label={a.patient.initials} size={44} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text numberOfLines={1} style={{ fontWeight: '600', fontSize: 15 }}>
            {a.patient.name}
          </Text>
          <Text style={{ color: colors.onSurfaceVariant, fontSize: 13 }}>{a.patient.phone}</Text>
        </View>
        <StatusBadge status={a.status} small />
      </View>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 8 }}>
        <Icon name="access-time" size={14} color={colors.primary} />
        <Text style={{ color: colors.primary, fontSize: 13 }}>{format(a.dateTime, 'h:mm a')}</Text>
        <View style={{ width: 8 }} />
        <Icon name="medical-services" size={14} color={colors.onSurfaceVariant} />
        <Text numberOfLines={1} style={{ flex: 1, color: colors.onSurfaceVariant, fontSize: 13 }}>
          {a.service}
        </Text>
      </View>
      {since != null && (
        <Text style={{ marginTop: 8, color: readable(statusMeta[a.status].color), fontSize: 13, fontWeight: '600' }}>{since}</Text>
      )}
      {buttons.length > 0 && (
        <Wrap align="center" style={{ marginTop: 12 }}>
          {buttons}
        </Wrap>
      )}
    </AppCard>
  );
}
