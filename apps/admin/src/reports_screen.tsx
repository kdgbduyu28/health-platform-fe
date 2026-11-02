import {
  AsyncView,
  type BillingRange,
  Breakdown,
  type ClinicReport,
  ContentWidth,
  Icon,
  type IconName,
  Page,
  RangeDialog,
  type ReportDay,
  addDays,
  clinicReportCsvRows,
  downloadTextFile,
  formatPeso,
  formatRate,
  inBrowser,
  invoiceStatusMeta,
  isSameDay,
  isoWeekday,
  startOfDay,
  statusMeta,
  toCsv,
  useAppTheme,
  useClinicReport,
  useCurrentClinic,
  useLayoutWidth,
  useOverlay,
  useReadable,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { Button, Chip, Text } from 'react-native-paper';

type Period = 'week' | 'month' | 'lastMonth' | 'days90' | 'custom';
const periodLabel: Record<Period, string> = {
  week: 'This week',
  month: 'This month',
  lastMonth: 'Last month',
  days90: 'Last 90 days',
  custom: 'Pick dates…',
};

function rangeOf(period: Period, custom: BillingRange | null, today: Date): BillingRange {
  switch (period) {
    case 'week':
      // Monday to today.
      return { from: addDays(today, -(isoWeekday(today) - 1)), to: today };
    case 'month':
      return { from: new Date(today.getFullYear(), today.getMonth(), 1), to: today };
    case 'lastMonth':
      return { from: new Date(today.getFullYear(), today.getMonth() - 1, 1), to: new Date(today.getFullYear(), today.getMonth(), 0) };
    case 'days90':
      return { from: addDays(today, -89), to: today };
    case 'custom':
      return custom ?? { from: today, to: today };
  }
}

/// How a run of days went: visits and no-shows, new patients, what was
/// billed and paid, per day, per doctor and per service. Admins only — the
/// database refuses anyone else. Every figure is `clinic_report`'s.
export function ReportsScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const clinic = useCurrentClinic().value ?? null;
  const [period, setPeriod] = useState<Period>('month');
  const [custom, setCustom] = useState<BillingRange | null>(null);
  const today = startOfDay(new Date());
  const range = rangeOf(period, custom, today);
  const report = useClinicReport(range);
  const label = isSameDay(range.from, range.to)
    ? format(range.from, 'MMM d, y')
    : `${format(range.from, 'MMM d, y')} – ${format(range.to, 'MMM d, y')}`;

  const pickRange = async () => {
    const picked = await overlay.showDialog<BillingRange>((close) => (
      <RangeDialog initial={custom ?? range} first={new Date(today.getFullYear() - 5, 0, 1)} last={today} close={close} />
    ));
    if (picked) {
      setCustom(picked);
      setPeriod('custom');
    }
  };

  const exportCsv = (r: ClinicReport) => {
    const name = `report-${clinic?.slug ?? 'clinic'}-${format(r.from, 'yyyy-MM-dd')}-to-${format(r.to, 'yyyy-MM-dd')}.csv`;
    downloadTextFile(name, 'text/csv', toCsv(clinicReportCsvRows(r)));
  };

  return (
    <Page
      title="Reports"
      back="/dashboard"
      maxWidth={ContentWidth.detail}
      actions={
        inBrowser() && report.value != null ? (
          <Button icon="download" onPress={() => exportCsv(report.value!)}>
            CSV
          </Button>
        ) : undefined
      }
    >
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
        {(Object.keys(periodLabel) as Period[]).map((p) => (
          <Chip key={p} mode="outlined" selected={period === p} showSelectedCheck onPress={() => (p === 'custom' ? void pickRange() : setPeriod(p))}>
            {periodLabel[p]}
          </Chip>
        ))}
      </ScrollView>
      <Text style={{ paddingVertical: 8, color: colors.onSurfaceVariant }}>{label}</Text>
      <AsyncView value={report} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['clinicReport'] })}>
        {(r) => (r == null ? null : <ReportBody r={r} />)}
      </AsyncView>
    </Page>
  );
}

export function ReportBody({ r }: { r: ClinicReport }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const [width, onLayout] = useLayoutWidth();
  const paid = readable(invoiceStatusMeta.paid.color);
  const noShow = readable(statusMeta.no_show.color);
  const tiles: TileProps[] = [
    { label: 'Visits', value: String(r.visits), icon: 'event', accent: colors.primary, note: `${r.count('completed')} completed` },
    {
      label: 'No-show rate',
      value: formatRate(r.noShowRate),
      icon: 'event-busy',
      accent: noShow,
      note: `${r.count('no_show')} no-show${r.count('no_show') === 1 ? '' : 's'} · ${r.count('cancelled')} cancelled`,
    },
    { label: 'New patients', value: String(r.newPatients), icon: 'person-add', accent: colors.primary },
    {
      label: 'Billed',
      value: formatPeso(r.billed),
      icon: 'receipt-long',
      accent: colors.primary,
      note: r.discounts > 0 ? `${r.billCount} bills · ${formatPeso(r.discounts)} off` : `${r.billCount} bill${r.billCount === 1 ? '' : 's'}`,
    },
    { label: 'Paid', value: formatPeso(r.paid), icon: 'check-circle-outline', accent: paid, note: 'received in these days' },
  ];
  const columns = width >= 720 ? 5 : width >= 420 ? 3 : 2;
  const gap = 8;
  const tileWidth = (width - gap * (columns - 1)) / columns;
  const twoPane = width >= 840;

  // Too narrow for every column: the names keep their room, Done goes.
  const doctors = <DoctorTable r={r} compact={width < 480} />;
  const services =
    r.byService.length === 0 ? null : (
      <Breakdown title="Billed by service (before discounts)" rows={r.byService.map((s) => [s.name, s.amount] as [string, number])} color={colors.primary} />
    );

  return (
    <View onLayout={onLayout} style={{ gap: 16 }}>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap }}>
        {tiles.map((t) => (
          <View key={t.label} style={{ width: tileWidth }}>
            <Tile {...t} />
          </View>
        ))}
      </View>
      <VisitsChart days={r.byDay} />
      {twoPane ? (
        <View style={{ flexDirection: 'row', gap: 16, alignItems: 'flex-start' }}>
          <View style={{ flex: 1 }}>{doctors}</View>
          <View style={{ flex: 1 }}>{services}</View>
        </View>
      ) : (
        <>
          {doctors}
          {services}
        </>
      )}
    </View>
  );
}

type TileProps = { label: string; value: string; icon: IconName; accent: string; note?: string };

function Tile({ label, value, icon, accent, note }: TileProps) {
  const { colors } = useAppTheme();
  return (
    <View style={{ padding: 12, borderRadius: 14, borderLeftWidth: 4, borderLeftColor: accent, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name={icon} size={16} color={accent} />
        <Text style={{ fontSize: 12, fontWeight: '600', color: colors.onSurfaceVariant }}>{label}</Text>
      </View>
      <Text numberOfLines={1} adjustsFontSizeToFit style={{ marginTop: 6, fontSize: 20, fontWeight: '700' }}>
        {value}
      </Text>
      {note != null && (
        <Text numberOfLines={1} style={{ fontSize: 11, color: colors.onSurfaceVariant }}>
          {note}
        </Text>
      )}
    </View>
  );
}

const chartHeight = 120;

/// Visits per day, one bar each. Hover or tap a bar for that day's figures;
/// with none picked, the busiest day shows.
function VisitsChart({ days }: { days: ReportDay[] }) {
  const { colors } = useAppTheme();
  const [picked, setPicked] = useState<number | null>(null);
  const top = days.reduce((m, d) => Math.max(m, d.visits), 0);
  const busiest = days.reduce((best, d, i) => (d.visits > (days[best]?.visits ?? -1) ? i : best), 0);
  const shown = days[picked ?? busiest];
  // Bars thin out on a long range; the gap between them stays 2px.
  const gap = days.length > 60 ? 1 : 2;
  return (
    <View style={{ padding: 12, borderRadius: 14, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ marginBottom: 8 }}>
        <Text style={{ fontSize: 12, fontWeight: '600', color: colors.onSurfaceVariant }}>Visits per day</Text>
        {shown != null && (
          <Text style={{ marginTop: 2, fontSize: 12, color: colors.onSurfaceVariant }}>
            {`${format(shown.day, 'EEE, MMM d')}${picked == null && top > 0 ? ' (busiest)' : ''}: `}
            <Text style={{ fontWeight: '700', color: colors.onSurface }}>{shown.visits}</Text>
            {` visits · ${shown.completed} done · ${shown.noShows} no-show${shown.noShows === 1 ? '' : 's'} · ${formatPeso(shown.paid)} paid`}
          </Text>
        )}
      </View>
      {top === 0 ? (
        <Text style={{ paddingVertical: 24, textAlign: 'center', color: colors.onSurfaceVariant }}>No visits in these days.</Text>
      ) : (
        <>
          <View style={{ height: chartHeight, flexDirection: 'row', alignItems: 'flex-end', gap, borderBottomWidth: 1, borderBottomColor: colors.outlineVariant }}>
            {days.map((d, i) => (
              <Pressable
                key={d.day.getTime()}
                accessibilityLabel={`${format(d.day, 'MMM d')}: ${d.visits} visits`}
                onPress={() => setPicked(i)}
                onHoverIn={() => setPicked(i)}
                onHoverOut={() => setPicked(null)}
                style={{ flex: 1, height: '100%', justifyContent: 'flex-end' }}
              >
                <View
                  style={{
                    height: d.visits === 0 ? 0 : Math.max(2, (d.visits / top) * chartHeight),
                    borderTopLeftRadius: 4,
                    borderTopRightRadius: 4,
                    backgroundColor: colors.primary,
                    opacity: picked == null || picked === i ? 1 : 0.45,
                  }}
                />
              </Pressable>
            ))}
          </View>
          <View style={{ flexDirection: 'row', marginTop: 4 }}>
            <Text style={{ flex: 1, fontSize: 11, color: colors.onSurfaceVariant }}>{format(days[0].day, 'MMM d')}</Text>
            <Text style={{ fontSize: 11, color: colors.onSurfaceVariant }}>{format(days[days.length - 1].day, 'MMM d')}</Text>
          </View>
        </>
      )}
    </View>
  );
}

function DoctorTable({ r, compact }: { r: ClinicReport; compact: boolean }) {
  const { colors } = useAppTheme();
  const head = { fontSize: 11, fontWeight: '600' as const, color: colors.onSurfaceVariant, textAlign: 'right' as const };
  const cell = { textAlign: 'right' as const };
  return (
    <View style={{ padding: 12, borderRadius: 14, backgroundColor: colors.surfaceContainerLow }}>
      <Text style={{ fontSize: 12, fontWeight: '600', color: colors.onSurfaceVariant, marginBottom: 8 }}>By doctor</Text>
      {r.byDoctor.length === 0 ? (
        <Text style={{ paddingVertical: 8, color: colors.onSurfaceVariant }}>No visits in these days.</Text>
      ) : (
        <>
          <View style={{ flexDirection: 'row', paddingBottom: 4 }}>
            <Text style={[head, { flex: 1, textAlign: 'left' }]}>Doctor</Text>
            <Text style={[head, { width: compact ? 44 : 52 }]}>Visits</Text>
            {!compact && <Text style={[head, { width: 52 }]}>Done</Text>}
            <Text style={[head, { width: 64 }]}>No-show</Text>
            <Text style={[head, { width: 96 }]}>Billed</Text>
          </View>
          {r.byDoctor.map((d) => (
            <View key={d.doctorId} style={{ flexDirection: 'row', paddingVertical: 6, borderTopWidth: 1, borderTopColor: colors.outlineVariant }}>
              <Text numberOfLines={1} style={{ flex: 1 }}>
                {d.name}
              </Text>
              <Text style={[cell, { width: compact ? 44 : 52 }]}>{d.visits}</Text>
              {!compact && <Text style={[cell, { width: 52 }]}>{d.completed}</Text>}
              <Text style={[cell, { width: 64 }]}>{d.noShows}</Text>
              <Text style={[cell, { width: 96, fontWeight: '600' }]}>{formatPeso(d.billed)}</Text>
            </View>
          ))}
        </>
      )}
    </View>
  );
}
