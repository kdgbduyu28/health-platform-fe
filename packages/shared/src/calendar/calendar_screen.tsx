import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { type ReactNode, useRef, useState } from 'react';
import { Pressable, ScrollView, View, useWindowDimensions } from 'react-native';
import { Button, Chip, FAB, IconButton, ProgressBar, SegmentedButtons, Text, Tooltip } from 'react-native-paper';

import { Breakpoints } from '../app/adaptive';
import type { Appointment } from '../models/appointment';
import { holdsTime, staffCanCancel } from '../models/appointment_status';
import type { Doctor } from '../models/doctor';
import { useCurrentDoctor, useDoctors, useMyPatient, useTimeOff } from '../queries/catalog';
import { useCalendarAppointments } from '../queries/misc';
import { useAppRole } from '../state/platform';
import { preferences } from '../state/preferences';
import { useAppTheme } from '../theme/clinic_theme';
import { ErrorView } from '../ui/async_view';
import { useDatePicker } from '../ui/fields';
import { Icon, type IconName } from '../ui/icon';
import { MenuButton } from '../ui/kit';
import { type Close, SheetScroll, useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { startOfDay } from '../util/dates';
import { StatusBadge, useStatusActions } from '../widgets/appointment_bits';
import { useRescheduleSheet } from '../widgets/reschedule_sheet';
import {
  type CalendarView,
  calendarRangeFor,
  calendarTitle,
  calendarViewFromName,
  calendarViewMeta,
  calendarViews,
  shiftCalendar,
  startOfWeek,
} from './calendar_math';
import { useQuickBookSheet } from './quick_book_sheet';
import { CalendarLegend, ScheduleCalendar } from './schedule_calendar';

/// Whose visits the calendar shows. RLS has already limited the rows; this
/// narrows them to what the app is for.
///
/// `doctor`: the signed-in doctor's own visits, shaded by their own hours.
/// `clinic`: everyone's at the clinic, with a doctor filter (front desk,
/// admin). `patient`: the signed-in patient's own visits.
export type CalendarScope = 'doctor' | 'clinic' | 'patient';

type VisitAction = 'confirm' | 'checkIn' | 'move' | 'patient' | 'cancel';

/// The visits as a month, a week or a day, like a wall calendar.
///
/// With [canBook], tapping empty time books it (for staff). A visit opens
/// with [onOpenAppointment], or — without one, as at the front desk, which
/// has no appointment page — in a sheet with the day's actions.
export function AppointmentCalendarScreen({
  scope,
  canBook = false,
  onOpenAppointment,
  onOpenPatient,
  onBookAsPatient,
  title,
}: {
  scope: CalendarScope;
  canBook?: boolean;
  onOpenAppointment?: (a: Appointment) => void;
  /// From the visit sheet, when [onOpenAppointment] is absent.
  onOpenPatient?: (patientId: string) => void;
  /// The patient app's "Book" button.
  onBookAsPatient?: () => void;
  title?: ReactNode;
}) {
  const app = useAppRole();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const status = useStatusActions();
  const reschedule = useRescheduleSheet();
  const quickBook = useQuickBookSheet();
  const { width } = useWindowDimensions();
  const [date, setDate] = useState(() => startOfDay(new Date()));
  // The view last picked on this device, so the front desk that works in
  // Day by doctor does not start from Week every morning.
  const [chosenView, setView] = useState<CalendarView | null>(() => calendarViewFromName(preferences.calendarView(app)));
  /// Clinic scope: one doctor's visits, or (null) everyone's.
  const [doctorId, setDoctorId] = useState<string | null>(null);
  const [showCancelled, setShowCancelled] = useState(false);
  /// The last page shown, kept on screen while the next one loads.
  const last = useRef<Appointment[]>([]);

  const view: CalendarView = chosenView ?? (scope === 'patient' ? 'month' : width >= Breakpoints.twoPane ? 'week' : 'day');
  const range = calendarRangeFor(view, date);
  const page = useCalendarAppointments(range);
  if (page.value) last.current = page.value;

  const allDoctors = useDoctors().value ?? [];
  const me = useCurrentDoctor().value ?? null;
  const mine = useMyPatient().value ?? null;
  const timeOff = useTimeOff().value ?? [];

  const go = (v: CalendarView, d: Date) => {
    setView(v);
    setDate(startOfDay(d));
  };
  /// Month / week / day picked: remembered. Opening a day from the week or
  /// month is a look, not a choice, so it is not.
  const pick = (v: CalendarView) => {
    preferences.setCalendarView(app, v);
    go(v, date);
  };

  const keep = (a: Appointment) => showCancelled || holdsTime(a.status);
  let inView: Doctor[];
  let shown: Appointment[];
  switch (scope) {
    case 'doctor':
      inView = me == null ? [] : [me];
      shown = last.current.filter((a) => a.doctor.id === me?.id && keep(a));
      break;
    case 'clinic':
      inView = doctorId == null ? allDoctors : allDoctors.filter((d) => d.id === doctorId);
      shown = last.current.filter((a) => (doctorId == null || a.doctor.id === doctorId) && keep(a));
      break;
    case 'patient':
      inView = [];
      shown = last.current.filter((a) => a.patient.id === mine?.id && keep(a));
      break;
  }

  const open = async (a: Appointment) => {
    if (onOpenAppointment) {
      onOpenAppointment(a);
      return;
    }
    const action = await overlay.showSheet<VisitAction>((close) => <VisitSheet appointment={a} canOpenPatient={onOpenPatient != null} close={close} />);
    switch (action) {
      case 'confirm':
        await status.change(a, 'confirmed', 'Confirmed');
        break;
      case 'checkIn':
        await status.change(a, 'arrived', `${a.patient.name} checked in`);
        break;
      case 'move':
        await reschedule(a, true);
        break;
      case 'patient':
        onOpenPatient?.(a.patient.id);
        break;
      case 'cancel':
        await status.confirmAndCancel(a, a.patient.name);
        break;
    }
  };

  const create = (start: Date, d: Doctor | null) => {
    if (start.getTime() <= Date.now()) {
      overlay.snack('That time has passed. Pick a time still to come.');
      return;
    }
    void quickBook(start, d ?? (inView.length === 1 ? inView[0] : null));
  };

  const add = () => {
    // The next quarter hour, on the page's day if it is still to come.
    const now = new Date();
    const future = date.getTime() > now.getTime();
    const base = future ? new Date(date.getFullYear(), date.getMonth(), date.getDate(), 9) : now;
    const next = new Date(base.getFullYear(), base.getMonth(), base.getDate(), base.getHours(), (Math.floor(base.getMinutes() / 15) + (future ? 0 : 1)) * 15);
    void quickBook(next, inView.length === 1 ? inView[0] : null);
  };

  const compactFab = width < Breakpoints.medium;
  const fab = canBook ? (
    <FAB
      icon="add"
      label={compactFab ? undefined : 'New appointment'}
      accessibilityLabel="New appointment"
      onPress={add}
      style={{ position: 'absolute', right: 16, bottom: 56 }}
    />
  ) : onBookAsPatient ? (
    <FAB icon="add" label="Book" onPress={onBookAsPatient} style={{ position: 'absolute', right: 16, bottom: 56 }} />
  ) : undefined;

  return (
    <Page
      title={title ?? 'Calendar'}
      scroll={false}
      actions={
        <Tooltip title={showCancelled ? 'Hide cancelled' : 'Show cancelled'}>
          <IconButton
            icon="event-busy"
            selected={showCancelled}
            mode={showCancelled ? 'contained-tonal' : undefined}
            accessibilityLabel={showCancelled ? 'Hide cancelled' : 'Show cancelled'}
            onPress={() => setShowCancelled((s) => !s)}
          />
        </Tooltip>
      }
      belowAppBar={
        <View>
          <Toolbar view={view} date={date} compact={width < Breakpoints.medium} onView={pick} onDate={(d) => go(view, d)} />
          {scope === 'clinic' && <DoctorFilter doctors={allDoctors} selected={doctorId} onSelect={setDoctorId} />}
        </View>
      }
      fab={fab}
    >
      <View style={{ height: 2 }}>{page.isLoading && <ProgressBar indeterminate style={{ height: 2 }} />}</View>
      <View style={{ flex: 1 }}>
        {page.hasError && !page.hasValue ? (
          <ErrorView error={page.error} onRetry={() => void qc.invalidateQueries({ queryKey: ['calendarRange'] })} />
        ) : (
          <ScheduleCalendar
            view={view}
            date={date}
            appointments={shown}
            doctors={inView}
            timeOff={timeOff}
            splitByDoctor={scope === 'clinic' && doctorId == null}
            blockTitle={scope === 'patient' ? (a) => a.service : undefined}
            onOpen={(a) => void open(a)}
            onCreate={canBook ? create : undefined}
            onDayTap={(day) => go('day', day)}
          />
        )}
      </View>
      <View style={{ paddingHorizontal: 12, paddingTop: 6, paddingBottom: 8 }}>
        <CalendarLegend />
      </View>
    </Page>
  );
}

function Toolbar({
  view,
  date,
  compact,
  onView,
  onDate,
}: {
  view: CalendarView;
  date: Date;
  compact: boolean;
  onView: (v: CalendarView) => void;
  onDate: (d: Date) => void;
}) {
  const pickDate = useDatePicker();
  const today = startOfDay(new Date());
  const label = calendarViewMeta[view].label.toLowerCase();
  const heading = compact
    ? view === 'day'
      ? format(date, 'EEE d MMM')
      : format(view === 'week' ? startOfWeek(date) : date, 'MMM y')
    : calendarTitle(view, date);
  return (
    <View style={{ height: 56, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, gap: 2 }}>
      {compact ? (
        <IconButton icon="today" accessibilityLabel="Today" onPress={() => onDate(today)} />
      ) : (
        <Button mode="outlined" compact onPress={() => onDate(today)}>
          Today
        </Button>
      )}
      <IconButton icon="chevron-left" accessibilityLabel={`Previous ${label}`} onPress={() => onDate(shiftCalendar(view, date, -1))} />
      <IconButton icon="chevron-right" accessibilityLabel={`Next ${label}`} onPress={() => onDate(shiftCalendar(view, date, 1))} />
      <Pressable
        style={{ flex: 1, paddingHorizontal: 4, paddingVertical: 8, borderRadius: 8 }}
        onPress={async () => {
          const picked = await pickDate({ initial: date, first: new Date(today.getFullYear() - 5, 0, 1), last: new Date(today.getFullYear() + 2, 11, 31) });
          if (picked) onDate(picked);
        }}
      >
        <Text variant="titleMedium" numberOfLines={1} style={{ fontWeight: '600' }}>
          {heading}
        </Text>
      </Pressable>
      {compact ? (
        <MenuButton
          label="View"
          anchor={(open) => (
            <Button compact icon="arrow-drop-down" contentStyle={{ flexDirection: 'row-reverse' }} onPress={open}>
              {calendarViewMeta[view].label}
            </Button>
          )}
          items={calendarViews.map((v) => ({ label: calendarViewMeta[v].label, icon: calendarViewMeta[v].icon as IconName, onPress: () => onView(v) }))}
        />
      ) : (
        <SegmentedButtons
          density="small"
          style={{ width: 260 }}
          value={view}
          onValueChange={(v) => onView(v as CalendarView)}
          buttons={calendarViews.map((v) => ({ value: v, label: calendarViewMeta[v].label }))}
        />
      )}
    </View>
  );
}

function DoctorFilter({ doctors, selected, onSelect }: { doctors: Doctor[]; selected: string | null; onSelect: (id: string | null) => void }) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 12, paddingVertical: 6, gap: 8 }}>
      <Chip mode="outlined" selected={selected == null} showSelectedCheck onPress={() => onSelect(null)}>
        All doctors
      </Chip>
      {doctors.map((d) => (
        <Chip key={d.id} mode="outlined" selected={selected === d.id} showSelectedCheck onPress={() => onSelect(selected === d.id ? null : d.id)}>
          {`Dr. ${d.name}`}
        </Chip>
      ))}
    </ScrollView>
  );
}

/// A visit tapped on the front desk's calendar: who, when, and the steps the
/// desk takes with it. Closes with the step chosen; the screen takes it.
function VisitSheet({ appointment: a, canOpenPatient, close }: { appointment: Appointment; canOpenPatient: boolean; close: Close<VisitAction> }) {
  const { colors } = useAppTheme();
  const line = (icon: IconName, text: string) => (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 6 }}>
      <Icon name={icon} size={18} color={colors.onSurfaceVariant} />
      <Text style={{ flex: 1 }}>{text}</Text>
    </View>
  );
  return (
    <SheetScroll padding={20}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
        <Text variant="titleLarge" style={{ flex: 1, fontWeight: '700' }}>
          {a.patient.name}
        </Text>
        <StatusBadge status={a.status} />
      </View>
      <View style={{ height: 8 }} />
      {line('schedule', `${format(a.dateTime, 'EEE, MMM d · h:mm')} – ${format(a.endsAt, 'h:mm a')}`)}
      {line('medical-services', a.service)}
      {line('person-outline', `Dr. ${a.doctor.name}`)}
      {a.patient.phone !== '' && line('phone', a.patient.phone)}
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 16 }}>
        {a.status === 'pending' && (
          <Button mode="contained" icon="check" onPress={() => close('confirm')}>
            Confirm
          </Button>
        )}
        {a.status === 'confirmed' && a.isToday && (
          <Button mode="contained" icon="how-to-reg" onPress={() => close('checkIn')}>
            Check in
          </Button>
        )}
        {a.canReschedule && (
          <Button mode="outlined" icon="edit-calendar" onPress={() => close('move')}>
            Move
          </Button>
        )}
        {canOpenPatient && (
          <Button mode="outlined" icon="folder-shared" onPress={() => close('patient')}>
            Patient
          </Button>
        )}
        {staffCanCancel(a.status) && (
          <Button icon="cancel" textColor={colors.error} onPress={() => close('cancel')}>
            Cancel
          </Button>
        )}
      </View>
    </SheetScroll>
  );
}
