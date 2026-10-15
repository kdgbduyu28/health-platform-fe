import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useRef, useState } from 'react';
import { FlatList, Pressable, ScrollView, View } from 'react-native';
import { Button, Chip, FAB, IconButton, ProgressBar, Text, TextInput, Tooltip } from 'react-native-paper';

import { Breakpoints, ContentWidth, useLayoutWidth, useRailShowsClinic } from '../app/adaptive';
import { registersPatients } from '../models/app_role';
import { formatPeso } from '../models/money';
import {
  type Patient,
  type PatientFlag,
  type PatientListing,
  type PatientPage,
  type PatientSort,
  patientFlagMeta,
  patientFlags,
} from '../models/patient';
import { type PatientTableQuery, defaultPatientTableQuery, usePatientTable } from '../queries/catalog';
import { useAppRole } from '../state/platform';
import { useAppTheme, withAlpha } from '../theme/clinic_theme';
import { AsyncView } from '../ui/async_view';
import { SelectField, TextField } from '../ui/fields';
import { Icon } from '../ui/icon';
import { AppCard, Avatar, MenuButton } from '../ui/kit';
import { BarAction, Page } from '../ui/page';
import { ClinicTitle } from '../widgets/chrome';
import { RemarkChips, remarkColor } from '../widgets/patient_remarks';
import { useRecordVisitSheet } from '../widgets/record_visit_sheet';
import { useAddPatient } from './intake_screens';

const sortLabels: Record<PatientSort, string> = {
  name: 'Name',
  age: 'Age',
  first_visit: 'First visit',
  last_visit: 'Last visit',
  next_visit: 'Next visit',
  visits: 'Visits',
  balance: 'Balance',
};
const sorts = Object.keys(sortLabels) as PatientSort[];

const date = (d: Date | null) => (d == null ? '—' : format(d, 'MMM d, y'));

/// Narrower than this (a tablet held sideways, beside the rail), the table
/// leaves out First visit and tightens the remarks, so every column fits
/// without scrolling sideways.
const tableFullWidth = 1100;

/// Every chart held at the current clinic, as a working list: search, filter
/// by remark (for recall, with balance, no contact info, needs attention,
/// pedia or adult), sort, and page through.
///
/// A sortable table from tablet width up, cards on a phone. The searching,
/// remarks, sorting and paging all happen in the database
/// (`search_patients`), one page at a time, so a clinic with thousands of
/// charts opens as fast as one with ten.
///
/// Shared by the staff apps; each passes [onOpenPatient] to route to its own
/// patient page. [canRecordVisits] adds "Manually add visit", for a visit
/// that happened but was never logged. Every staff app gets "Add patient";
/// [onOpenData] opens the import and export of patients as CSV, which only
/// the front desk and admin apps pass.
export function PatientDirectoryScreen({
  onOpenPatient,
  canRecordVisits = false,
  onOpenData,
}: {
  onOpenPatient: (patient: Patient) => void;
  canRecordVisits?: boolean;
  onOpenData?: () => void;
}) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const app = useAppRole();
  const railShowsClinic = useRailShowsClinic();
  const recordVisit = useRecordVisitSheet();
  const addPatientFlow = useAddPatient();
  const [q, setQ] = useState<PatientTableQuery>(defaultPatientTableQuery);
  const [width, onLayout] = useLayoutWidth();
  const pageAsync = usePatientTable(q);
  /// The page last shown, kept on screen while the next one loads.
  const shown = useRef<PatientPage | null>(null);
  if (pageAsync.value) shown.current = pageAsync.value;
  const page = pageAsync.value ?? shown.current;
  const canRegister = registersPatients(app);
  const searching = q.search.trim() !== '';
  // With the table, "Add patient" sits in the app bar; below that it is a
  // round button sharing the bottom row with the pager.
  const wide = width >= Breakpoints.twoPane;

  /// A new search, filter or sort starts again at page one.
  const set = (next: Partial<PatientTableQuery>) => setQ((prev) => ({ ...prev, ...next, page: 0 }));

  const toggleFilter = (f: PatientFlag) => {
    const next = new Set(q.filters);
    if (next.has(f)) next.delete(f);
    else {
      next.add(f);
      // An age group is one or the other.
      if (f === 'pedia') next.delete('adult');
      if (f === 'adult') next.delete('pedia');
    }
    set({ filters: next });
  };

  const sortBy = (sort: PatientSort) => {
    // Again on the same column flips it. Dates and amounts start with the
    // largest: the latest visit, the biggest balance.
    const descending = sort === q.sort ? !q.descending : sort !== 'name';
    set({ sort, descending });
  };

  const addPatient = async () => {
    const added = await addPatientFlow();
    if (added != null) onOpenPatient(added);
  };

  const summary = (p: PatientPage) => {
    const n = (count: number) => `${count} patient${count === 1 ? '' : 's'}`;
    if (!(searching || q.filters.size > 0) || p.all == null) return n(p.total);
    return `${p.total} of ${n(p.all)}`;
  };

  return (
    <Page
      scroll={false}
      title={
        railShowsClinic ? (
          <Text variant="titleLarge" style={{ fontWeight: '600' }}>
            Patients
          </Text>
        ) : (
          <View>
            <Text variant="labelMedium" style={{ color: colors.onSurfaceVariant }}>
              Patients
            </Text>
            <ClinicTitle markSize={20} />
          </View>
        )
      }
      actions={
        <>
          {canRecordVisits && <BarAction icon="edit-note" label="Manually add visit" onPress={() => void recordVisit()} />}
          {canRegister && onOpenData && <BarAction icon="import-export" label="Import / export" onPress={onOpenData} />}
          <BarAction icon="refresh" label="Refresh" onPress={() => void qc.invalidateQueries({ queryKey: ['patientTable'] })} />
          {canRegister && wide && (
            <Button mode="contained" icon="person-add-alt-1" onPress={addPatient} style={{ marginLeft: 8, marginRight: 16 }}>
              Add patient
            </Button>
          )}
        </>
      }
      fab={canRegister && !wide ? <FAB icon="person-add-alt-1" accessibilityLabel="Add patient" onPress={addPatient} style={{ position: 'absolute', right: 16, bottom: 16 }} /> : undefined}
    >
      <View style={{ flex: 1 }} onLayout={onLayout}>
        <View style={{ width: '100%', maxWidth: ContentWidth.wide + 32, alignSelf: 'center' }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 16, paddingTop: 16, paddingBottom: 4 }}>
            <TextField
              style={{ flex: 1 }}
              icon="search"
              placeholder="Search by name, phone, email or chart no.…"
              value={q.search}
              onChangeText={(v) => set({ search: v })}
              right={q.search === '' ? undefined : <TextInput.Icon icon="clear" accessibilityLabel="Clear" onPress={() => set({ search: '' })} />}
            />
            {/* The table sorts by its headers; a phone, or a tablet whose table
                leaves out a column, also gets a menu. */}
            {(!wide || width - 32 < tableFullWidth) && <SortMenu query={q} onSort={sortBy} />}
          </View>
          <FilterBar
            selected={q.filters}
            counts={page?.counts ?? new Map()}
            onToggle={toggleFilter}
            onClear={q.filters.size === 0 ? undefined : () => set({ filters: new Set() })}
          />
          {page != null && (
            <Text style={{ paddingHorizontal: 20, paddingVertical: 4, fontSize: 12, color: colors.onSurfaceVariant }}>{summary(page)}</Text>
          )}
        </View>
        <View style={{ height: 2 }}>{pageAsync.isLoading && page != null && <ProgressBar indeterminate />}</View>
        <View style={{ flex: 1 }}>
          {page == null ? (
            <AsyncView value={pageAsync} onRetry={() => void qc.invalidateQueries({ queryKey: ['patientTable'] })}>
              {() => null}
            </AsyncView>
          ) : page.patients.length === 0 ? (
            <Text variant="titleMedium" style={{ marginTop: 80, textAlign: 'center' }}>
              {searching ? `No patients match "${q.search.trim()}".` : q.filters.size > 0 ? 'No patients with these remarks.' : 'No patients yet.'}
            </Text>
          ) : wide ? (
            <PatientTable page={page} query={q} width={width} onSort={sortBy} onOpen={onOpenPatient} />
          ) : (
            <FlatList
              data={page.patients}
              keyExtractor={(l) => l.patient.id}
              contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 4, paddingBottom: 8 }}
              ItemSeparatorComponent={() => <View style={{ height: 8 }} />}
              renderItem={({ item }) => <PatientCard listing={item} onPress={() => onOpenPatient(item.patient)} />}
            />
          )}
        </View>
        {page != null && page.total > 0 && (
          <View style={{ width: '100%', maxWidth: ContentWidth.wide + 32, alignSelf: 'center' }}>
            <Pager
              query={q}
              total={page.total}
              // Clear of the round "Add patient" button.
              endPadding={canRegister && !wide ? 80 : 16}
              onPage={(p) => setQ((prev) => ({ ...prev, page: p }))}
              onPageSize={(s) => set({ pageSize: s })}
            />
          </View>
        )}
      </View>
    </Page>
  );
}

// ── Filters, sort, pages ────────────────────────────────────────────────────

function FilterBar({
  selected,
  counts,
  onToggle,
  onClear,
}: {
  selected: ReadonlySet<PatientFlag>;
  counts: ReadonlyMap<PatientFlag, number>;
  onToggle: (flag: PatientFlag) => void;
  onClear?: () => void;
}) {
  const { colors, dark } = useAppTheme();
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, paddingVertical: 4, alignItems: 'center' }}>
      {patientFlags.map((f) => (
        <View key={f} style={{ flexDirection: 'row', alignItems: 'center' }}>
          {f === 'pedia' && <View style={{ width: 1, height: 24, marginHorizontal: 8, backgroundColor: colors.outlineVariant }} />}
          <Chip
            compact
            mode="outlined"
            selected={selected.has(f)}
            showSelectedCheck={false}
            style={{ marginRight: 6, backgroundColor: selected.has(f) ? colors.secondaryContainer : undefined }}
            icon={() => <Icon name={patientFlagMeta[f].icon} size={16} color={remarkColor(f, dark)} />}
            onPress={() => onToggle(f)}
          >
            {counts.get(f) == null ? patientFlagMeta[f].label : `${patientFlagMeta[f].label}  ${counts.get(f)}`}
          </Chip>
        </View>
      ))}
      {onClear && <Button onPress={onClear}>Clear</Button>}
    </ScrollView>
  );
}

function SortMenu({ query, onSort }: { query: PatientTableQuery; onSort: (s: PatientSort) => void }) {
  return (
    <MenuButton
      icon="sort"
      label="Sort"
      items={sorts.map((s) => ({
        label: s === query.sort ? `${sortLabels[s]} ${query.descending ? '↓' : '↑'}` : sortLabels[s],
        icon: s === query.sort ? 'check' : undefined,
        onPress: () => onSort(s),
      }))}
    />
  );
}

function Pager({
  query,
  total,
  onPage,
  onPageSize,
  endPadding = 16,
}: {
  query: PatientTableQuery;
  total: number;
  onPage: (page: number) => void;
  onPageSize: (size: number) => void;
  endPadding?: number;
}) {
  const { colors } = useAppTheme();
  const [width, onLayout] = useLayoutWidth();
  const size = query.pageSize;
  const pages = Math.ceil(total / size);
  const page = Math.min(Math.max(query.page, 0), pages - 1);
  const from = page * size + 1;
  const to = Math.min((page + 1) * size, total);
  // Rows per page and first/last only where they fit.
  const wide = width >= 520;
  const button = (icon: 'first-page' | 'chevron-left' | 'chevron-right' | 'last-page', label: string, enabled: boolean, go: () => void) => (
    <Tooltip title={label}>
      <IconButton icon={icon} accessibilityLabel={label} disabled={!enabled} onPress={go} />
    </Tooltip>
  );
  return (
    <View onLayout={onLayout} style={{ flexDirection: 'row', alignItems: 'center', paddingLeft: 16, paddingRight: endPadding, paddingTop: 4, paddingBottom: 8 }}>
      <Text numberOfLines={1} style={{ flexShrink: 1, fontSize: 13, color: colors.onSurfaceVariant }}>
        {from}–{to} of {total}
      </Text>
      <View style={{ flex: 1 }} />
      {wide && (
        <>
          <Text style={{ fontSize: 13, color: colors.onSurfaceVariant, marginRight: 8 }}>Rows</Text>
          <SelectField
            style={{ width: 96, marginRight: 12 }}
            value={size}
            options={[25, 50, 100].map((s) => ({ value: s, label: `${s}` }))}
            onChange={onPageSize}
          />
          {button('first-page', 'First page', page > 0, () => onPage(0))}
        </>
      )}
      {button('chevron-left', 'Previous page', page > 0, () => onPage(page - 1))}
      <Text style={{ fontWeight: '600' }}>
        {page + 1} / {pages}
      </Text>
      {button('chevron-right', 'Next page', page < pages - 1, () => onPage(page + 1))}
      {wide && button('last-page', 'Last page', page < pages - 1, () => onPage(pages - 1))}
    </View>
  );
}

// ── The table (tablet and up) ───────────────────────────────────────────────

type Column = { label: string; sort: PatientSort | null; numeric: boolean; flex: number };

/// The sort behind each column; null for one that does not sort.
const columns: Column[] = [
  { label: 'Patient', sort: 'name', numeric: false, flex: 2.4 },
  { label: 'Age', sort: 'age', numeric: true, flex: 0.6 },
  { label: 'First visit', sort: 'first_visit', numeric: false, flex: 1 },
  { label: 'Last visit', sort: 'last_visit', numeric: false, flex: 1.7 },
  { label: 'Next visit', sort: 'next_visit', numeric: false, flex: 1 },
  { label: 'Visits', sort: 'visits', numeric: true, flex: 0.6 },
  { label: 'Balance', sort: 'balance', numeric: true, flex: 0.9 },
  { label: 'Remarks', sort: null, numeric: false, flex: 2.4 },
];

function PatientTable({
  page,
  query,
  width,
  onSort,
  onOpen,
}: {
  page: PatientPage;
  query: PatientTableQuery;
  width: number;
  onSort: (s: PatientSort) => void;
  onOpen: (p: Patient) => void;
}) {
  const { colors, dark } = useAppTheme();
  const compact = Math.min(width - 32, ContentWidth.wide) < tableFullWidth;
  const shown = columns.filter((c) => !(compact && c.sort === 'first_visit'));
  const small = { fontSize: 12, color: colors.onSurfaceVariant };

  const cell = (c: Column, l: PatientListing) => {
    const p = l.patient;
    switch (c.sort) {
      case 'name': {
        const contact = p.phone !== '' ? p.phone : p.email;
        return (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
            <Avatar label={p.initials} size={32} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text numberOfLines={1} style={{ fontWeight: '600' }}>
                {p.name}
                {p.chartNumber != null && <Text style={[small, { fontWeight: '400' }]}>{`  ${p.chartNumber}`}</Text>}
              </Text>
              <Text
                numberOfLines={1}
                style={contact === '' ? [small, { color: remarkColor('no_contact', dark), fontStyle: 'italic' }] : small}
              >
                {contact === '' ? 'No contact info' : contact}
              </Text>
            </View>
          </View>
        );
      }
      case 'age':
        return (
          <View style={{ alignItems: 'flex-end' }}>
            <Text>{l.age == null ? '—' : `${l.age}`}</Text>
            {l.flags.has('pedia') && <Text style={[small, { color: remarkColor('pedia', dark) }]}>Pedia</Text>}
          </View>
        );
      case 'first_visit':
        return <Text>{date(l.firstVisitAt)}</Text>;
      case 'last_visit':
        return (
          <View>
            <Text>{date(l.lastVisitAt)}</Text>
            {l.lastVisitMissed ? (
              <Text style={[small, { color: colors.error }]}>Missed last visit</Text>
            ) : l.lastVisitService != null ? (
              <Text numberOfLines={1} style={small}>
                {[l.lastVisitService, ...(l.lastVisitDoctor != null ? [`Dr. ${l.lastVisitDoctor}`] : [])].join(' · ')}
              </Text>
            ) : null}
          </View>
        );
      case 'next_visit':
        return <Text style={l.nextVisitAt == null ? undefined : { color: colors.primary, fontWeight: '600' }}>{date(l.nextVisitAt)}</Text>;
      case 'visits':
        return <Text style={{ textAlign: 'right' }}>{l.completedVisits}</Text>;
      case 'balance':
        return (
          <Text style={[{ textAlign: 'right' }, l.balance > 0 && { color: remarkColor('balance', dark), fontWeight: '700' }]}>
            {l.balance > 0 ? formatPeso(l.balance) : '—'}
          </Text>
        );
      default:
        return <RemarkChips flags={l.flags} attention={l.attention} dense showAgeGroup={false} />;
    }
  };

  return (
    <ScrollView contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 4, paddingBottom: 16 }}>
      <AppCard style={{ width: '100%', maxWidth: ContentWidth.wide, alignSelf: 'center' }}>
        <View style={{ flexDirection: 'row', backgroundColor: colors.surfaceContainerHighest, paddingHorizontal: 16, gap: compact ? 16 : 20 }}>
          {shown.map((c) => {
            const active = c.sort != null && c.sort === query.sort;
            const content = (
              <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: c.numeric ? 'flex-end' : 'flex-start', gap: 4, height: 56 }}>
                {active && c.numeric && <Icon name={query.descending ? 'arrow-downward' : 'arrow-upward'} size={16} color={colors.onSurface} />}
                <Text variant="labelMedium" style={{ fontWeight: '700', color: active ? colors.onSurface : colors.onSurfaceVariant }}>
                  {c.label}
                </Text>
                {active && !c.numeric && <Icon name={query.descending ? 'arrow-downward' : 'arrow-upward'} size={16} color={colors.onSurface} />}
              </View>
            );
            return (
              <View key={c.label} style={{ flex: c.flex, minWidth: 0 }}>
                {c.sort == null ? content : <Pressable onPress={() => onSort(c.sort!)}>{content}</Pressable>}
              </View>
            );
          })}
        </View>
        {page.patients.map((l, i) => (
          <Pressable
            key={l.patient.id}
            onPress={() => onOpen(l.patient)}
            style={({ hovered }) => ({
              flexDirection: 'row',
              alignItems: 'center',
              minHeight: 60,
              paddingVertical: 8,
              paddingHorizontal: 16,
              gap: compact ? 16 : 20,
              borderTopWidth: i === 0 ? 0 : 1,
              borderTopColor: colors.outlineVariant,
              backgroundColor: hovered ? withAlpha(colors.onSurface, 0.04) : undefined,
            })}
          >
            {shown.map((c) => (
              <View key={c.label} style={{ flex: c.flex, minWidth: 0 }}>
                {cell(c, l)}
              </View>
            ))}
          </Pressable>
        ))}
      </AppCard>
    </ScrollView>
  );
}

// ── Cards (phone) ───────────────────────────────────────────────────────────

function PatientCard({ listing: l, onPress }: { listing: PatientListing; onPress: () => void }) {
  const { colors, dark } = useAppTheme();
  const p = l.patient;
  const small = { fontSize: 12.5, color: colors.onSurfaceVariant };
  return (
    <AppCard onPress={onPress} padding={14}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
        <Avatar label={p.initials} />
        <View style={{ flex: 1 }}>
          <Text style={{ fontWeight: '600', fontSize: 15 }}>{[p.name, ...(l.age != null ? [`${l.age}`] : [])].join(', ')}</Text>
          <Text style={small}>{p.phone !== '' ? p.phone : p.email !== '' ? p.email : 'No contact info'}</Text>
        </View>
        <View style={{ alignItems: 'flex-end' }}>
          {l.balance > 0 && <Text style={{ fontWeight: '700', color: remarkColor('balance', dark) }}>{formatPeso(l.balance)}</Text>}
          <Text style={small}>
            {l.completedVisits} visit{l.completedVisits === 1 ? '' : 's'}
          </Text>
        </View>
      </View>
      <Text style={[small, { marginTop: 10 }]}>
        {[
          `Last ${date(l.lastVisitAt)}${l.lastVisitMissed ? ' (missed)' : ''}`,
          ...(l.nextVisitAt != null ? [`Next ${date(l.nextVisitAt)}`] : []),
          ...(l.firstVisitAt != null ? [`Since ${format(l.firstVisitAt, 'MMM y')}`] : []),
        ].join(' · ')}
      </Text>
      {l.flags.size > 0 && (
        <View style={{ marginTop: 8 }}>
          <RemarkChips flags={l.flags} attention={l.attention} dense />
        </View>
      )}
    </AppCard>
  );
}
