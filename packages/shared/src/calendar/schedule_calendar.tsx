import { format } from 'date-fns';
import { createElement, useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { Text, Tooltip } from 'react-native-paper';

import { useLayoutWidth } from '../app/adaptive';
import type { Appointment } from '../models/appointment';
import { appointmentStatuses, holdsTime, statusMeta } from '../models/appointment_status';
import type { Doctor } from '../models/doctor';
import type { TimeOff } from '../models/time_off';
import { lerpColor, useAppTheme, useReadable, withAlpha } from '../theme/clinic_theme';
import { Icon } from '../ui/icon';
import { Avatar } from '../ui/kit';
import { addDays, isSameDay, startOfDay } from '../util/dates';
import {
  type CalendarView,
  type MinuteSpan,
  calendarRangeFor,
  closedLabel,
  closureOn,
  layoutLanes,
  leaveLabel,
  leaveOn,
  mergeSpans,
  workingSpans,
} from './calendar_math';

type GridColumn = {
  day: Date;
  doctor?: Doctor | null;
  items: Appointment[];
  /// Bookable time; the rest is shaded. Null: nothing is shaded.
  open: MinuteSpan[] | null;
  /// Why the whole column is shaded (a closure, leave), if it is.
  blocked: string | null;
  heading?: string;
};

/// A page of visits laid out like a wall calendar: a month grid, or a week
/// or day of hours with each visit a block as long as it lasts.
///
/// It only draws; the screen around it owns the page ([view], [date]) and
/// decides what the callbacks do. Without [onCreate], empty time is not
/// tappable.
export function ScheduleCalendar({
  view,
  date,
  appointments,
  doctors = [],
  timeOff = [],
  splitByDoctor = false,
  blockTitle,
  onOpen,
  onCreate,
  onDayTap,
}: {
  view: CalendarView;
  date: Date;
  appointments: Appointment[];
  /// The doctors in view. Their hours leave the rest of the day shaded, and
  /// with [splitByDoctor] the day view gives each a column. Empty: no
  /// shading.
  doctors?: Doctor[];
  /// Closures shade whole days; a doctor's leave shades their column.
  timeOff?: TimeOff[];
  /// Day view only: one column per doctor, side by side.
  splitByDoctor?: boolean;
  /// What a block says first. Defaults to the patient's name.
  blockTitle?: (a: Appointment) => string;
  onOpen?: (a: Appointment) => void;
  /// Empty time tapped: its start, snapped to the quarter hour, and the
  /// doctor whose column it was, if the columns are doctors'.
  onCreate?: (start: Date, doctor: Doctor | null) => void;
  /// A day's number (month) or heading (week) tapped.
  onDayTap?: (day: Date) => void;
}) {
  const title = (a: Appointment) => blockTitle?.(a) ?? a.patient.name;
  if (view === 'month') {
    return <MonthGrid date={date} appointments={appointments} timeOff={timeOff} title={title} onOpen={onOpen} onDayTap={onDayTap} />;
  }
  const on = (day: Date) => appointments.filter((a) => isSameDay(a.dateTime, day));
  const openFor = (day: Date) => (doctors.length === 0 ? null : mergeSpans(doctors.flatMap((d) => workingSpans(d, day, timeOff))));
  let columns: GridColumn[];
  if (view === 'week') {
    const r = calendarRangeFor(view, date);
    columns = Array.from({ length: 7 }, (_, i) => {
      const day = addDays(r.from, i);
      const closure = closureOn(timeOff, day);
      return { day, items: on(day), open: openFor(day), blocked: closure ? closedLabel(closure) : null };
    });
  } else {
    const day = startOfDay(date);
    const closure = closureOn(timeOff, day);
    const items = on(day);
    if (!splitByDoctor || doctors.length < 2) {
      const one = doctors.length === 1 ? doctors[0] : null;
      const leave = one == null ? null : leaveOn(timeOff, one, day);
      columns = [{ day, doctor: one, items, open: openFor(day), blocked: closure ? closedLabel(closure) : leave ? leaveLabel(leave) : null }];
    } else {
      const ids = new Set(doctors.map((d) => d.id));
      const others = items.filter((a) => !ids.has(a.doctor.id));
      columns = doctors.map((d) => {
        const leave = leaveOn(timeOff, d, day);
        return {
          day,
          doctor: d,
          items: items.filter((a) => a.doctor.id === d.id),
          open: workingSpans(d, day, timeOff),
          blocked: closure ? closedLabel(closure) : leave ? leaveLabel(leave) : null,
        };
      });
      // Visits with a doctor no longer on the roster still show.
      if (others.length > 0) columns.push({ day, items: others, open: null, blocked: null, heading: 'Other' });
    }
  }
  return (
    <TimeGrid
      key={`${view}-${startOfDay(date).getTime()}-${splitByDoctor}`}
      columns={columns}
      title={title}
      onOpen={onOpen}
      onCreate={onCreate}
      onDayTap={view === 'week' ? onDayTap : undefined}
    />
  );
}

// ── Week and day: hours down the side ───────────────────────────────────────

const hourHeight = 60;
const minuteHeight = hourHeight / 60;
const gutter = 56;
const minColumnWidth = 112;
const snapMinutes = 15;

/// Keeps the red "now" line moving.
function useMinuteClock(): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 60_000);
    return () => clearInterval(t);
  }, []);
  return now;
}

function TimeGrid({
  columns,
  title,
  onOpen,
  onCreate,
  onDayTap,
}: {
  columns: GridColumn[];
  title: (a: Appointment) => string;
  onOpen?: (a: Appointment) => void;
  onCreate?: (start: Date, doctor: Doctor | null) => void;
  onDayTap?: (day: Date) => void;
}) {
  const { colors } = useAppTheme();
  const now = useMinuteClock();
  const [width, onLayout] = useLayoutWidth();
  const vertical = useRef<ScrollView>(null);

  /// Opens on the working day rather than at midnight: an hour before the
  /// earliest of the first open time, the first visit, and — today — now.
  useEffect(() => {
    let minute = 8 * 60;
    const starts: number[] = [];
    for (const c of columns) {
      if (c.open != null && c.open.length > 0) starts.push(c.open[0].start);
      for (const a of c.items) starts.push(a.dateTime.getHours() * 60 + a.dateTime.getMinutes());
    }
    if (starts.length > 0) minute = Math.min(...starts);
    const t = new Date();
    if (columns.some((c) => isSameDay(c.day, t))) minute = Math.min(minute, t.getHours() * 60 + t.getMinutes());
    const y = Math.max(0, (minute - 60) * minuteHeight);
    requestAnimationFrame(() => vertical.current?.scrollTo({ y, animated: false }));
    // Once, when the page opens.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const n = columns.length;
  const fits = width - gutter >= n * minColumnWidth || n === 1;
  const columnWidth = fits ? (width - gutter) / n : minColumnWidth;
  const gridWidth = gutter + columnWidth * n;

  const grid = (
    <View style={{ width: fits ? width : gridWidth, flex: 1 }}>
      <View style={{ height: 56, flexDirection: 'row' }}>
        <View style={{ width: gutter }} />
        {columns.map((c, i) => (
          <View key={i} style={{ width: columnWidth }}>
            {c.doctor != null || c.heading != null ? (
              <DoctorHeading doctor={c.doctor ?? null} heading={c.heading} count={c.items.length} />
            ) : (
              <Pressable
                disabled={onDayTap == null}
                onPress={() => onDayTap?.(c.day)}
                style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}
              >
                <Text variant="labelSmall" style={{ color: isSameDay(c.day, now) ? colors.primary : colors.onSurfaceVariant }}>
                  {format(c.day, 'EEE').toUpperCase()}
                </Text>
                <View style={{ height: 2 }} />
                <DayNumber day={c.day} today={isSameDay(c.day, now)} />
              </Pressable>
            )}
          </View>
        ))}
      </View>
      <View style={{ height: 1, backgroundColor: colors.outlineVariant }} />
      <ScrollView ref={vertical} style={{ flex: 1 }}>
        <View style={{ height: 24 * hourHeight, flexDirection: 'row' }}>
          <HourGutter />
          {columns.map((c) => (
            <View key={c.doctor?.id ?? c.heading ?? c.day.toISOString()} style={{ width: columnWidth }}>
              <DayColumn column={c} width={columnWidth} now={now} title={title} onOpen={onOpen} onCreate={onCreate} />
            </View>
          ))}
        </View>
      </ScrollView>
    </View>
  );
  return (
    <View style={{ flex: 1 }} onLayout={onLayout}>
      {fits ? (
        grid
      ) : (
        <ScrollView horizontal contentContainerStyle={{ flexGrow: 1 }}>
          {grid}
        </ScrollView>
      )}
    </View>
  );
}

function DoctorHeading({ doctor, heading, count }: { doctor: Doctor | null; heading?: string; count: number }) {
  const { colors } = useAppTheme();
  const name = doctor == null ? heading! : `Dr. ${doctor.name}`;
  return (
    <View style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 6 }}>
      <Avatar label={doctor?.initials ?? '?'} size={28} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <Text variant="labelLarge" numberOfLines={1}>
          {name}
        </Text>
        <Text variant="labelSmall" style={{ color: colors.onSurfaceVariant }}>
          {count} visit{count === 1 ? '' : 's'}
        </Text>
      </View>
    </View>
  );
}

function DayNumber({ day, today, muted = false }: { day: Date; today: boolean; muted?: boolean }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ width: 28, height: 28, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: today ? colors.primary : undefined }}>
      <Text style={{ fontWeight: '600', color: today ? colors.onPrimary : muted ? colors.outline : colors.onSurface }}>{day.getDate()}</Text>
    </View>
  );
}

function HourGutter() {
  const { colors } = useAppTheme();
  return (
    <View style={{ width: gutter }}>
      {Array.from({ length: 23 }, (_, i) => i + 1).map((h) => (
        <Text key={h} variant="labelSmall" style={{ position: 'absolute', top: h * hourHeight - 7, right: 8, color: colors.onSurfaceVariant }}>
          {format(new Date(2000, 0, 1, h), 'h a')}
        </Text>
      ))}
    </View>
  );
}

/// One day's (or one doctor's) hours: shading, hour lines, the visits, the
/// "now" line, and — when booking is allowed — a hint of the quarter hour
/// under the pointer.
function DayColumn({
  column: c,
  width,
  now,
  title,
  onOpen,
  onCreate,
}: {
  column: GridColumn;
  width: number;
  now: Date;
  title: (a: Appointment) => string;
  onOpen?: (a: Appointment) => void;
  onCreate?: (start: Date, doctor: Doctor | null) => void;
}) {
  const { colors } = useAppTheme();
  /// The quarter hour under the mouse, for the "+ 10:15" hint.
  const [hover, setHover] = useState<number | null>(null);
  const canCreate = onCreate != null;
  const lanes = layoutLanes(c.items);
  const snap = (dy: number) => Math.min(24 * 60 - snapMinutes, Math.max(0, Math.floor(Math.floor(dy / minuteHeight) / snapMinutes) * snapMinutes));
  const at = (minute: number) => new Date(c.day.getFullYear(), c.day.getMonth(), c.day.getDate(), Math.floor(minute / 60), minute % 60);
  const yOf = (e: { clientY: number; currentTarget: { getBoundingClientRect(): DOMRect } }) => e.clientY - e.currentTarget.getBoundingClientRect().top;

  const today = isSameDay(c.day, now);
  const past = today ? now.getHours() * 60 + now.getMinutes() : c.day.getTime() < startOfDay(now).getTime() ? 24 * 60 : 0;
  const open = c.blocked != null ? [] : c.open;
  const shade = withAlpha(colors.onSurface, 26 / 255);

  // Shaded stretches: everything outside the open spans.
  const shaded: MinuteSpan[] = [];
  if (open != null) {
    let from = 0;
    for (const s of [...open, { start: 24 * 60, end: 24 * 60 }]) {
      if (s.start > from) shaded.push({ start: from, end: s.start });
      from = Math.max(from, s.end);
    }
  }

  const background = createElement(
    'div',
    {
      style: { position: 'absolute', inset: 0, cursor: canCreate ? 'pointer' : 'default' },
      onMouseMove: canCreate ? (e: MouseEvent & { currentTarget: HTMLElement }) => setHover(snap(yOf(e))) : undefined,
      onMouseLeave: canCreate ? () => setHover(null) : undefined,
      onClick: canCreate ? (e: MouseEvent & { currentTarget: HTMLElement }) => onCreate!(at(snap(yOf(e))), c.doctor ?? null) : undefined,
    },
    // Decoration only; clicks go to the background itself.
    <View pointerEvents="none" style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}>
      {shaded.map((s) => (
        <View key={s.start} style={{ position: 'absolute', left: 0, right: 0, top: s.start * minuteHeight, height: (s.end - s.start) * minuteHeight, backgroundColor: shade }} />
      ))}
      {past > 0 && <View style={{ position: 'absolute', left: 0, right: 0, top: 0, height: past * minuteHeight, backgroundColor: withAlpha(colors.onSurface, 8 / 255) }} />}
      {Array.from({ length: 24 }, (_, h) => (
        <View key={h}>
          <View style={{ position: 'absolute', left: 0, right: 0, top: h * hourHeight, height: 1, backgroundColor: colors.outlineVariant }} />
          <View style={{ position: 'absolute', left: 0, right: 0, top: h * hourHeight + hourHeight / 2, height: 1, backgroundColor: withAlpha(colors.outlineVariant, 0.33) }} />
        </View>
      ))}
      <View style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 1, backgroundColor: colors.outlineVariant }} />
    </View>,
  );

  return (
    <View style={{ flex: 1 }}>
      {background}
      {c.blocked != null && (
        <View pointerEvents="none" style={{ position: 'absolute', top: 8, left: 4, right: 4 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 6, paddingVertical: 4, borderRadius: 6, backgroundColor: colors.surfaceContainerHighest }}>
            <Icon name="event-busy" size={14} color={colors.onSurfaceVariant} />
            <Text numberOfLines={2} style={{ flex: 1, fontSize: 11, color: colors.onSurfaceVariant }}>
              {c.blocked}
            </Text>
          </View>
        </View>
      )}
      {hover != null && canCreate && (
        <View
          pointerEvents="none"
          style={{
            position: 'absolute',
            top: hover * minuteHeight,
            left: 2,
            right: 2,
            height: 30 * minuteHeight,
            paddingHorizontal: 6,
            justifyContent: 'center',
            backgroundColor: withAlpha(colors.primary, 20 / 255),
            borderWidth: 1,
            borderColor: withAlpha(colors.primary, 120 / 255),
            borderRadius: 6,
          }}
        >
          <Text numberOfLines={1} style={{ fontSize: 11, color: colors.primary }}>
            + {format(at(hover), 'h:mm a')}
          </Text>
        </View>
      )}
      {c.items.map((a) => {
        const place = lanes.get(a.id)!;
        const top = (a.dateTime.getHours() * 60 + a.dateTime.getMinutes()) * minuteHeight;
        const bottom = Math.min(24 * hourHeight, top + a.durationMinutes * minuteHeight);
        const laneWidth = (width - 6) / place.lanes;
        return (
          <View
            key={a.id}
            style={{ position: 'absolute', top: top + 1, height: Math.max(20, bottom - top - 2), left: 2 + place.lane * laneWidth, width: laneWidth - 2 }}
          >
            <AppointmentBlock appointment={a} title={title(a)} onPress={onOpen ? () => onOpen(a) : undefined} />
          </View>
        );
      })}
      {today && (
        <View pointerEvents="none" style={{ position: 'absolute', top: (now.getHours() * 60 + now.getMinutes()) * minuteHeight - 4, left: 0, right: 0, flexDirection: 'row', alignItems: 'center' }}>
          <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: colors.error }} />
          <View style={{ flex: 1, height: 2, backgroundColor: colors.error }} />
        </View>
      )}
    </View>
  );
}

/// A visit on the time grid: tinted by its status, as tall as it lasts.
export function AppointmentBlock({ appointment: a, title, onPress }: { appointment: Appointment; title: string; onPress?: () => void }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const [height, setHeight] = useState(40);
  const color = readable(statusMeta[a.status].color);
  const gone = !holdsTime(a.status);
  const time = format(a.dateTime, 'h:mm');
  const end = format(a.endsAt, 'h:mm a');
  const text = {
    fontSize: 11,
    lineHeight: 13,
    color: gone ? colors.onSurfaceVariant : colors.onSurface,
    textDecorationLine: gone ? ('line-through' as const) : ('none' as const),
  };
  const roomy = height >= 34;
  return (
    <Tooltip title={`${title}\n${time} – ${end} · ${a.service}\nDr. ${a.doctor.name} · ${statusMeta[a.status].label}`} enterTouchDelay={500}>
      <Pressable
        onPress={onPress}
        onLayout={(e) => setHeight(e.nativeEvent.layout.height)}
        style={{
          flex: 1,
          borderRadius: 6,
          overflow: 'hidden',
          backgroundColor: lerpColor(colors.surface, color.startsWith('#') ? color : '#888888', (gone ? 18 : 46) / 255),
          borderLeftWidth: 3,
          borderLeftColor: color,
          paddingLeft: 5,
          paddingRight: 4,
          paddingVertical: 2,
        }}
      >
        <Text numberOfLines={1} style={[text, { fontWeight: '600' }]}>
          {roomy ? title : `${time} ${title}`}
        </Text>
        {roomy && (
          <Text numberOfLines={height >= 60 ? 3 : 1} style={text}>
            {time} – {end} · {a.service}
          </Text>
        )}
      </Pressable>
    </Tooltip>
  );
}

// ── Month ───────────────────────────────────────────────────────────────────

/// Below this width a month cell shows dots, not lines of text.
const roomyMonthCell = 96;
const monthLine = 18;

function MonthGrid({
  date,
  appointments,
  timeOff,
  title,
  onOpen,
  onDayTap,
}: {
  date: Date;
  appointments: Appointment[];
  timeOff: TimeOff[];
  title: (a: Appointment) => string;
  onOpen?: (a: Appointment) => void;
  onDayTap?: (day: Date) => void;
}) {
  const { colors } = useAppTheme();
  const range = calendarRangeFor('month', date);
  const [size, setSize] = useState({ width: 700, height: 500 });
  const byDay = new Map<number, Appointment[]>();
  for (const a of [...appointments].sort((x, y) => x.dateTime.getTime() - y.dateTime.getTime())) {
    const k = startOfDay(a.dateTime).getTime();
    const list = byDay.get(k) ?? [];
    list.push(a);
    byDay.set(k, list);
  }
  const rowHeight = Math.max(size.height / 6, 76);
  const roomy = size.width / 7 >= roomyMonthCell;
  const rows = (
    <View>
      {Array.from({ length: 6 }, (_, w) => (
        <View key={w} style={{ height: rowHeight, flexDirection: 'row' }}>
          {Array.from({ length: 7 }, (_, i) => {
            const day = addDays(range.from, w * 7 + i);
            return (
              <View key={i} style={{ flex: 1 }}>
                <MonthCell
                  day={day}
                  inMonth={day.getMonth() === date.getMonth()}
                  items={byDay.get(day.getTime()) ?? []}
                  closure={closureOn(timeOff, day)}
                  roomy={roomy}
                  height={rowHeight}
                  title={title}
                  onOpen={onOpen}
                  onPress={onDayTap ? () => onDayTap(day) : undefined}
                />
              </View>
            );
          })}
        </View>
      ))}
    </View>
  );
  return (
    <View style={{ flex: 1 }}>
      <View style={{ height: 32, flexDirection: 'row' }}>
        {Array.from({ length: 7 }, (_, i) => (
          <View key={i} style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
            <Text variant="labelSmall" style={{ color: colors.onSurfaceVariant }}>
              {format(addDays(range.from, i), 'EEE').toUpperCase()}
            </Text>
          </View>
        ))}
      </View>
      <View style={{ height: 1, backgroundColor: colors.outlineVariant }} />
      <View style={{ flex: 1 }} onLayout={(e) => setSize({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}>
        {rowHeight * 6 <= size.height + 0.5 ? rows : <ScrollView>{rows}</ScrollView>}
      </View>
    </View>
  );
}

function MonthCell({
  day,
  inMonth,
  items,
  closure,
  roomy,
  height,
  title,
  onOpen,
  onPress,
}: {
  day: Date;
  inMonth: boolean;
  items: Appointment[];
  closure: TimeOff | null;
  roomy: boolean;
  height: number;
  title: (a: Appointment) => string;
  onOpen?: (a: Appointment) => void;
  onPress?: () => void;
}) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const today = isSameDay(day, new Date());
  const live = items.filter((a) => holdsTime(a.status));
  let body: React.ReactNode;
  if (roomy) {
    const fit = Math.max(0, Math.floor((height - 36) / monthLine));
    const shown = items.length <= fit ? items : items.slice(0, Math.max(0, fit - 1));
    const more = items.length - shown.length;
    body = (
      <View>
        {closure != null && fit > 0 && items.length === 0 && (
          <Text numberOfLines={1} style={{ fontSize: 10, color: colors.onSurfaceVariant }}>
            {closedLabel(closure)}
          </Text>
        )}
        {shown.map((a) => (
          <MonthChip key={a.id} appointment={a} title={title(a)} onPress={onOpen ? () => onOpen(a) : undefined} />
        ))}
        {more > 0 && <Text style={{ marginLeft: 4, marginTop: 1, fontSize: 11, fontWeight: '600', color: colors.onSurfaceVariant }}>+{more} more</Text>}
      </View>
    );
  } else {
    // A phone: a dot per visit (up to four) and the count; tap for the day.
    body = (
      <View style={{ alignItems: 'center' }}>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 3 }}>
          {live.slice(0, 4).map((a) => (
            <View key={a.id} style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: readable(statusMeta[a.status].color) }} />
          ))}
        </View>
        {live.length > 4 && <Text style={{ fontSize: 10, color: colors.onSurfaceVariant }}>+{live.length - 4}</Text>}
      </View>
    );
  }
  return (
    <Pressable
      onPress={onPress}
      accessibilityLabel={`${format(day, 'EEEE, MMMM d')}, ${live.length} visit${live.length === 1 ? '' : 's'}`}
      style={{
        flex: 1,
        padding: 2,
        overflow: 'hidden',
        borderRightWidth: 0.5,
        borderBottomWidth: 0.5,
        borderColor: colors.outlineVariant,
        backgroundColor: closure != null ? withAlpha(colors.surfaceContainerHighest, 140 / 255) : inMonth ? colors.surface : colors.surfaceContainerLow,
        alignItems: roomy ? 'stretch' : 'center',
      }}
    >
      <View style={{ alignSelf: roomy ? 'flex-start' : 'center' }}>
        <DayNumber day={day} today={today} muted={!inMonth} />
      </View>
      <View style={{ height: 2 }} />
      <View style={{ flex: 1, overflow: 'hidden' }}>{body}</View>
    </Pressable>
  );
}

function MonthChip({ appointment: a, title, onPress }: { appointment: Appointment; title: string; onPress?: () => void }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const gone = !holdsTime(a.status);
  const color = readable(statusMeta[a.status].color);
  return (
    <Pressable onPress={onPress} style={{ height: monthLine, flexDirection: 'row', alignItems: 'center', gap: 4, paddingLeft: 2, borderRadius: 4 }}>
      <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: gone ? 'transparent' : color, borderWidth: gone ? 1 : 0, borderColor: color }} />
      <Text
        numberOfLines={1}
        style={{ flex: 1, fontSize: 11, color: gone ? colors.onSurfaceVariant : colors.onSurface, textDecorationLine: gone ? 'line-through' : 'none' }}
      >
        {format(a.dateTime, 'h:mma').toLowerCase()} {title}
      </Text>
    </Pressable>
  );
}

/// Status colours as a key, for the foot of the calendar.
export function CalendarLegend() {
  const { colors } = useAppTheme();
  const readable = useReadable();
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', columnGap: 12, rowGap: 4 }}>
      {appointmentStatuses
        .filter((s) => s !== 'no_show')
        .map((s) => (
          <View key={s} style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
            <View style={{ width: 10, height: 10, borderRadius: 3, backgroundColor: readable(statusMeta[s].color) }} />
            <Text style={{ fontSize: 11, color: colors.onSurfaceVariant }}>{statusMeta[s].label}</Text>
          </View>
        ))}
    </View>
  );
}
