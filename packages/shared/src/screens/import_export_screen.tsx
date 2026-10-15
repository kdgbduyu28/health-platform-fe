import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { type ReactNode, useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, SegmentedButtons, Text } from 'react-native-paper';

import { ContentWidth } from '../app/adaptive';
import { toCsv, parseCsv } from '../import_export/csv';
import { exportLayout, importSpecOf } from '../import_export/import_spec';
import { type ImportBatch, type ImportKind, importKindCount, importKindMeta } from '../models/data_import';
import { downloadTextFile, pickTextFile } from '../platform/browser';
import { useCurrentClinic } from '../queries/clinic';
import { useCanSeeClinicalNotes, useCurrentClinicRole } from '../queries/clinical';
import { useImportBatches } from '../queries/misc';
import { useCurrentUserId, useRepository } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, ListTile } from '../ui/kit';
import { useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { ImportFlow, confirmUndoImport, undoneMessage } from './import_flow';

/// The clinic's records in and out as spreadsheets, for the front desk and
/// admins: patients, their visit history, and (at a dental clinic) their
/// dental charts. Export to CSV; import a CSV (the clinic's old records, or
/// an export edited in Excel); undo a recent import.
///
/// Clinical notes follow the usual rule: only doctors and admins export or
/// import them. The dental chart is clinical, so only they import it; the
/// front desk, who read it, may export it.
export function ImportExportScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const clinic = useCurrentClinic().value ?? null;
  const notes = useCanSeeClinicalNotes();
  const clinician = notes.value ?? false;
  const batches = useImportBatches();
  const [chosen, setKind] = useState<ImportKind>('patients');
  /// Rows fetched so far while exporting; null when not exporting.
  const [exported, setExported] = useState<number | null>(null);
  const dental = clinic?.chartKind === 'dental';
  const kinds: ImportKind[] = ['patients', 'visits', ...(dental ? (['dental'] as const) : [])];
  const kind = kinds.includes(chosen) ? chosen : 'patients';
  const exporting = exported != null;
  const canImport = kind !== 'dental' || clinician;
  const meta = importKindMeta[kind];

  const doExport = async () => {
    if (clinic == null) return;
    const withNotes = clinician;
    setExported(0);
    try {
      const rows: Record<string, any>[] = [];
      const page = 500;
      for (;;) {
        const next = await repo.exportRows(kind, clinic.id, { limit: page, offset: rows.length });
        rows.push(...next);
        setExported(rows.length);
        if (next.length < page) break;
      }
      const layout = exportLayout(kind, withNotes);
      const csv = toCsv([layout.headers, ...rows.map(layout.cells)]);
      downloadTextFile(`${kind}-${clinic.slug}-${format(new Date(), 'yyyy-MM-dd')}.csv`, 'text/csv', csv);
      overlay.snack(`Exported ${importKindCount(kind, rows.length)}.`);
    } catch (e) {
      overlay.snack(describeError(e));
    } finally {
      setExported(null);
    }
  };

  const doImport = async () => {
    let file;
    try {
      file = await pickTextFile();
    } catch (e) {
      overlay.snack(`Could not read that file. ${String(e)}`);
      return;
    }
    if (file == null) return;
    const rows = parseCsv(file.text);
    if (rows.length < 2) {
      overlay.snack('That file has no rows under its header. Is it a CSV with the column names in the first row?');
      return;
    }
    const name = file.name;
    await overlay.showPage((close) => <ImportFlow spec={importSpecOf(kind)} fileName={name} rows={rows} close={close} />);
    void qc.invalidateQueries({ queryKey: ['importBatches'] });
  };

  const description: Record<ImportKind, string> = {
    patients:
      'Add or update patients from a CSV file: your old patient list, typed-up forms, or an export from here edited in Excel or Google Sheets.',
    visits:
      'Add visits from a CSV file, past or upcoming. Past visits are kept as history; upcoming ones are booked like any other. The patients must be here already: import them first.',
    dental:
      "Add to patients' dental charts from a CSV file: findings, existing work, the treatment plan and work done. Work done is recorded at the visit on its date, so import the visits first.",
  };
  const exportText: Record<ImportKind, string> = {
    patients: clinician
      ? 'Every patient at this clinic as a CSV file: their details, the patient information form, clinic notes and what they owe.'
      : 'Every patient at this clinic as a CSV file: their details, the patient information form and what they owe. Clinic notes are left out: only doctors and admins see them.',
    visits: clinician
      ? 'Every visit at this clinic, past and upcoming, with its doctor, service, status and notes.'
      : 'Every visit at this clinic, past and upcoming, with its doctor, service and status. Visit notes are left out: only doctors and admins see them.',
    dental: 'Every entry on every dental chart here, tooth by tooth (FDI numbers).',
  };

  return (
    <Page title="Import & export" maxWidth={ContentWidth.form} back="/patients">
      <SegmentedButtons
        value={kind}
        onValueChange={(v) => !exporting && setKind(v as ImportKind)}
        buttons={kinds.map((k) => ({ value: k, label: importKindMeta[k].label, disabled: exporting }))}
      />
      <View style={{ height: 16 }} />
      <Section icon="upload-file" title={`Import ${meta.many}`}>
        <Text>{description[kind]}</Text>
        <View style={{ height: 8 }} />
        <Tips
          tips={[
            'The first row names the columns. Download the template for the ones this app knows; other names are matched where they can be, and you can fix the rest.',
            ...(kind !== 'patients' ? ['Rows find their patient by chart no., or by name (with a phone or birthday when two patients share one).'] : []),
            'In Excel, use File › Save As › CSV UTF-8.',
            'Nothing is saved until you have seen what the import will do, and you can undo it afterwards.',
          ]}
        />
        {!clinician && kind !== 'dental' && (
          <Text variant="bodySmall" style={{ marginTop: 8, color: colors.onSurfaceVariant }}>
            {kind === 'patients' ? 'Clinic notes in a file are imported only by doctors and admins.' : 'Visit notes in a file are imported only by doctors and admins.'}
          </Text>
        )}
        {!canImport && (
          <Text variant="bodySmall" style={{ marginTop: 8, color: colors.error }}>
            Dental charts are imported by doctors and admins.
          </Text>
        )}
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
          <Button mode="contained" icon="file-open" disabled={exporting || !canImport} onPress={() => void doImport()}>
            Choose a CSV file
          </Button>
          <Button mode="outlined" icon="table-view" onPress={() => downloadTextFile(`${kind}-template.csv`, 'text/csv', toCsv([importSpecOf(kind).templateHeaders]))}>
            Download template
          </Button>
        </View>
      </Section>
      <View style={{ height: 16 }} />
      <Section icon="download" title={`Export ${meta.many}`}>
        <Text>{exportText[kind]}</Text>
        <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 8, marginTop: 8 }}>
          <Icon name="shield" size={18} color={colors.error} />
          <Text variant="bodySmall" style={{ flex: 1 }}>
            The file holds personal and health information. Keep it private and delete it when you are done. Each export is recorded.
          </Text>
        </View>
        <Button mode="contained-tonal" icon={exporting ? undefined : 'download'} disabled={exporting} onPress={() => void doExport()} style={{ marginTop: 12, alignSelf: 'flex-start' }}>
          {exporting ? (
            <>
              <ActivityIndicator size={14} /> {`Exporting… ${exported}`}
            </>
          ) : (
            `Export ${meta.many} (CSV)`
          )}
        </Button>
      </Section>
      <Text variant="titleMedium" style={{ marginTop: 24, marginBottom: 8 }}>
        Recent imports
      </Text>
      <AsyncView value={batches} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['importBatches'] })}>
        {(list) =>
          list.length === 0 ? (
            <Text style={{ color: colors.onSurfaceVariant }}>None yet.</Text>
          ) : (
            <AppCard>
              {list.map((b) => (
                <BatchTile key={b.id} batch={b} />
              ))}
            </AppCard>
          )
        }
      </AsyncView>
    </Page>
  );
}

function Section({ icon, title, children }: { icon: IconName; title: string; children: ReactNode }) {
  const { colors } = useAppTheme();
  return (
    <AppCard padding={16}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <Icon name={icon} color={colors.primary} />
        <Text variant="titleMedium">{title}</Text>
      </View>
      {children}
    </AppCard>
  );
}

function Tips({ tips }: { tips: string[] }) {
  return (
    <View>
      {tips.map((t) => (
        <View key={t} style={{ flexDirection: 'row', marginTop: 4 }}>
          <Text variant="bodySmall">•  </Text>
          <Text variant="bodySmall" style={{ flex: 1 }}>
            {t}
          </Text>
        </View>
      ))}
    </View>
  );
}

/// One past import, with Undo for an admin or whoever ran it.
function BatchTile({ batch: b }: { batch: ImportBatch }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const role = useCurrentClinicRole().value;
  const uid = useCurrentUserId();
  const [busy, setBusy] = useState(false);
  const mine = b.createdBy != null && b.createdBy === uid;
  const canUndo = !b.isUndone && b.created > 0 && (role === 'admin' || mine);
  const when = format(b.createdAt, 'MMM d, y · h:mm a');
  const counts = [
    `${b.created} added`,
    ...(b.kind === 'patients' ? [`${b.updated} updated`] : []),
    ...(b.skipped > 0 ? [`${b.skipped} skipped`] : []),
    ...(b.failed > 0 ? [`${b.failed} failed`] : []),
  ].join(' · ');
  const icon: IconName = b.isUndone ? 'undo' : b.kind === 'patients' ? 'group' : b.kind === 'visits' ? 'event-note' : 'grid-view';

  const undo = async () => {
    if (!(await confirmUndoImport(overlay, b.kind, b.created, b.updated))) return;
    setBusy(true);
    try {
      const r = await repo.undoImport(b.id);
      overlay.snack(undoneMessage(b.kind, r.removed));
      void qc.invalidateQueries({ queryKey: ['importBatches'] });
    } catch (e) {
      overlay.snack(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <ListTile
      leading={<Icon name={icon} color={b.isUndone ? colors.onSurfaceVariant : colors.onSurface} />}
      title={
        <Text numberOfLines={1}>
          {importKindMeta[b.kind].label} · {b.fileName}
        </Text>
      }
      subtitle={b.isUndone ? `${when} · undone` : `${when}\n${counts}`}
      trailing={!canUndo ? undefined : busy ? <ActivityIndicator size={20} /> : <Button onPress={() => void undo()}>Undo</Button>}
    />
  );
}
