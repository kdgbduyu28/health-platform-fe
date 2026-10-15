import { format } from 'date-fns';
import { type ReactNode, useEffect } from 'react';
import { FlatList, View } from 'react-native';
import { ActivityIndicator, Button, Text } from 'react-native-paper';

import { ContentWidth } from '../app/adaptive';
import type { Appointment } from '../models/appointment';
import { type AppointmentStatus, statusMeta } from '../models/appointment_status';
import type { Doctor } from '../models/doctor';
import { useAppointmentActions, usePastAppointments } from '../queries/appointments';
import { useAppTheme, useReadable, withAlpha } from '../theme/clinic_theme';
import { ErrorView, describeError } from '../ui/async_view';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, EmptyState, GradientBox } from '../ui/kit';
import { useOverlay } from '../ui/overlay';

export const visitTimeFormat = 'EEE, MMM d · h:mm a';

export function StatusBadge({ status, small = false }: { status: AppointmentStatus; small?: boolean }) {
  const readable = useReadable();
  const meta = statusMeta[status];
  const color = readable(meta.color);
  return (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        alignSelf: 'flex-start',
        gap: 4,
        paddingHorizontal: small ? 8 : 12,
        paddingVertical: small ? 3 : 5,
        borderRadius: 20,
        backgroundColor: withAlpha(color, 30 / 255),
        borderWidth: 1,
        borderColor: withAlpha(color, 80 / 255),
      }}
    >
      <Icon name={meta.icon} size={small ? 12 : 14} color={color} />
      <Text style={{ color, fontSize: small ? 11 : 12, fontWeight: '600' }}>{meta.label}</Text>
    </View>
  );
}

/// Moving a visit along, and cancelling one.
export function useStatusActions() {
  const actions = useAppointmentActions();
  const overlay = useOverlay();

  /// Moves [appointment] to [to] and says how it went.
  ///
  /// The database decides which moves are allowed (and who may make them),
  /// so a refusal is expected, not exceptional: its message is shown as-is —
  /// it is written for the person at the screen ("A completed visit cannot
  /// become confirmed."). Returns whether the change was saved.
  const change = async (appointment: Appointment, to: AppointmentStatus, done?: string): Promise<boolean> => {
    try {
      await actions.updateStatus(appointment.id, to);
      if (done != null) overlay.snack(done);
      return true;
    } catch (e) {
      overlay.snack(describeError(e));
      return false;
    }
  };

  return {
    change,
    /// Asks before cancelling — it cannot be undone from the app — then
    /// cancels.
    confirmAndCancel: async (appointment: Appointment, who?: string): Promise<boolean> => {
      const ok = await overlay.confirm({
        title: 'Cancel appointment?',
        message:
          who == null
            ? 'This frees the time for someone else.'
            : `Cancel ${who}'s appointment? This frees the time for someone else.`,
        cancelLabel: 'Keep',
        confirmLabel: 'Cancel it',
        destructive: true,
      });
      if (!ok) return false;
      return change(appointment, 'cancelled', 'Appointment cancelled');
    },
  };
}

export function DoctorAvatar({ doctor, radius = 24 }: { doctor: Doctor; radius?: number }) {
  const { colors } = useAppTheme();
  return (
    <View
      style={{
        width: radius * 2,
        height: radius * 2,
        borderRadius: radius,
        backgroundColor: colors.primaryContainer,
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Text style={{ color: colors.onPrimaryContainer, fontSize: radius * 0.6, fontWeight: '700' }}>{doctor.initials}</Text>
    </View>
  );
}

function IconRow({ icon, text, color }: { icon: IconName; text: string; color: string }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
      <Icon name={icon} size={14} color={color} />
      <Text style={{ flex: 1, fontSize: 13, color }}>{text}</Text>
    </View>
  );
}

export function AppointmentCard({
  appointment,
  onPress,
  showPatient = false,
  showDoctor = true,
}: {
  appointment: Appointment;
  onPress: () => void;
  showPatient?: boolean;
  showDoctor?: boolean;
}) {
  const { colors } = useAppTheme();
  if (showPatient) return <StaffAppointmentCard appointment={appointment} onPress={onPress} showDoctor={showDoctor} />;
  return (
    <AppCard onPress={onPress} padding={16}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
        <Text variant="titleMedium" style={{ flex: 1, fontWeight: '600' }}>
          {appointment.service}
        </Text>
        <StatusBadge status={appointment.status} small />
      </View>
      <View style={{ height: 8 }} />
      <IconRow icon="access-time" text={format(appointment.dateTime, visitTimeFormat)} color={colors.primary} />
      {showDoctor && (
        <View style={{ marginTop: 4 }}>
          <IconRow icon="person-outline" text={`Dr. ${appointment.doctor.name}`} color={colors.onSurfaceVariant} />
        </View>
      )}
    </AppCard>
  );
}

/// For the front desk and admins: who first, then what and with whom, the
/// time in a block down the side — denser, so a tablet shows the morning at
/// a glance. No date: the staff lists this serves are one day's.
function StaffAppointmentCard({ appointment: a, onPress, showDoctor }: { appointment: Appointment; onPress: () => void; showDoctor: boolean }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const faded = a.status === 'cancelled' || a.status === 'no_show';
  return (
    <AppCard onPress={onPress}>
      <View style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 12, paddingLeft: 12, paddingRight: 14, gap: 12 }}>
        <View
          style={{
            width: 64,
            paddingVertical: 8,
            borderRadius: 12,
            alignItems: 'center',
            backgroundColor: withAlpha(readable(statusMeta[a.status].color), 24 / 255),
          }}
        >
          <Text style={{ fontWeight: '700', fontSize: 16 }}>{format(a.dateTime, 'h:mm')}</Text>
          <Text style={{ fontSize: 11, color: colors.onSurfaceVariant }}>{format(a.dateTime, 'a')}</Text>
        </View>
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text
            variant="titleMedium"
            numberOfLines={1}
            style={{
              fontWeight: '600',
              textDecorationLine: faded ? 'line-through' : 'none',
              color: faded ? colors.onSurfaceVariant : undefined,
            }}
          >
            {a.patient.name}
          </Text>
          <Text numberOfLines={1} style={{ marginTop: 2, fontSize: 13, color: colors.onSurfaceVariant }}>
            {[a.service, ...(showDoctor ? [`Dr. ${a.doctor.name}`] : [])].join(' · ')}
          </Text>
        </View>
        <StatusBadge status={a.status} small />
      </View>
    </AppCard>
  );
}

/// The top of a staff visit page: status, service, when, and who.
///
/// The status sits on a pill of the page's own surface, which its colours
/// are chosen to read on, rather than on the clinic-colour gradient. [who]
/// (the patient and doctor) is shown on staff pages, where "who is this" is
/// the first question; a patient's own page leaves it out.
export function VisitHeader({ appointment: a, who }: { appointment: Appointment; who?: string | null }) {
  const { colors } = useAppTheme();
  const on = colors.onPrimary;
  return (
    <GradientBox style={{ padding: 20 }}>
      <View style={{ alignSelf: 'flex-start', backgroundColor: colors.surface, borderRadius: 20 }}>
        <StatusBadge status={a.status} />
      </View>
      <Text variant="headlineSmall" style={{ marginTop: 12, color: on, fontWeight: '700' }}>
        {a.service}
      </Text>
      {who != null && (
        <Text variant="titleSmall" style={{ marginTop: 2, color: on, fontWeight: '600' }}>
          {who}
        </Text>
      )}
      <Text style={{ marginTop: 4, color: withAlpha(on, 210 / 255), fontSize: 13 }}>
        {[format(a.dateTime, visitTimeFormat), `${a.durationMinutes} min`].join('  ·  ')}
      </Text>
      {a.rescheduledFrom != null && (
        <Text style={{ color: withAlpha(on, 180 / 255), fontSize: 12 }}>Moved from {format(a.rescheduledFrom, visitTimeFormat)}</Text>
      )}
    </GradientBox>
  );
}

/// The last row of a paged list: fetches the next page as soon as it scrolls
/// into view, and offers a retry if that fails.
export function LoadMoreFooter({ loading, error, onLoadMore }: { loading: boolean; error: unknown; onLoadMore: () => void }) {
  const { colors } = useAppTheme();
  // Shown means scrolled to: ask for the next page.
  useEffect(() => {
    if (error == null) onLoadMore();
    // Once per appearance, like the widget it replaces.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  if (error != null && !loading) {
    return (
      <View style={{ alignItems: 'center', paddingVertical: 8 }}>
        <Text style={{ color: colors.error, fontSize: 13, textAlign: 'center' }}>{describeError(error)}</Text>
        <Button onPress={onLoadMore}>Try again</Button>
      </View>
    );
  }
  return (
    <View style={{ alignItems: 'center', paddingVertical: 16 }}>
      <ActivityIndicator size={24} />
    </View>
  );
}

/// A "Past" tab: the recent visits already loaded, then older ones fetched a
/// page at a time as the list scrolls down.
///
/// [recent] are visits inside the loaded window, newest first; the older
/// pages start where the window ends, so the two never overlap.
export function PastAppointmentsList({
  recent,
  query,
  renderItem,
  emptyMessage,
  emptySubtitle,
}: {
  recent: Appointment[];
  query: { doctorId?: string | null; patientId?: string | null };
  renderItem: (appointment: Appointment) => ReactNode;
  emptyMessage: string;
  emptySubtitle?: string;
}) {
  const older = usePastAppointments(query);
  const items = [...recent, ...older.items];

  // The first older page is still on its way, or failed.
  const pending = older.hasValue ? null : older.error != null ? (
    <ErrorView error={older.error} onRetry={older.retry} />
  ) : (
    <View style={{ padding: 16, alignItems: 'center' }}>
      <ActivityIndicator />
    </View>
  );

  if (items.length === 0 && pending == null) {
    return <EmptyState icon="history" title={emptyMessage} message={emptySubtitle} />;
  }

  const footer =
    pending ??
    (older.hasMore || older.loadMoreError != null ? (
      <LoadMoreFooter loading={older.loadingMore} error={older.loadMoreError} onLoadMore={older.loadMore} />
    ) : null);

  return (
    <FlatList
      data={items}
      keyExtractor={(a) => a.id}
      contentContainerStyle={{ padding: 16, width: '100%', maxWidth: ContentWidth.list, alignSelf: 'center' }}
      ItemSeparatorComponent={() => <View style={{ height: 8 }} />}
      renderItem={({ item }) => <>{renderItem(item)}</>}
      ListFooterComponent={footer == null ? null : <View style={{ marginTop: 8 }}>{footer}</View>}
      onEndReached={() => older.hasMore && older.loadMoreError == null && older.loadMore()}
      onEndReachedThreshold={0.5}
    />
  );
}
