import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { ActivityIndicator, Button, Chip, SegmentedButtons, Text } from 'react-native-paper';
import Svg, { Circle, Line, Path, Rect } from 'react-native-svg';

import { ContentWidth, useLayoutWidth } from '../app/adaptive';
import type { Appointment } from '../models/appointment';
import {
  describeTooth,
  type DentalChart,
  type DentalCode,
  type DentalEntry,
  type DentalEntryStatus,
  type Dentition,
  type ToothNumbering,
  type ToothState,
  type ToothSurface,
  ToothState as ToothStateClass,
  allowedStatuses,
  dentalCodeMeta,
  dentalCodes,
  dentitionForAge,
  dentitionLabel,
  lowerTeeth,
  surfaceLabelFor,
  surfacesLabel,
  toothLabel,
  toothName,
  toothNumberingLabel,
  toothSurfaces,
  upperTeeth,
} from '../models/dental_chart';
import type { Patient } from '../models/patient';
import { useCanSeeClinicalNotes } from '../queries/clinical';
import { useClinicChartsTeeth, useDentalChart } from '../queries/misc';
import { useRepository } from '../state/platform';
import { preferences, usePreference } from '../state/preferences';
import { useAppTheme, useReadable, withAlpha } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { TextField } from '../ui/fields';
import { Icon } from '../ui/icon';
import { Avatar, ListTile, MenuButton } from '../ui/kit';
import { SheetScroll, useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';

/// How this device numbers teeth, and the setter.
export function useToothNumbering(): [ToothNumbering, (n: ToothNumbering) => void] {
  const numbering = usePreference((p) => p.toothNumbering);
  return [numbering, (n) => preferences.setToothNumbering(n)];
}

// ── The odontogram ──────────────────────────────────────────────────────────

const midline = 10;
const minTooth = 26;
const maxTooth = 52;

/// Both arches of one dentition, drawn as the dentist faces the patient: the
/// patient's right on the left of the screen, upper arch on top.
///
/// Each tooth is the classic five-surface diagram — the centre square is the
/// occlusal (or incisal) surface, the four sides are buccal on the outside of
/// the arch, lingual on the inside, mesial toward the midline, distal away
/// from it — coloured by what is on each surface now. A badge under the
/// tooth names whole-tooth work (crown, root canal, implant…), a dot marks
/// planned work, and a missing tooth is crossed out.
export function Odontogram({
  chart,
  dentition,
  numbering,
  selectedTooth = null,
  highlighted = new Set(),
  onToothTap,
}: {
  chart: DentalChart;
  dentition: Dentition;
  numbering: ToothNumbering;
  selectedTooth?: number | null;
  /// Teeth to pick out, e.g. those touched at the visit being viewed.
  highlighted?: ReadonlySet<number>;
  onToothTap?: (tooth: number) => void;
}) {
  const { colors } = useAppTheme();
  const [available, onLayout] = useLayoutWidth();
  const perArch = upperTeeth(dentition).length;
  const size = Math.min(maxTooth, Math.max(minTooth, (available - midline) / perArch));
  const width = size * perArch + midline;

  const arch = (teeth: number[], upper: boolean) => {
    const half = Math.floor(teeth.length / 2);
    const cell = (t: number) => (
      <ToothCell
        key={t}
        state={chart.stateOf(t)}
        size={size}
        upper={upper}
        label={toothLabel(numbering, t)}
        selected={t === selectedTooth}
        highlighted={highlighted.has(t)}
        onPress={onToothTap == null ? undefined : () => onToothTap(t)}
      />
    );
    return (
      <View style={{ flexDirection: 'row', alignItems: 'flex-start' }}>
        {teeth.slice(0, half).map(cell)}
        <View style={{ width: midline, alignItems: 'center' }}>
          <View style={{ width: 1, height: size * 1.9, backgroundColor: colors.outlineVariant }} />
        </View>
        {teeth.slice(half).map(cell)}
      </View>
    );
  };

  const arches = (
    <View style={{ width }}>
      {arch(upperTeeth(dentition), true)}
      <View style={{ width, height: 1, marginVertical: 4, backgroundColor: colors.outlineVariant }} />
      {arch(lowerTeeth(dentition), false)}
    </View>
  );
  return (
    <View onLayout={onLayout} style={{ width: '100%' }}>
      {/* Too narrow for even the smallest teeth: scroll rather than squash. */}
      {width > available ? (
        <ScrollView horizontal>{arches}</ScrollView>
      ) : (
        <View style={{ alignItems: 'center' }}>{arches}</View>
      )}
    </View>
  );
}

function ToothCell({
  state,
  size,
  upper,
  label,
  selected,
  highlighted,
  onPress,
}: {
  state: ToothState;
  size: number;
  upper: boolean;
  label: string;
  selected: boolean;
  highlighted: boolean;
  onPress?: () => void;
}) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const headline = state.headline;
  const number = (
    <View style={{ height: 16 }}>
      <Text
        style={{
          fontSize: size < 32 ? 9 : 10,
          fontWeight: selected ? '700' : '500',
          color: selected ? colors.primary : colors.onSurfaceVariant,
          textAlign: 'center',
        }}
      >
        {label}
      </Text>
    </View>
  );
  const badge = (
    <View style={{ height: 14 }}>
      {headline != null && headline !== 'missing' && (
        <Text numberOfLines={1} style={{ fontSize: 9, fontWeight: '700', color: readable(dentalCodeMeta[headline].color), textAlign: 'center' }}>
          {dentalCodeMeta[headline].abbreviation}
        </Text>
      )}
    </View>
  );
  const painted = (
    <ToothDrawing
      state={state}
      upper={upper}
      size={size - 4}
      outline={selected ? colors.primary : colors.outline}
      empty={highlighted ? colors.primaryContainer : colors.surface}
      strokeWidth={selected ? 2 : 1}
    />
  );
  return (
    <Pressable
      onPress={onPress}
      disabled={onPress == null}
      accessibilityRole={onPress ? 'button' : undefined}
      accessibilityState={{ selected }}
      accessibilityLabel={`Tooth ${label}, ${toothName(state.tooth)}. ${describeTooth(state)}`}
      style={{ width: size, alignItems: 'center', borderRadius: 6 }}
    >
      {upper ? (
        <>
          {number}
          {painted}
          {badge}
        </>
      ) : (
        <>
          {badge}
          {painted}
          {number}
        </>
      )}
    </Pressable>
  );
}


/// A tint for the whole tooth when something covers all of it.
function wholeFill(state: ToothState): string | null {
  for (const c of ['implant', 'crown', 'bridge', 'impacted', 'fracture', 'caries', 'veneer', 'watch'] as const) {
    if (state.whole.has(c)) return withAlpha(dentalCodeMeta[c].color, 70 / 255);
  }
  return null;
}

function ToothDrawing({
  state,
  upper,
  size,
  outline,
  empty,
  strokeWidth,
}: {
  state: ToothState;
  upper: boolean;
  size: number;
  outline: string;
  empty: string;
  strokeWidth: number;
}) {
  const w = size;
  const h = size;
  const inset = w * 0.3;
  const half = strokeWidth / 2;
  const o = { l: half, t: half, r: w - half, b: h - half };
  const i = { l: inset, t: inset, r: w - inset, b: h - inset };
  // Which drawn side is which surface. Buccal is always the outside of the
  // arch; mesial always faces the midline, which is on the right for the
  // patient's right-hand quadrants (1, 4, 5, 8) as drawn.
  const q = Math.floor(state.tooth / 10);
  const patientsRight = q === 1 || q === 4 || q === 5 || q === 8;
  const quad = (pts: [number, number][]) => `M${pts.map(([x, y]) => `${x},${y}`).join('L')}Z`;
  const polygons: [ToothSurface, string][] = [
    [upper ? 'B' : 'L', quad([[o.l, o.t], [o.r, o.t], [i.r, i.t], [i.l, i.t]])],
    [upper ? 'L' : 'B', quad([[o.l, o.b], [o.r, o.b], [i.r, i.b], [i.l, i.b]])],
    [patientsRight ? 'D' : 'M', quad([[o.l, o.t], [i.l, i.t], [i.l, i.b], [o.l, o.b]])],
    [patientsRight ? 'M' : 'D', quad([[o.r, o.t], [i.r, i.t], [i.r, i.b], [o.r, o.b]])],
    ['O', quad([[i.l, i.t], [i.r, i.t], [i.r, i.b], [i.l, i.b]])],
  ];
  const whole = wholeFill(state);
  const stroke = state.missing ? withAlpha(outline, 90 / 255) : outline;
  const plannedR = Math.max(3, w * 0.12);
  return (
    <Svg width={w} height={h}>
      {polygons.map(([surface, d]) => {
        const code = state.surfaces.get(surface);
        const fill = state.missing
          ? withAlpha(empty, 90 / 255)
          : code != null
            ? withAlpha(dentalCodeMeta[code].color, (dentalCodeMeta[code].isCondition ? 200 : 170) / 255)
            : whole ?? empty;
        return <Path key={surface} d={d} fill={fill} stroke={stroke} strokeWidth={strokeWidth} />;
      })}
      {/* A crown caps the whole tooth: a heavy ring in the crown's colour. */}
      {state.whole.has('crown') && (
        <Rect
          x={o.l + 1}
          y={o.t + 1}
          width={o.r - o.l - 2}
          height={o.b - o.t - 2}
          fill="none"
          stroke={dentalCodeMeta.crown.color}
          strokeWidth={Math.max(2.5, w * 0.08)}
        />
      )}
      {/* A root canal: a line down the middle, the way it shows on a film. */}
      {state.whole.has('root_canal') && (
        <Line
          x1={w / 2}
          y1={upper ? i.t : 0}
          x2={w / 2}
          y2={upper ? h : i.b}
          stroke={dentalCodeMeta.root_canal.color}
          strokeWidth={Math.max(2, w * 0.07)}
        />
      )}
      {state.missing && (
        <>
          <Line x1={o.l + 3} y1={o.t + 3} x2={o.r - 3} y2={o.b - 3} stroke={dentalCodeMeta.missing.color} strokeWidth={Math.max(1.5, w * 0.06)} strokeLinecap="round" />
          <Line x1={o.r - 3} y1={o.t + 3} x2={o.l + 3} y2={o.b - 3} stroke={dentalCodeMeta.missing.color} strokeWidth={Math.max(1.5, w * 0.06)} strokeLinecap="round" />
        </>
      )}
      {/* Work still to do: a dot in the corner, in the colour of what is next. */}
      {state.planned.length > 0 && (
        <>
          <Circle cx={w - plannedR * 0.6} cy={plannedR * 0.6} r={plannedR + 1} fill={empty} />
          <Circle
            cx={w - plannedR * 0.6}
            cy={plannedR * 0.6}
            r={plannedR}
            fill={dentalCodeMeta[state.planned[state.planned.length - 1].code].color}
            stroke="#FFFFFF"
            strokeWidth={1}
          />
        </>
      )}
    </Svg>
  );
}

/// What the colours mean. Only the codes on this chart, so it stays short.
export function DentalChartLegend({ chart }: { chart: DentalChart }) {
  const { colors } = useAppTheme();
  const used = new Set(chart.entries.filter((e) => e.status !== 'planned').map((e) => e.code));
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', columnGap: 12, rowGap: 6 }}>
      {dentalCodes
        .filter((c) => used.has(c))
        .map((c) => (
          <View key={c} style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
            <View style={{ width: 10, height: 10, borderRadius: 2, backgroundColor: dentalCodeMeta[c].color }} />
            <Text style={{ fontSize: 11, color: colors.onSurfaceVariant }}>{dentalCodeMeta[c].label}</Text>
          </View>
        ))}
      {chart.plan.length > 0 && (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
          <Icon name="circle" size={10} color={colors.tertiary} />
          <Text style={{ fontSize: 11, color: colors.onSurfaceVariant }}>Planned</Text>
        </View>
      )}
    </View>
  );
}

// ── The chart on a patient's record ─────────────────────────────────────────

/// Work can be charted as done only at a visit the patient came to. Mirrors
/// the database's rule.
function attended(a: Appointment | null | undefined): boolean {
  return a != null && (a.status === 'arrived' || a.status === 'in_consultation' || a.status === 'completed');
}

function useInvalidateDental(): () => Promise<void> {
  const qc = useQueryClient();
  return () => qc.invalidateQueries({ queryKey: ['dentalEntries'] });
}

/// The dental chart section of a patient's record or of a visit.
///
/// Renders nothing unless the current clinic charts teeth. Doctors and
/// admins tap a tooth to chart it; everyone else taps to read what is on it.
/// With an [appointment], teeth touched at that visit are highlighted, what
/// was recorded there is listed, and work can be charted as done at it once
/// the patient has arrived.
export function DentalChartSection({ patient, appointment = null }: { patient: Patient; appointment?: Appointment | null }) {
  const { colors } = useAppTheme();
  const chartsTeeth = useClinicChartsTeeth();
  const chartAsync = useDentalChart(patient.id);
  const [numbering] = useToothNumbering();
  const canChart = useCanSeeClinicalNotes().value ?? false;
  const [chosen, setDentition] = useState<Dentition | null>(null);
  const invalidate = useInvalidateDental();
  const openTooth = useToothSheet();
  if (!chartsTeeth) return null;

  return (
    <View style={{ marginBottom: 12, padding: 12, paddingBottom: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <AsyncView value={chartAsync} padded onRetry={() => void invalidate()}>
        {(chart) => {
          const dentition = chosen ?? (chart.hasPermanentTeeth ? 'permanent' : chart.hasPrimaryTeeth ? 'primary' : dentitionForAge(patient.age));
          const atVisit = appointment == null ? [] : chart.atVisit(appointment.id);
          const open = (t: number) => openTooth({ patient, tooth: t, appointment });
          return (
            <View>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                <Icon name="grid-view" size={16} color={colors.onSurfaceVariant} />
                <Text style={{ flex: 1, fontWeight: '600', color: colors.onSurfaceVariant, fontSize: 12 }}>Dental chart</Text>
                <ChartOptions dentition={dentition} onDentition={setDentition} />
              </View>
              <Text style={{ fontSize: 11, color: colors.outline }}>
                {canChart ? 'Tap a tooth to chart it.' : 'Tap a tooth to see its history.'}
              </Text>
              <View style={{ height: 12 }} />
              <Odontogram chart={chart} dentition={dentition} numbering={numbering} highlighted={new Set(atVisit.map((e) => e.tooth))} onToothTap={open} />
              <View style={{ height: 12 }} />
              <DentalChartLegend chart={chart} />
              {appointment != null && (
                <>
                  <View style={{ height: 16 }} />
                  <SubHeading text="At this visit" />
                  {atVisit.length === 0 ? (
                    <Text style={{ fontSize: 13, color: colors.outline }}>
                      {canChart ? 'Nothing charted yet. Tap the teeth you examine or treat.' : 'Nothing charted at this visit.'}
                    </Text>
                  ) : (
                    atVisit.map((e) => <DentalEntryTile key={e.id} entry={e} numbering={numbering} onPress={() => open(e.tooth)} />)
                  )}
                </>
              )}
              {chart.plan.length > 0 && (
                <>
                  <View style={{ height: 16 }} />
                  <SubHeading text="Treatment plan" />
                  {chart.plan.map((e) => (
                    <DentalEntryTile
                      key={e.id}
                      entry={e}
                      numbering={numbering}
                      trailing={canChart && attended(appointment) ? <MarkDoneButton entry={e} appointmentId={appointment!.id} /> : undefined}
                      onPress={() => open(e.tooth)}
                    />
                  ))}
                </>
              )}
            </View>
          );
        }}
      </AsyncView>
    </View>
  );
}

function SubHeading({ text }: { text: string }) {
  return <Text style={{ fontWeight: '600', fontSize: 13, marginBottom: 4 }}>{text}</Text>;
}

/// Adult/child teeth, and FDI/Universal numbering (remembered on this
/// device).
function ChartOptions({ dentition, onDentition }: { dentition: Dentition; onDentition: (d: Dentition) => void }) {
  const [numbering, setNumbering] = useToothNumbering();
  return (
    <MenuButton
      icon="tune"
      label="Chart options"
      items={[
        { header: 'Teeth' },
        ...(['permanent', 'primary'] as const).map((d) => ({
          label: dentitionLabel[d],
          icon: d === dentition ? ('check' as const) : undefined,
          onPress: () => onDentition(d),
        })),
        'divider',
        { header: 'Numbering' },
        ...(['fdi', 'universal'] as const).map((n) => ({
          label: toothNumberingLabel[n],
          icon: n === numbering ? ('check' as const) : undefined,
          onPress: () => setNumbering(n),
        })),
      ]}
    />
  );
}

function statusText(e: DentalEntry): string {
  const date = e.createdAt == null ? '' : ` ${format(e.createdAt, 'MMM d, y')}`;
  switch (e.status) {
    case 'existing':
      return dentalCodeMeta[e.code].isCondition ? `Found${date}` : `Already present${date}`;
    case 'planned':
      return `Planned${date}`;
    case 'done':
      return `Done${date}`;
  }
}

/// One line of the chart: `Filling 46 · MO`, its status, and its note.
export function DentalEntryTile({
  entry: e,
  numbering,
  trailing,
  onPress,
  forPatient = false,
}: {
  entry: DentalEntry;
  numbering: ToothNumbering;
  trailing?: React.ReactNode;
  onPress?: () => void;
  forPatient?: boolean;
}) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const meta = dentalCodeMeta[e.code];
  return (
    <ListTile
      dense
      paddingHorizontal={0}
      onPress={onPress}
      leading={<Avatar icon={meta.icon} size={32} color={withAlpha(meta.color, 40 / 255)} textColor={readable(meta.color)} />}
      title={<Text style={{ fontWeight: '600' }}>{e.describe(numbering, { forPatient })}</Text>}
      subtitle={
        <Text numberOfLines={2} style={{ color: colors.onSurfaceVariant }}>
          {[forPatient ? toothName(e.tooth) : statusText(e), ...(e.note != null && !forPatient ? [e.note] : [])].join(' · ')}
        </Text>
      }
      trailing={trailing}
    />
  );
}

function MarkDoneButton({ entry, appointmentId }: { entry: DentalEntry; appointmentId: string }) {
  const repo = useRepository();
  const overlay = useOverlay();
  const invalidate = useInvalidateDental();
  const [busy, setBusy] = useState(false);
  return (
    <Button
      compact
      disabled={busy}
      onPress={async () => {
        setBusy(true);
        try {
          await repo.completeDentalEntry(entry.id, appointmentId);
          await invalidate();
        } catch (e) {
          overlay.snack(describeError(e));
        } finally {
          setBusy(false);
        }
      }}
    >
      {busy ? <ActivityIndicator size={16} /> : 'Done today'}
    </Button>
  );
}

// ── One tooth ───────────────────────────────────────────────────────────────

/// Everything about one tooth, and — for a doctor or admin — the form to
/// chart something new on it.
export function useToothSheet(): (args: { patient: Patient; tooth: number; appointment?: Appointment | null }) => void {
  const overlay = useOverlay();
  return (args) => void overlay.showSheet(() => <ToothSheet {...args} />);
}

function ToothSheet({ patient, tooth, appointment = null }: { patient: Patient; tooth: number; appointment?: Appointment | null }) {
  const { colors } = useAppTheme();
  const [numbering] = useToothNumbering();
  const canChart = useCanSeeClinicalNotes().value ?? false;
  const chart = useDentalChart(patient.id).value;
  const state = chart?.stateOf(tooth) ?? new ToothStateClass(tooth);
  const history = [...state.history].reverse();
  const [adding, setAdding] = useState(false);

  return (
    <SheetScroll padding={20}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
        <View style={{ width: 44, height: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.primaryContainer }}>
          <Text style={{ fontWeight: '700', fontSize: 16, color: colors.onPrimaryContainer }}>{toothLabel(numbering, tooth)}</Text>
        </View>
        <View style={{ flex: 1 }}>
          <Text variant="titleMedium" style={{ fontWeight: '700' }}>
            {toothName(tooth)}
          </Text>
          <Text style={{ color: colors.onSurfaceVariant }}>{describeTooth(state)}</Text>
        </View>
      </View>
      <View style={{ height: 16 }} />
      {canChart && !adding && (
        <Button mode="contained-tonal" icon="add" onPress={() => setAdding(true)}>
          Chart this tooth
        </Button>
      )}
      {adding && <EntryForm patient={patient} tooth={tooth} appointment={appointment} onDone={() => setAdding(false)} />}
      <Text variant="titleSmall" style={{ marginTop: 16 }}>
        History
      </Text>
      {history.length === 0 ? (
        <Text style={{ paddingVertical: 8, color: colors.outline }}>Nothing recorded on this tooth.</Text>
      ) : (
        history.map((e) => (
          <DentalEntryTile
            key={e.id}
            entry={e}
            numbering={numbering}
            trailing={canChart ? <EntryMenu entry={e} appointment={appointment} /> : undefined}
          />
        ))
      )}
    </SheetScroll>
  );
}

function EntryMenu({ entry, appointment }: { entry: DentalEntry; appointment: Appointment | null }) {
  const repo = useRepository();
  const overlay = useOverlay();
  const invalidate = useInvalidateDental();
  const canComplete = entry.status === 'planned' && attended(appointment);
  const run = async (work: () => Promise<void>) => {
    try {
      await work();
      await invalidate();
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };
  return (
    <MenuButton
      items={[
        ...(canComplete ? [{ label: 'Done at this visit', onPress: () => void run(() => repo.completeDentalEntry(entry.id, appointment!.id)) }] : []),
        {
          label: 'Remove',
          onPress: async () => {
            const sure = await overlay.confirm({
              title: 'Remove this entry?',
              message: 'Use this for something charted by mistake. It is removed from the chart for everyone.',
              cancelLabel: 'Keep',
              confirmLabel: 'Remove',
            });
            if (sure) await run(() => repo.deleteDentalEntry(entry.id));
          },
        },
      ]}
    />
  );
}

/// Chart one thing on one tooth: what, where on it, and whether it was
/// found, is planned, or was done today.
function EntryForm({ patient, tooth, appointment, onDone }: { patient: Patient; tooth: number; appointment: Appointment | null; onDone: () => void }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const repo = useRepository();
  const invalidate = useInvalidateDental();
  const [code, setCode] = useState<DentalCode | null>(null);
  const [status, setStatus] = useState<DentalEntryStatus | null>(null);
  const [surfaces, setSurfaces] = useState<Set<ToothSurface>>(new Set());
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const statusesFor = (c: DentalCode | null) =>
    c == null ? [] : allowedStatuses(c).filter((s) => s !== 'done' || attended(appointment));
  const statuses = statusesFor(code);

  const pick = (c: DentalCode) => {
    setCode(c);
    setError(null);
    if (!dentalCodeMeta[c].usesSurfaces) setSurfaces(new Set());
    const allowed = statusesFor(c);
    if (status == null || !allowed.includes(status)) {
      // At a visit the patient came to, treatment is most often what was
      // just done; anywhere else, what is planned.
      setStatus(allowed.includes('done') ? 'done' : allowed.includes('planned') ? 'planned' : allowed[0]);
    }
  };

  const valid =
    code != null &&
    status != null &&
    (!dentalCodeMeta[code].usesSurfaces || surfaces.size > 0 || dentalCodeMeta[code].isCondition || code === 'veneer');

  const save = async () => {
    if (code == null || status == null || busy) return;
    setBusy(true);
    setError(null);
    try {
      await repo.addDentalEntry({
        clinicId: patient.clinicId,
        patientId: patient.id,
        tooth,
        code,
        status,
        surfaces: dentalCodeMeta[code].usesSurfaces ? surfaces : new Set(),
        appointmentId: appointment?.id,
        note,
      });
      await invalidate();
      onDone();
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  const chips = (codes: DentalCode[]) => (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
      {codes.map((c) => (
        <Chip
          key={c}
          mode="outlined"
          selected={c === code}
          icon={() => <Icon name={dentalCodeMeta[c].icon} size={16} color={readable(dentalCodeMeta[c].color)} />}
          onPress={() => pick(c)}
        >
          {dentalCodeMeta[c].label}
        </Chip>
      ))}
    </View>
  );

  const statusLabel: Record<DentalEntryStatus, string> = { existing: 'Already there', planned: 'Plan it', done: 'Done today' };

  return (
    <View style={{ padding: 12, borderWidth: 1, borderColor: colors.outlineVariant, borderRadius: 12 }}>
      <Text style={{ fontSize: 12, color: colors.outline, marginBottom: 4 }}>Found</Text>
      {chips(dentalCodes.filter((c) => dentalCodeMeta[c].isCondition))}
      <Text style={{ fontSize: 12, color: colors.outline, marginTop: 12, marginBottom: 4 }}>Treatment</Text>
      {chips(dentalCodes.filter((c) => !dentalCodeMeta[c].isCondition))}
      {code != null && dentalCodeMeta[code].usesSurfaces && (
        <>
          <Text style={{ fontSize: 12, color: colors.outline, marginTop: 12, marginBottom: 4 }}>Surfaces</Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
            {toothSurfaces.map((s) => (
              <Chip
                key={s}
                mode="outlined"
                selected={surfaces.has(s)}
                showSelectedCheck
                onPress={() => {
                  const next = new Set(surfaces);
                  if (next.has(s)) next.delete(s);
                  else next.add(s);
                  setSurfaces(next);
                }}
              >
                {`${s} · ${surfaceLabelFor(s, tooth)}`}
              </Chip>
            ))}
          </View>
        </>
      )}
      {code != null && statuses.length > 1 && (
        <SegmentedButtons
          style={{ marginTop: 12 }}
          value={status ?? ''}
          onValueChange={(v) => setStatus(v as DentalEntryStatus)}
          buttons={statuses.map((s) => ({ value: s, label: statusLabel[s] }))}
        />
      )}
      <TextField
        style={{ marginTop: 12 }}
        value={note}
        onChangeText={setNote}
        maxLength={500}
        multiline
        minLines={1}
        autoCapitalize="sentences"
        placeholder="Detail, e.g. composite, shade A2 (staff only)"
      />
      {error != null && <Text style={{ marginTop: 8, color: colors.error }}>{error}</Text>}
      <View style={{ flexDirection: 'row', gap: 8, marginTop: 8 }}>
        <Button mode="outlined" style={{ flex: 1 }} disabled={busy} onPress={onDone}>
          Cancel
        </Button>
        <Button mode="contained" style={{ flex: 1 }} disabled={busy || !valid} onPress={save}>
          {busy ? <ActivityIndicator size={18} /> : 'Save'}
        </Button>
      </View>
    </View>
  );
}

// ── For the patient ─────────────────────────────────────────────────────────

/// What happened to the patient's teeth at one visit, in plain words: what
/// was done, what was found, what is planned next. Renders nothing when
/// nothing was charted or the clinic does not chart teeth.
export function VisitDentalSummary({ patientId, appointmentId, forPatient = false }: { patientId: string; appointmentId: string; forPatient?: boolean }) {
  const { colors } = useAppTheme();
  const chartsTeeth = useClinicChartsTeeth();
  const chart = useDentalChart(patientId).value;
  const [numbering] = useToothNumbering();
  if (!chartsTeeth || chart == null) return null;
  const entries = chart.atVisit(appointmentId);
  if (entries.length === 0) return null;
  const having = (s: DentalEntryStatus) => entries.filter((e) => e.status === s);
  const groups: [string, DentalEntry[]][] = [
    [forPatient ? 'Treatment you received' : 'Done', having('done')],
    [forPatient ? 'What the dentist found' : 'Found', having('existing')],
    [forPatient ? 'Recommended next' : 'Planned', having('planned')],
  ];
  return (
    <View style={{ marginBottom: 12, padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name="grid-view" size={16} color={colors.primary} />
        <Text style={{ fontWeight: '600', color: colors.onSurfaceVariant }}>Your teeth at this visit</Text>
      </View>
      {groups
        .filter(([, list]) => list.length > 0)
        .map(([title, list]) => (
          <View key={title} style={{ marginTop: 10 }}>
            <SubHeading text={title} />
            {list.map((e) => (
              <DentalEntryTile key={e.id} entry={e} numbering={numbering} forPatient={forPatient} />
            ))}
          </View>
        ))}
    </View>
  );
}

/// A patient's whole chart, read-only: the teeth, and the plan in words.
export function MyDentalChartScreen({ patient }: { patient: Patient }) {
  const { colors } = useAppTheme();
  const [numbering] = useToothNumbering();
  const chartAsync = useDentalChart(patient.id);
  const invalidate = useInvalidateDental();
  const [selected, setSelected] = useState<number | null>(null);
  const [chosen, setDentition] = useState<Dentition | null>(null);

  return (
    <Page title="My teeth" maxWidth={ContentWidth.detail} back="/profile">
      <AsyncView value={chartAsync} padded onRetry={() => void invalidate()}>
        {(chart) => {
          const dentition = chosen ?? (chart.hasPermanentTeeth || !chart.hasPrimaryTeeth ? dentitionForAge(patient.age) : 'primary');
          const tooth = selected == null ? null : chart.stateOf(selected);
          return (
            <View>
              {chart.isEmpty && (
                <Text style={{ marginBottom: 16, color: colors.onSurfaceVariant }}>
                  Your dentist has not charted your teeth yet. After your next check-up, what they find and do will show here.
                </Text>
              )}
              <View style={{ paddingHorizontal: 8, paddingVertical: 12, borderRadius: 16, backgroundColor: colors.surfaceContainerLow, alignItems: 'center' }}>
                <SegmentedButtons
                  value={dentition}
                  onValueChange={(v) => {
                    setDentition(v as Dentition);
                    setSelected(null);
                  }}
                  buttons={(['permanent', 'primary'] as const).map((d) => ({ value: d, label: `${dentitionLabel[d]} teeth` }))}
                />
                <Text style={{ marginTop: 12, fontSize: 10, color: colors.outline }}>Your right</Text>
                <Odontogram
                  chart={chart}
                  dentition={dentition}
                  numbering={numbering}
                  selectedTooth={selected}
                  onToothTap={(t) => setSelected((s) => (s === t ? null : t))}
                />
                <View style={{ height: 12 }} />
                <DentalChartLegend chart={chart} />
              </View>
              {tooth != null && (
                <View style={{ marginTop: 16 }}>
                  <Text variant="titleMedium" style={{ fontWeight: '700' }}>
                    {toothName(tooth.tooth)}
                  </Text>
                  {tooth.isEmpty ? (
                    <Text style={{ marginTop: 4, color: colors.outline }}>Nothing recorded on this tooth.</Text>
                  ) : (
                    [...tooth.history].reverse().map((e) => <DentalEntryTile key={e.id} entry={e} numbering={numbering} forPatient />)
                  )}
                </View>
              )}
              {chart.plan.length > 0 && (
                <View style={{ marginTop: 16 }}>
                  <Text variant="titleMedium" style={{ fontWeight: '700' }}>
                    Recommended treatment
                  </Text>
                  <Text style={{ color: colors.onSurfaceVariant, fontSize: 13 }}>What your dentist has planned. Ask the clinic to book it.</Text>
                  {chart.plan.map((e) => (
                    <DentalEntryTile key={e.id} entry={e} numbering={numbering} forPatient />
                  ))}
                </View>
              )}
            </View>
          );
        }}
      </AsyncView>
    </Page>
  );
}

/// `Filling 46 MO · Sealant 36 O`: a visit's dental work on one line, for a
/// row in a list of visits.
export function VisitDentalLine({ patientId, appointmentId }: { patientId: string; appointmentId: string }) {
  const { colors } = useAppTheme();
  const chartsTeeth = useClinicChartsTeeth();
  const chart = useDentalChart(patientId).value;
  const [numbering] = useToothNumbering();
  if (!chartsTeeth || chart == null) return null;
  const entries = chart.atVisit(appointmentId);
  if (entries.length === 0) return null;
  return (
    <View style={{ marginTop: 6, flexDirection: 'row', flexWrap: 'wrap', gap: 4 }}>
      {entries.map((e) => {
        const meta = dentalCodeMeta[e.code];
        return (
          <View
            key={e.id}
            style={{
              paddingHorizontal: 6,
              paddingVertical: 2,
              borderRadius: 6,
              backgroundColor: withAlpha(meta.color, 30 / 255),
              borderWidth: e.status === 'planned' ? 1 : 0,
              borderColor: withAlpha(meta.color, 120 / 255),
            }}
          >
            <Text style={{ fontSize: 11, fontWeight: '600', color: colors.onSurface }}>
              {`${meta.abbreviation} ${toothLabel(numbering, e.tooth)}${e.surfaces.size === 0 ? '' : ` ${surfacesLabel(e.surfaces)}`}`}
            </Text>
          </View>
        );
      })}
    </View>
  );
}
