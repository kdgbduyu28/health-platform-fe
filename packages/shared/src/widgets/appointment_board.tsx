import { format } from 'date-fns';
import { createElement, type ReactNode, useState } from 'react';
import { Platform, Pressable, ScrollView, View } from 'react-native';
import { Button, IconButton, Text, Tooltip } from 'react-native-paper';

import { ContentWidth, useLayoutWidth } from '../app/adaptive';
import { useClinicNav } from '../app/navigation';
import type { AppRole } from '../models/app_role';
import type { Appointment } from '../models/appointment';
import { type AppointmentStatus, statusMeta } from '../models/appointment_status';
import { useCanSeeClinicalNotes } from '../queries/clinical';
import { preferences, usePreference } from '../state/preferences';
import { useAppRole } from '../state/platform';
import { useAppTheme, useReadable, withAlpha } from '../theme/clinic_theme';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, Tabs } from '../ui/kit';
import { StatusBadge, useStatusActions } from './appointment_bits';
import { useCompleteVisitSheet } from './complete_visit_sheet';
import { type BoardColumn, type BoardStep, boardColumnOf, boardColumns, boardNextStep, columnMeta } from '../models/board';

/// Switches a screen between the list and AppointmentBoard. Remembered per
/// app on this device.
export function AppointmentViewToggle() {
  const app = useAppRole();
  const view = usePreference((p) => p.appointmentView(app));
  const board = view === 'board';
  return (
    <Tooltip title={board ? 'Show as a list' : 'Show as a board'}>
      <IconButton
        icon={board ? 'view-agenda' : 'view-kanban'}
        accessibilityLabel={board ? 'Show as a list' : 'Show as a board'}
        onPress={() => preferences.setAppointmentView(app, board ? 'list' : 'board')}
      />
    </Tooltip>
  );
}

export function useAppointmentView(): 'list' | 'board' {
  const app = useAppRole();
  return usePreference((p) => p.appointmentView(app));
}

/// Below this, four columns get too narrow to read; the board becomes tabs.
const minWideWidth = 880;

/// A day's visits in columns by where each one stands: Upcoming (booked, to
/// confirm), Planned (confirmed), In progress (in the waiting room or with
/// the doctor) and Completed.
///
/// On a wide screen the columns sit side by side and a card can be dragged
/// one column to the right — only where its next step leads, so the board
/// never offers a move the database would refuse. On a narrow screen the
/// columns become tabs, and each card's button does the same.
///
/// Visits are shown as given: the caller picks the day and whose visits.
export function AppointmentBoard({
  appointments,
  showDoctor = true,
  onOpen,
}: {
  appointments: Appointment[];
  /// Whether cards name the doctor. Off in the doctor app: they are all
  /// theirs.
  showDoctor?: boolean;
  /// What tapping a card does. By default it opens the visit's page.
  onOpen?: (a: Appointment) => void;
}) {
  const app = useAppRole();
  const clinician = useCanSeeClinicalNotes().value ?? app === 'doctor';
  const nav = useClinicNav();
  const status = useStatusActions();
  const completeVisit = useCompleteVisitSheet();
  const [width, onLayout] = useLayoutWidth();
  const [dragging, setDragging] = useState<Appointment | null>(null);
  const stepOf = (a: Appointment) => boardNextStep(a, app, clinician);

  const lanes = new Map<BoardColumn, Appointment[]>(boardColumns.map((c) => [c, []]));
  const closed: Appointment[] = [];
  for (const a of appointments) {
    const column = boardColumnOf(a.status);
    (column == null ? closed : lanes.get(column)!).push(a);
  }
  const byTime = (a: Appointment, b: Appointment) => a.dateTime.getTime() - b.dateTime.getTime();
  for (const list of [...lanes.values(), closed]) list.sort(byTime);
  // With the doctor first, then the waiting room in order of arrival: the
  // top card is the one to deal with next.
  lanes.get('in_progress')!.sort((a, b) => {
    const withDoctor = (a.status === 'in_consultation' ? 0 : 1) - (b.status === 'in_consultation' ? 0 : 1);
    if (withDoctor !== 0) return withDoctor;
    return (a.arrivedAt ?? a.dateTime).getTime() - (b.arrivedAt ?? b.dateTime).getTime();
  });

  const open = (a: Appointment) => (onOpen ? onOpen(a) : nav.push(`/appointments/${a.id}`));
  const advance = async (a: Appointment) => {
    const step = stepOf(a);
    if (step == null) return;
    if (step.to === 'completed') {
      await completeVisit(a);
      return;
    }
    await status.change(a, step.to, step.done);
  };

  const lane = (column: BoardColumn, draggable: boolean) => (
    <Lane
      column={column}
      appointments={lanes.get(column)!}
      closed={column === 'completed' ? closed : []}
      showDoctor={showDoctor}
      draggable={draggable}
      stepOf={stepOf}
      onOpen={open}
      onAdvance={advance}
      dragging={dragging}
      setDragging={setDragging}
    />
  );

  return (
    <View style={{ flex: 1 }} onLayout={onLayout}>
      {width < minWideWidth ? (
        <BoardTabs
          counts={new Map(boardColumns.map((c) => [c, lanes.get(c)!.length]))}
          // Open on what needs attention now.
          initial={lanes.get('in_progress')!.length > 0 ? 'in_progress' : 'planned'}
          lane={(c) => lane(c, false)}
        />
      ) : (
        <View style={{ flex: 1, flexDirection: 'row', gap: 12, paddingHorizontal: 16, paddingTop: 4, paddingBottom: 16, width: '100%', maxWidth: ContentWidth.wide + 32, alignSelf: 'center' }}>
          {boardColumns.map((c) => (
            <View key={c} style={{ flex: 1, minWidth: 0 }}>
              {lane(c, true)}
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

function BoardTabs({ counts, initial, lane }: { counts: Map<BoardColumn, number>; initial: BoardColumn; lane: (c: BoardColumn) => ReactNode }) {
  const [tab, setTab] = useState<BoardColumn>(initial);
  return (
    <View style={{ flex: 1 }}>
      <Tabs scrollable value={tab} onChange={setTab} tabs={boardColumns.map((c) => ({ value: c, label: `${columnMeta[c].label} (${counts.get(c)})` }))} />
      <View style={{ flex: 1, paddingHorizontal: 16, paddingTop: 12, paddingBottom: 16 }}>{lane(tab)}</View>
    </View>
  );
}

/// One column: its heading and count, its cards, and — for a card being
/// dragged whose next step lands here — a highlight to drop it on.
function Lane({
  column,
  appointments,
  closed,
  showDoctor,
  draggable,
  stepOf,
  onOpen,
  onAdvance,
  dragging,
  setDragging,
}: {
  column: BoardColumn;
  appointments: Appointment[];
  /// Cancelled visits and no-shows, folded away at the bottom.
  closed: Appointment[];
  showDoctor: boolean;
  draggable: boolean;
  stepOf: (a: Appointment) => BoardStep | null;
  onOpen: (a: Appointment) => void;
  onAdvance: (a: Appointment) => Promise<void>;
  dragging: Appointment | null;
  setDragging: (a: Appointment | null) => void;
}) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const [showClosed, setShowClosed] = useState(false);
  const [hovering, setHovering] = useState(false);
  const tone = readable(statusMeta[columnMeta[column].tone].color);
  const wide = draggable;
  // Drag and drop is the browser's; on a phone each card's button moves it on.
  const dnd = draggable && Platform.OS === 'web';

  const lands = (a: Appointment | null) => {
    if (a == null) return false;
    const step = stepOf(a);
    return step != null && boardColumnOf(step.to) === column && boardColumnOf(a.status) !== column;
  };

  const card = (a: Appointment) => {
    const step = stepOf(a);
    const body = <BoardCard appointment={a} showDoctor={showDoctor} step={step} onOpen={() => onOpen(a)} onAdvance={() => void onAdvance(a)} />;
    // Only a card whose next step leaves this column can be dragged.
    if (!dnd || step == null || boardColumnOf(step.to) === column) return body;
    return createElement(
      'div',
      {
        draggable: true,
        onDragStart: (e: DragEvent) => {
          e.dataTransfer?.setData('text/plain', a.id);
          setDragging(a);
        },
        onDragEnd: () => setDragging(null),
        style: { cursor: 'grab', opacity: dragging?.id === a.id ? 0.35 : 1 },
      },
      body,
    );
  };

  const content = (
    <View style={{ flex: 1 }}>
      {wide && (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 12, paddingTop: 12, paddingBottom: 8 }}>
          <Icon name={statusMeta[columnMeta[column].tone].icon} size={18} color={tone} />
          <Text variant="titleSmall" style={{ flex: 1, fontWeight: '700' }}>
            {columnMeta[column].label}
          </Text>
          <View style={{ paddingHorizontal: 8, paddingVertical: 2, borderRadius: 10, backgroundColor: withAlpha(tone, 30 / 255) }}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: tone }}>{appointments.length}</Text>
          </View>
        </View>
      )}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: wide ? 8 : 0, paddingBottom: 8 }}>
        {appointments.length === 0 && closed.length === 0 && (
          <Text style={{ paddingVertical: 24, textAlign: 'center', color: colors.onSurfaceVariant }}>Nothing here</Text>
        )}
        {appointments.map((a) => (
          <View key={a.id} style={{ marginBottom: 8 }}>
            {card(a)}
          </View>
        ))}
        {closed.length > 0 && (
          <View>
            <Pressable onPress={() => setShowClosed((s) => !s)} style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 10 }}>
              <Text style={{ flex: 1, fontSize: 13, color: colors.onSurfaceVariant }}>Cancelled and no-shows ({closed.length})</Text>
              <Icon name={showClosed ? 'expand-less' : 'expand-more'} color={colors.onSurfaceVariant} />
            </Pressable>
            {showClosed &&
              closed.map((a) => (
                <View key={a.id} style={{ marginBottom: 8, opacity: 0.7 }}>
                  {card(a)}
                </View>
              ))}
          </View>
        )}
      </ScrollView>
    </View>
  );

  if (!wide) return content;
  const accepting = hovering && lands(dragging);
  const frame = (
    <View
      style={{
        flex: 1,
        borderRadius: 16,
        borderWidth: accepting ? 2 : 1,
        borderColor: accepting ? tone : colors.outlineVariant,
        backgroundColor: accepting ? withAlpha(tone, 28 / 255) : colors.surfaceContainerLow,
      }}
    >
      {content}
    </View>
  );
  if (!dnd) return frame;
  return createElement(
    'div',
    {
      style: { display: 'flex', flex: 1, height: '100%' },
      onDragOver: (e: DragEvent) => {
        if (lands(dragging)) {
          e.preventDefault();
          if (!hovering) setHovering(true);
        }
      },
      onDragLeave: () => setHovering(false),
      onDrop: (e: DragEvent) => {
        e.preventDefault();
        setHovering(false);
        const a = dragging;
        setDragging(null);
        if (lands(a)) void onAdvance(a!);
      },
    },
    frame,
  );
}

function BoardCard({
  appointment: a,
  showDoctor,
  step,
  onOpen,
  onAdvance,
}: {
  appointment: Appointment;
  showDoctor: boolean;
  step: BoardStep | null;
  onOpen: () => void;
  onAdvance: () => void;
}) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const since =
    a.status === 'arrived' && a.arrivedAt != null
      ? `Since ${format(a.arrivedAt, 'h:mm a')}`
      : a.status === 'in_consultation' && a.startedAt != null
        ? `Since ${format(a.startedAt, 'h:mm a')}`
        : null;
  // Within a column the status is mostly the column itself; the badge is for
  // where it is not — waiting vs. with the doctor, or cancelled.
  const showBadge = a.status !== 'pending' && a.status !== 'confirmed' && a.status !== 'completed';
  return (
    <AppCard onPress={onOpen} padding={12}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
        <Icon name="access-time" size={14} color={colors.primary} />
        <Text style={{ flex: 1, fontSize: 13, fontWeight: '600', color: colors.primary }}>{format(a.dateTime, 'h:mm a')}</Text>
        {showBadge && <StatusBadge status={a.status} small />}
      </View>
      <Text variant="titleSmall" numberOfLines={1} style={{ marginTop: 6, fontWeight: '600' }}>
        {a.patient.name}
      </Text>
      <Text numberOfLines={1} style={{ fontSize: 13, color: colors.onSurfaceVariant }}>
        {a.service}
      </Text>
      {showDoctor && (
        <Text numberOfLines={1} style={{ fontSize: 12, color: colors.onSurfaceVariant }}>
          Dr. {a.doctor.name}
        </Text>
      )}
      {since != null && <Text style={{ marginTop: 2, fontSize: 12, color: readable(statusMeta[a.status].color) }}>{since}</Text>}
      {step != null && (
        <Button mode="contained-tonal" icon={step.icon} compact onPress={onAdvance} style={{ marginTop: 8, alignSelf: 'flex-start' }} labelStyle={{ fontSize: 13 }}>
          {step.label}
        </Button>
      )}
    </AppCard>
  );
}

