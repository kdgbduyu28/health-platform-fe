import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { type ReactNode, useEffect, useMemo, useState } from 'react';
import { View } from 'react-native';
import { Button, IconButton, ProgressBar, SegmentedButtons, Text } from 'react-native-paper';

import { ContentWidth, useLayoutWidth } from '../app/adaptive';
import { toothNumberingLabel, type ToothNumbering } from '../models/dental_chart';
import { type ImportKind, type ImportMatch, type ImportOutcome, type ImportRowResult, importKindCount, importKindMeta } from '../models/data_import';
import type { Doctor } from '../models/doctor';
import { refreshAppointments } from '../queries/appointments';
import { useRoster } from '../queries/catalog';
import { useCurrentClinicId } from '../queries/clinic';
import { useCanSeeClinicalNotes, useCurrentClinicRole } from '../queries/clinical';
import { downloadTextFile } from '../platform/browser';
import { useRepository } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { SelectField } from '../ui/fields';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, MenuButton } from '../ui/kit';
import { type Close, useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { toCsv } from '../import_export/csv';
import { type DateOrder, type ImportColumn, type ImportRow, cleanCell, dateOrderLabel } from '../import_export/import_common';
import type { ImportSettings, ImportSpec } from '../import_export/import_spec';
import { matchDoctor } from '../import_export/visit_columns';

type Step = 'columns' | 'checking' | 'review' | 'importing' | 'done';

/// What to do with a row that looks like a patient already here.
type Decision = 'update' | 'create' | 'skip';
const decisionLabel: Record<Decision, string> = { update: 'Update', create: 'Add as new', skip: 'Skip' };

/// Rows per call: well inside the database's 500, and a few seconds' work.
const chunk = 200;

const stepTitle: Record<Step, string> = {
  columns: 'Import · match the columns',
  checking: 'Import · checking',
  review: 'Import · review',
  importing: 'Importing…',
  done: 'Import finished',
};

function count(results: ReadonlyMap<number, ImportRowResult>, o: ImportOutcome): number {
  let n = 0;
  for (const r of results.values()) if (r.outcome === o) n++;
  return n;
}

/// Importing one CSV file — patients, visits or a dental chart — start to
/// finish:
///
///   columns    which of the file's columns is which (matched from the
///              headers; the person fixes the rest), how it writes dates and
///              tooth numbers, and which roster doctor each name means
///   check      a dry run of every row against the database
///   review     what will happen: new, updated, already on file, problems,
///              and (patients) possible duplicates, each to be updated, added
///              as new, or skipped
///   import     the real run, a chunk at a time
///   done       the tally, the rows that failed as a file, and Undo
export function ImportFlow({ spec, fileName, rows, close }: { spec: ImportSpec; fileName: string; rows: string[][]; close: Close<void> }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const clinicId = useCurrentClinicId();
  const seesNotes = useCanSeeClinicalNotes().value ?? false;
  const role = useCurrentClinicRole().value;
  const roster = useRoster();
  const kind = spec.kind;
  const headers = rows[0];
  const body = useMemo(() => rows.slice(1), [rows]);

  const [columns, setColumns] = useState<(ImportColumn | null)[]>(() => spec.match(headers));
  const [dateOrder, setDateOrder] = useState<DateOrder>('month_first');
  const [numbering, setNumbering] = useState<ToothNumbering>('fdi');
  /// Visits: the roster doctor picked for each doctor name in the file.
  const [doctorPicks, setDoctorPicks] = useState<Map<string, string>>(new Map());
  const [step, setStep] = useState<Step>('columns');
  const [done, setDone] = useState(0);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState<unknown>(null);
  const [parsed, setParsed] = useState<ImportRow[]>([]);
  const [check, setCheck] = useState<Map<number, ImportRowResult>>(new Map());
  const [decisions, setDecisions] = useState<Map<number, Decision>>(new Map());
  const [batchId, setBatchId] = useState<string | null>(null);
  const [results, setResults] = useState<Map<number, ImportRowResult>>(new Map());
  const [undone, setUndone] = useState(false);

  /// Each doctor name in the file (cleaned), with how many rows use it.
  const doctorNames = useMemo(() => {
    const i = spec.doctorColumn == null ? -1 : columns.indexOf(spec.doctorColumn);
    const out = new Map<string, number>();
    if (i < 0) return out;
    for (const r of body) {
      const name = i < r.length ? cleanCell(r[i]) : '';
      out.set(name, (out.get(name) ?? 0) + 1);
    }
    return out;
  }, [spec, columns, body]);

  /// Names the file's doctors after the roster, where they plainly match.
  useEffect(() => {
    const list = roster.value;
    if (list == null || doctorNames.size === 0) return;
    const byName = new Map(list.map((d) => [d.name, d.id]));
    const active = list.filter((d) => d.isActive);
    let changed = false;
    const next = new Map(doctorPicks);
    for (const name of doctorNames.keys()) {
      if (next.has(name)) continue;
      const id = name === '' ? (active.length === 1 ? active[0].id : null) : matchDoctor(name, byName);
      if (id != null) {
        next.set(name, id);
        changed = true;
      }
    }
    if (changed) setDoctorPicks(next);
  }, [roster.value, doctorNames, doctorPicks]);

  /// Why the check cannot run yet, or null.
  const missing = (() => {
    const m = spec.missing(columns);
    if (m != null) return m;
    if (spec.doctorColumn != null) {
      if (!columns.includes(spec.doctorColumn)) return 'Pick the column with the doctor.';
      if ([...doctorNames.keys()].some((n) => !doctorPicks.has(n))) return 'Match every doctor in the file to one on the roster.';
    }
    return null;
  })();

  const settings: ImportSettings = { dateOrder, numbering, doctors: doctorPicks };

  /// What an import changed, shown again wherever it is listed.
  const refresh = () => {
    void qc.invalidateQueries({ queryKey: ['patientTable'] });
    if (kind === 'visits') void refreshAppointments(qc);
  };

  /// The same patient twice in one file (same chart number, or same name
  /// and phone or birthday) is a mistake to fix in the file, not something
  /// to import twice: the later rows are held back.
  const markRepeats = (list: ImportRow[]) => {
    const seen = new Map<string, number>();
    for (const r of list) {
      if (!r.ok) continue;
      const keys = spec.sameRecordKeys(r);
      const first = keys.map((k) => seen.get(k)).find((v) => v != null);
      if (first != null) r.errors.push(`The same patient as row ${first} of this file.`);
      else for (const k of keys) seen.set(k, r.row);
    }
  };

  const runCheck = async () => {
    const list = body.map((cells, i) => spec.read(cells, columns, i + 2, settings));
    markRepeats(list);
    const sendable = list.filter((r) => r.ok);
    setParsed(list);
    setStep('checking');
    setDone(0);
    setTotal(sendable.length);
    setError(null);
    try {
      const out = new Map<number, ImportRowResult>();
      for (let i = 0; i < sendable.length; i += chunk) {
        const part = sendable.slice(i, i + chunk);
        for (const r of await repo.importRows({ kind, clinicId: clinicId!, rows: part.map((r) => r.json) })) out.set(r.row, r);
        setDone(i + part.length);
      }
      setDecisions(new Map([...out.values()].filter((r) => r.outcome === 'duplicate').map((r) => [r.row, 'update' as Decision])));
      setCheck(out);
      setStep('review');
    } catch (e) {
      setError(e);
      setStep('columns');
    }
  };

  const toSend = parsed
    .filter((r) => r.ok && check.get(r.row)?.outcome !== 'error')
    .map((r) => {
      switch (decisions.get(r.row)) {
        case 'update':
          return { ...r.json, action: 'update', match_id: check.get(r.row)!.match!.id };
        case 'create':
          return { ...r.json, action: 'create' };
        case 'skip':
          return { row: r.row, action: 'skip' };
        default:
          return r.json;
      }
    });
  const importCount = toSend.filter((r) => r.action !== 'skip').length;

  const runImport = async () => {
    const list = toSend;
    setStep('importing');
    setDone(0);
    setTotal(list.length);
    setError(null);
    const out = new Map<number, ImportRowResult>();
    try {
      const batch = batchId ?? (await repo.startImport({ clinicId: clinicId!, fileName, kind }));
      setBatchId(batch);
      for (let i = 0; i < list.length; i += chunk) {
        const part = list.slice(i, i + chunk);
        for (const r of await repo.importRows({ kind, clinicId: clinicId!, rows: part, batchId: batch })) out.set(r.row, r);
        setDone(i + part.length);
      }
      refresh();
    } catch (e) {
      // Chunks already in stay in; say how far it got.
      setError(e);
    }
    setResults(out);
    setStep('done');
  };

  const undo = async () => {
    if (!(await confirmUndoImport(overlay, kind, count(results, 'created'), count(results, 'updated')))) return;
    try {
      const r = await repo.undoImport(batchId!);
      overlay.snack(undoneMessage(kind, r.removed));
      refresh();
      setUndone(true);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  /// The rows that did not go in, as the file had them plus why, to fix and
  /// import again.
  const downloadProblems = (problems: [ImportRow, string][]) => {
    const base = fileName.replace(/\.csv$/i, '');
    downloadTextFile(
      `${base}-problems.csv`,
      'text/csv',
      toCsv([
        [...headers, 'Problem'],
        ...problems.map(([row, why]) => [...row.cells, ...Array(Math.max(0, headers.length - row.cells.length)).fill(''), why]),
      ]),
    );
  };

  const addFormerDoctor = async (name: string) => {
    try {
      const id = await repo.addFormerDoctor(clinicId!, name);
      void qc.invalidateQueries({ queryKey: ['roster'] });
      void qc.invalidateQueries({ queryKey: ['doctors'] });
      setDoctorPicks((m) => new Map(m).set(name, id));
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  const busy = step === 'checking' || step === 'importing';

  const bottom = (children: ReactNode) => (
    <View style={{ backgroundColor: colors.surfaceContainer, paddingHorizontal: 16, paddingVertical: 12, boxShadow: '0 -1px 4px rgba(0,0,0,0.12)' } as never}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, width: '100%', maxWidth: ContentWidth.list, alignSelf: 'center' }}>{children}</View>
    </View>
  );

  return (
    <Page
      title={stepTitle[step]}
      back={busy ? false : undefined}
      onBack={busy ? undefined : () => close()}
      maxWidth={ContentWidth.list}
      scroll={!busy}
      footer={
        step === 'columns'
          ? bottom(
              <>
                <Text style={{ flex: 1 }}>{missing ?? ''}</Text>
                <Button mode="contained" disabled={missing != null} onPress={() => void runCheck()}>
                  Check {body.length} {body.length === 1 ? 'row' : 'rows'}
                </Button>
              </>,
            )
          : step === 'review'
            ? bottom(
                <>
                  <Button onPress={() => setStep('columns')}>Back to columns</Button>
                  <View style={{ flex: 1 }} />
                  <Button mode="contained" disabled={importCount === 0} onPress={() => void runImport()}>
                    Import {importKindCount(kind, importCount)}
                  </Button>
                </>,
              )
            : step === 'done'
              ? bottom(
                  <>
                    {batchId != null && !undone && count(results, 'created') > 0 && (
                      <Button icon="undo" onPress={() => void undo()}>
                        Undo this import
                      </Button>
                    )}
                    <View style={{ flex: 1 }} />
                    <Button mode="contained" onPress={() => close()}>
                      Done
                    </Button>
                  </>,
                )
              : undefined
      }
    >
      {busy ? (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 32 }}>
          <View style={{ width: 320 }}>
            <ProgressBar progress={total === 0 ? undefined : done / total} indeterminate={total === 0} />
          </View>
          <Text style={{ marginTop: 16 }}>{step === 'checking' ? `Checking row ${done} of ${total}…` : `Imported ${done} of ${total}…`}</Text>
          <Text style={{ marginTop: 4, color: colors.onSurfaceVariant }}>Keep this page open.</Text>
        </View>
      ) : step === 'columns' ? (
        <ColumnsStep
          spec={spec}
          fileName={fileName}
          headers={headers}
          body={body}
          columns={columns}
          setColumns={setColumns}
          dateOrder={dateOrder}
          setDateOrder={setDateOrder}
          numbering={numbering}
          setNumbering={setNumbering}
          error={error}
          seesNotes={seesNotes}
          doctorNames={doctorNames}
          roster={roster}
          doctorPicks={doctorPicks}
          canAddDoctor={role === 'admin'}
          onPickDoctor={(name, id) => setDoctorPicks((m) => new Map(m).set(name, id))}
          onAddDoctor={(name) => void addFormerDoctor(name)}
          onRetryRoster={() => void qc.invalidateQueries({ queryKey: ['roster'] })}
        />
      ) : step === 'review' ? (
        <ReviewStep
          kind={kind}
          parsed={parsed}
          check={check}
          decisions={decisions}
          setDecision={(row, d) => setDecisions((m) => new Map(m).set(row, d))}
          setAll={(rowsToSet, d) =>
            setDecisions((m) => {
              const next = new Map(m);
              for (const r of rowsToSet) next.set(r, d);
              return next;
            })
          }
          onDownload={downloadProblems}
        />
      ) : (
        <DoneStep parsed={parsed} check={check} results={results} error={error} undone={undone} onDownload={downloadProblems} />
      )}
    </Page>
  );
}

function Banner({ color, text }: { color: string; text: string }) {
  return (
    <View style={{ padding: 12, borderRadius: 12, backgroundColor: color }}>
      <Text>{text}</Text>
    </View>
  );
}

function Stat({ label, value, icon, color }: { label: string; value: number; icon: IconName; color?: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ minWidth: 150, padding: 12, borderRadius: 12, borderWidth: 1, borderColor: colors.outlineVariant }}>
      <Icon name={icon} size={20} color={color ?? colors.onSurface} />
      <Text variant="headlineSmall" style={{ marginTop: 4, color }}>
        {value}
      </Text>
      <Text variant="bodySmall">{label}</Text>
    </View>
  );
}

function ColumnsStep(p: {
  spec: ImportSpec;
  fileName: string;
  headers: string[];
  body: string[][];
  columns: (ImportColumn | null)[];
  setColumns: (c: (ImportColumn | null)[]) => void;
  dateOrder: DateOrder;
  setDateOrder: (o: DateOrder) => void;
  numbering: ToothNumbering;
  setNumbering: (n: ToothNumbering) => void;
  error: unknown;
  seesNotes: boolean;
  doctorNames: Map<string, number>;
  roster: ReturnType<typeof useRoster>;
  doctorPicks: Map<string, string>;
  canAddDoctor: boolean;
  onPickDoctor: (name: string, id: string) => void;
  onAddDoctor: (name: string) => void;
  onRetryRoster: () => void;
}) {
  const { colors } = useAppTheme();
  const { spec, headers, body, columns } = p;
  const hasDates = columns.some((c) => c != null && spec.dateColumns.has(c));
  const notes = columns.filter((c): c is ImportColumn => c != null && spec.clinicianColumns.has(c)).map((c) => c.header);
  /// The first few values in column [i], to recognise it by.
  const example = (i: number) =>
    body
      .slice(0, 20)
      .map((r) => (i < r.length ? r[i].trim() : ''))
      .filter((v) => v !== '')
      .slice(0, 2)
      .join(' · ');

  return (
    <View>
      <Text variant="titleMedium">
        {importKindMeta[spec.kind].label} · {p.fileName}
      </Text>
      <Text>
        {body.length} {body.length === 1 ? 'row' : 'rows'} · {headers.length} columns
      </Text>
      {p.error != null && (
        <View style={{ marginTop: 12 }}>
          <Banner color={colors.errorContainer} text={`The check stopped: ${describeError(p.error)}`} />
        </View>
      )}
      <Text style={{ marginTop: 16 }}>Each column of your file, and what it holds here. Columns set to "Don't import" are left out.</Text>
      {hasDates && (
        <SelectField
          style={{ marginTop: 16 }}
          label="How the file writes dates"
          value={p.dateOrder}
          options={(['month_first', 'day_first'] as const).map((o) => ({ value: o, label: dateOrderLabel[o] }))}
          onChange={p.setDateOrder}
        />
      )}
      {spec.asksNumbering && (
        <SelectField
          style={{ marginTop: 16 }}
          label="How the file numbers teeth"
          value={p.numbering}
          options={[
            { value: 'fdi', label: `${toothNumberingLabel.fdi} (11–48, baby teeth 51–85)` },
            { value: 'universal', label: `${toothNumberingLabel.universal} (1–32, baby teeth A–T)` },
          ]}
          onChange={p.setNumbering}
        />
      )}
      {notes.length > 0 && !p.seesNotes && (
        <View style={{ marginTop: 12 }}>
          <Banner color={colors.secondaryContainer} text={`${notes.join(' and ')} will be left out: only doctors and admins can import them.`} />
        </View>
      )}
      {spec.doctorColumn != null && p.doctorNames.size > 0 && (
        <View style={{ marginTop: 16 }}>
          <AsyncView value={p.roster} padded onRetry={p.onRetryRoster}>
            {(r) => (
              <DoctorsCard names={p.doctorNames} roster={r} picks={p.doctorPicks} canAdd={p.canAddDoctor} onPick={p.onPickDoctor} onAdd={p.onAddDoctor} />
            )}
          </AsyncView>
        </View>
      )}
      <AppCard style={{ marginTop: 12 }}>
        {headers.map((h, i) => (
          <ColumnTile
            key={i}
            options={spec.columns}
            header={h}
            example={example(i)}
            value={columns[i]}
            onChange={(c) => p.setColumns(columns.map((x, j) => (j === i ? c : c != null && x === c ? null : x)))}
          />
        ))}
      </AppCard>
    </View>
  );
}

function ColumnTile({
  options,
  header,
  example,
  value,
  onChange,
}: {
  options: readonly ImportColumn[];
  header: string;
  example: string;
  value: ImportColumn | null;
  onChange: (c: ImportColumn | null) => void;
}) {
  const { colors } = useAppTheme();
  const [width, onLayout] = useLayoutWidth();
  const picker = (
    <SelectField
      value={value == null ? -1 : options.indexOf(value)}
      options={[{ value: -1, label: "Don't import" }, ...options.map((c, i) => ({ value: i, label: c.header }))]}
      onChange={(i) => onChange(i === -1 ? null : options[i])}
    />
  );
  const label = (
    <View style={{ flex: 1, minWidth: 0 }}>
      <Text style={{ fontWeight: '600' }}>{header === '' ? '(no header)' : header}</Text>
      {example !== '' && (
        <Text numberOfLines={1} style={{ color: colors.onSurfaceVariant, fontSize: 13 }}>
          {example}
        </Text>
      )}
      {value != null && <Text style={{ color: colors.onSurfaceVariant, fontSize: 12 }}>{value.hint}</Text>}
    </View>
  );
  return (
    <View onLayout={onLayout} style={{ paddingHorizontal: 16, paddingVertical: 8 }}>
      {width >= 520 ? (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16 }}>
          {label}
          <View style={{ width: 240 }}>{picker}</View>
        </View>
      ) : (
        <View style={{ gap: 4 }}>
          {label}
          {picker}
        </View>
      )}
    </View>
  );
}

/// Each doctor name in a visits file, and the roster doctor it means. An
/// admin can put someone who has left on the roster, inactive, for their
/// visits.
function DoctorsCard({
  names,
  roster,
  picks,
  canAdd,
  onPick,
  onAdd,
}: {
  names: Map<string, number>;
  roster: Doctor[];
  picks: Map<string, string>;
  canAdd: boolean;
  onPick: (name: string, id: string) => void;
  onAdd: (name: string) => void;
}) {
  const { colors } = useAppTheme();
  return (
    <AppCard padding={16}>
      <Text variant="titleSmall">Doctors in this file</Text>
      <Text variant="bodySmall" style={{ marginTop: 4, color: colors.onSurfaceVariant }}>
        {canAdd
          ? 'Match each to the roster. Someone who has left can be added as a former doctor: kept for their visits, never booked.'
          : 'Match each to the roster. An admin can add a doctor who has left.'}
      </Text>
      {[...names.entries()].map(([name, n]) => (
        <View key={name} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 8 }}>
          <Text style={{ flex: 1, fontWeight: '600', color: picks.has(name) ? undefined : colors.error }}>
            {name === '' ? '(no doctor given)' : name} · {n} {n === 1 ? 'row' : 'rows'}
          </Text>
          <SelectField
            style={{ width: 240 }}
            value={picks.get(name) ?? null}
            placeholder="Pick a doctor"
            options={roster.map((d) => ({ value: d.id, label: d.isActive ? d.name : `${d.name} (inactive)` }))}
            onChange={(id) => onPick(name, id)}
          />
          {canAdd && name !== '' && !picks.has(name) && <IconButton icon="person-add-alt" accessibilityLabel="Add as a former doctor" onPress={() => onAdd(name)} />}
        </View>
      ))}
    </AppCard>
  );
}

function ReviewStep({
  kind,
  parsed,
  check,
  decisions,
  setDecision,
  setAll,
  onDownload,
}: {
  kind: ImportKind;
  parsed: ImportRow[];
  check: Map<number, ImportRowResult>;
  decisions: Map<number, Decision>;
  setDecision: (row: number, d: Decision) => void;
  setAll: (rows: number[], d: Decision) => void;
  onDownload: (problems: [ImportRow, string][]) => void;
}) {
  const { colors } = useAppTheme();
  const [showWarned, setShowWarned] = useState(false);
  const problems: [ImportRow, string][] = [];
  for (const r of parsed) {
    if (!r.ok) problems.push([r, r.errors.join(' ')]);
    else if (check.get(r.row)?.outcome === 'error') problems.push([r, check.get(r.row)!.message ?? 'Could not be imported.']);
  }
  const dupes = parsed.filter((r) => check.get(r.row)?.outcome === 'duplicate');
  const warned: [ImportRow, string][] = [];
  for (const r of parsed) {
    if (!r.ok || check.get(r.row)?.outcome === 'error') continue;
    const w = [...new Set([...r.warnings, ...(check.get(r.row)?.warnings ?? [])])];
    if (w.length > 0) warned.push([r, w.join(' ')]);
  }
  const patients = kind === 'patients';
  return (
    <View>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        <Stat label={`New ${importKindMeta[kind].many}`} value={count(check, 'created')} icon="add-circle-outline" />
        {patients ? (
          <>
            <Stat label="Already here, updated" value={count(check, 'updated')} icon="edit" />
            <Stat label="Look like patients here" value={dupes.length} icon="people-outline" />
          </>
        ) : (
          <Stat label="Already on file" value={count(check, 'skipped')} icon="inventory-2" />
        )}
        <Stat label="Problems" value={problems.length} icon="error-outline" color={problems.length === 0 ? undefined : colors.error} />
      </View>
      <Text variant="bodySmall" style={{ marginTop: 8, color: colors.onSurfaceVariant }}>
        {patients
          ? 'Nothing has been saved yet. An update fills in what the file has and keeps what is on file where the file is blank.'
          : 'Nothing has been saved yet. What is already on file is left as it is.'}
      </Text>
      {dupes.length > 0 && (
        <View style={{ marginTop: 24 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Text variant="titleMedium" style={{ flex: 1 }}>
              Look like patients already here
            </Text>
            <MenuButton
              label="Set all"
              anchor={(open) => <Button onPress={open}>Set all…</Button>}
              items={(['update', 'create', 'skip'] as const).map((d) => ({
                label: `${decisionLabel[d]}: all`,
                onPress: () => setAll(dupes.map((r) => r.row), d),
              }))}
            />
          </View>
          {dupes.slice(0, 200).map((r) => (
            <DuplicateCard key={r.row} row={r} match={check.get(r.row)!.match!} decision={decisions.get(r.row) ?? 'update'} onChange={(d) => setDecision(r.row, d)} />
          ))}
          {dupes.length > 200 && <Text>…and {dupes.length - 200} more, set with "Set all".</Text>}
        </View>
      )}
      {problems.length > 0 && (
        <View style={{ marginTop: 24 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Text variant="titleMedium" style={{ flex: 1 }}>
              Problems (not imported)
            </Text>
            <Button icon="download" onPress={() => onDownload(problems)}>
              Download
            </Button>
          </View>
          <RowList items={problems} color={colors.error} />
        </View>
      )}
      {warned.length > 0 && (
        <View style={{ marginTop: 24 }}>
          <Button
            icon={showWarned ? 'expand-less' : 'expand-more'}
            onPress={() => setShowWarned((s) => !s)}
            contentStyle={{ flexDirection: 'row-reverse', justifyContent: 'space-between' }}
            style={{ alignSelf: 'stretch' }}
          >
            {`Imported, with a note (${warned.length})`}
          </Button>
          {showWarned && <RowList items={warned} />}
        </View>
      )}
    </View>
  );
}

function DoneStep({
  parsed,
  check,
  results,
  error,
  undone,
  onDownload,
}: {
  parsed: ImportRow[];
  check: Map<number, ImportRowResult>;
  results: Map<number, ImportRowResult>;
  error: unknown;
  undone: boolean;
  onDownload: (problems: [ImportRow, string][]) => void;
}) {
  const { colors } = useAppTheme();
  const failed: [ImportRow, string][] = [];
  for (const r of parsed) {
    const res = results.get(r.row);
    if (!r.ok) failed.push([r, r.errors.join(' ')]);
    else if (check.get(r.row)?.outcome === 'error') failed.push([r, check.get(r.row)!.message ?? 'Could not be imported.']);
    else if (res != null && (res.outcome === 'error' || res.outcome === 'duplicate')) failed.push([r, res.message ?? 'Could not be imported.']);
  }
  return (
    <View style={{ gap: 8 }}>
      {error != null && (
        <Banner
          color={colors.errorContainer}
          text={`The import stopped part-way: ${describeError(error)} What is counted below went in. To finish, import the same file again: the patients already in show up as matches, to update or skip.`}
        />
      )}
      {undone && <Banner color={colors.secondaryContainer} text="This import was undone." />}
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        <Stat label="Added" value={count(results, 'created')} icon="person-add-alt" />
        <Stat label="Updated" value={count(results, 'updated')} icon="edit" />
        <Stat label="Skipped" value={count(results, 'skipped')} icon="redo" />
        <Stat label="Not imported" value={failed.length} icon="error-outline" color={failed.length === 0 ? undefined : colors.error} />
      </View>
      {failed.length > 0 && (
        <View style={{ marginTop: 16 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Text variant="titleMedium" style={{ flex: 1 }}>
              Not imported
            </Text>
            <Button icon="download" onPress={() => onDownload(failed)}>
              Download to fix
            </Button>
          </View>
          <RowList items={failed} color={colors.error} />
        </View>
      )}
    </View>
  );
}

function DuplicateCard({ row, match, decision, onChange }: { row: ImportRow; match: ImportMatch; decision: Decision; onChange: (d: Decision) => void }) {
  const { colors } = useAppTheme();
  const person = row.json.person as Record<string, any>;
  const line = (name: string, phone?: string | null, born?: string | null, chart?: string | null) =>
    [name, ...(phone ? [phone] : []), ...(born != null ? [`born ${born}`] : []), ...(chart != null ? [`chart ${chart}`] : [])].join(' · ');
  return (
    <AppCard padding={12} style={{ marginBottom: 8 }}>
      <Text>
        Row {row.row}: {line(row.name, person.phone, person.date_of_birth, row.json.chart_number)}
      </Text>
      <Text style={{ color: colors.onSurfaceVariant }}>
        On file: {line(match.name, match.phone, match.dateOfBirth == null ? null : format(match.dateOfBirth, 'yyyy-MM-dd'), match.chartNumber)}
      </Text>
      <SegmentedButtons
        style={{ marginTop: 8 }}
        value={decision}
        onValueChange={(v) => onChange(v as Decision)}
        buttons={(['update', 'create', 'skip'] as const).map((d) => ({ value: d, label: decisionLabel[d] }))}
      />
    </AppCard>
  );
}

/// Rows with a message each; the first 200, the rest in the download.
function RowList({ items, color }: { items: [ImportRow, string][]; color?: string }) {
  const { colors } = useAppTheme();
  return (
    <View>
      {items.slice(0, 200).map(([row, why]) => (
        <View key={row.row} style={{ flexDirection: 'row', alignItems: 'flex-start', paddingVertical: 4 }}>
          <Text style={{ width: 64, color: colors.onSurfaceVariant, fontSize: 13 }}>Row {row.row}</Text>
          <View style={{ flex: 1 }}>
            <Text style={{ fontWeight: '600' }}>{row.name === '' ? '(no name)' : row.name}</Text>
            <Text style={{ color, fontSize: 13 }}>{why}</Text>
          </View>
        </View>
      ))}
      {items.length > 200 && <Text>…and {items.length - 200} more in the download.</Text>}
    </View>
  );
}

/// Asks before undoing an import, saying what it removes and what stays.
export function confirmUndoImport(overlay: ReturnType<typeof useOverlay>, kind: ImportKind, added: number, updated: number): Promise<boolean> {
  const what =
    kind === 'patients'
      ? `This removes the ${importKindCount(kind, added)} it added, with their forms, notes and opening balances. It only works if none of them has had a visit, bill or payment since.${
          updated === 0 ? '' : `\n\nThe ${importKindCount(kind, updated)} it updated keep the changes.`
        }`
      : kind === 'visits'
        ? `This removes the ${importKindCount(kind, added)} it added, with their notes. It only works if none of them has been changed, billed or charted since.`
        : `This removes the ${importKindCount(kind, added)} it added. It only works if none of them has been changed since.`;
  return overlay.confirm({ title: 'Undo this import?', message: what, cancelLabel: 'Keep', confirmLabel: 'Undo import' });
}

export function undoneMessage(kind: ImportKind, removed: number): string {
  return `Import undone: ${importKindCount(kind, removed)} removed.`;
}

