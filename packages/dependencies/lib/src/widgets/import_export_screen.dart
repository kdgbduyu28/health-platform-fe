import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../calendar/browser_links.dart';
import '../import_export/csv.dart';
import '../import_export/file_picker.dart';
import '../import_export/import_spec.dart';
import '../models/app_role.dart';
import '../models/data_import.dart';
import '../providers/clinic_provider.dart';
import '../providers/clinical_provider.dart';
import '../providers/data_import_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';
import 'import_flow.dart';

/// The clinic's records in and out as spreadsheets, for the front desk and
/// admins: patients, their visit history, and (at a dental clinic) their
/// dental charts. Export to CSV; import a CSV (the clinic's old records, or
/// an export edited in Excel); undo a recent import.
///
/// Clinical notes follow the usual rule: only doctors and admins export or
/// import them. The dental chart is clinical, so only they import it; the
/// front desk, who read it, may export it.
class ImportExportScreen extends ConsumerStatefulWidget {
  const ImportExportScreen({super.key});

  @override
  ConsumerState<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  ImportKind _kind = ImportKind.patients;

  /// Rows fetched so far while exporting; null when not exporting.
  int? _exported;

  Future<void> _export() async {
    final clinic = ref.read(currentClinicProvider).value;
    if (clinic == null) return;
    final kind = _kind;
    final withNotes = await ref.read(canSeeClinicalNotesProvider.future);
    final repo = ref.read(healthRepositoryProvider);
    setState(() => _exported = 0);
    try {
      final rows = <Map<String, dynamic>>[];
      const page = 500;
      while (true) {
        final next = await repo.exportRows(kind, clinic.id, limit: page, offset: rows.length);
        rows.addAll(next);
        if (mounted) setState(() => _exported = rows.length);
        if (next.length < page) break;
      }
      final layout = exportLayout(kind, withNotes: withNotes);
      final csv = toCsv([layout.headers, for (final r in rows) layout.cells(r)]);
      final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
      downloadTextFile('${kind.wire}-${clinic.slug}-$day.csv', 'text/csv', csv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported ${kind.count(rows.length)}.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _exported = null);
    }
  }

  void _downloadTemplate() {
    downloadTextFile('${_kind.wire}-template.csv', 'text/csv',
        toCsv([ImportSpec.of(_kind).templateHeaders]));
  }

  Future<void> _import() async {
    final PickedTextFile? file;
    try {
      file = await pickTextFile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not read that file. $e')));
      }
      return;
    }
    if (file == null || !mounted) return;
    final rows = parseCsv(file.text);
    if (rows.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That file has no rows under its header. Is it a CSV '
              'with the column names in the first row?')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          ImportFlow(spec: ImportSpec.of(_kind), fileName: file!.name, rows: rows),
    ));
    ref.invalidate(importBatchesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final clinician = ref.watch(canSeeClinicalNotesProvider).value ?? false;
    final dental = ref.watch(currentClinicProvider).value?.chartKind == 'dental';
    final exporting = _exported != null;
    final kinds = [
      ImportKind.patients,
      ImportKind.visits,
      if (dental) ImportKind.dental,
    ];
    if (!kinds.contains(_kind)) _kind = ImportKind.patients;
    final canImport = _kind != ImportKind.dental || clinician;

    return Scaffold(
      appBar: AppBar(title: const Text('Import & export')),
      body: CenteredScroll(
        maxWidth: ContentWidth.form,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        builder: (padding) => ListView(
          padding: padding,
          children: [
            SegmentedButton<ImportKind>(
              segments: [
                for (final k in kinds) ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: exporting ? null : (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            _Section(
              icon: Icons.upload_file_outlined,
              title: 'Import ${_kind.many}',
              children: [
                Text(switch (_kind) {
                  ImportKind.patients =>
                    'Add or update patients from a CSV file: your old patient '
                        'list, typed-up forms, or an export from here edited in '
                        'Excel or Google Sheets.',
                  ImportKind.visits =>
                    'Add visits from a CSV file, past or upcoming. Past visits '
                        'are kept as history; upcoming ones are booked like any '
                        'other. The patients must be here already: import them '
                        'first.',
                  ImportKind.dental =>
                    'Add to patients\' dental charts from a CSV file: findings, '
                        'existing work, the treatment plan and work done. Work '
                        'done is recorded at the visit on its date, so import '
                        'the visits first.',
                }),
                const SizedBox(height: 8),
                _Tips(tips: [
                  'The first row names the columns. Download the template '
                      'for the ones this app knows; other names are matched '
                      'where they can be, and you can fix the rest.',
                  if (_kind != ImportKind.patients)
                    'Rows find their patient by chart no., or by name (with a '
                        'phone or birthday when two patients share one).',
                  'In Excel, use File › Save As › CSV UTF-8.',
                  'Nothing is saved until you have seen what the import '
                      'will do, and you can undo it afterwards.',
                ]),
                if (!clinician && _kind != ImportKind.dental)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _kind == ImportKind.patients
                          ? 'Clinic notes in a file are imported only by doctors '
                              'and admins.'
                          : 'Visit notes in a file are imported only by doctors '
                              'and admins.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                if (!canImport)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Dental charts are imported by doctors and admins.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: exporting || !canImport ? null : _import,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Choose a CSV file'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadTemplate,
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Download template'),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              icon: Icons.download_outlined,
              title: 'Export ${_kind.many}',
              children: [
                Text(switch (_kind) {
                  ImportKind.patients => clinician
                      ? 'Every patient at this clinic as a CSV file: their '
                          'details, the patient information form, clinic '
                          'notes and what they owe.'
                      : 'Every patient at this clinic as a CSV file: their '
                          'details, the patient information form and what '
                          'they owe. Clinic notes are left out: only doctors '
                          'and admins see them.',
                  ImportKind.visits => clinician
                      ? 'Every visit at this clinic, past and upcoming, with '
                          'its doctor, service, status and notes.'
                      : 'Every visit at this clinic, past and upcoming, with '
                          'its doctor, service and status. Visit notes are '
                          'left out: only doctors and admins see them.',
                  ImportKind.dental =>
                    'Every entry on every dental chart here, tooth by tooth '
                        '(FDI numbers).',
                }),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.shield_outlined, size: 18, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The file holds personal and health information. '
                      'Keep it private and delete it when you are done. '
                      'Each export is recorded.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: exporting ? null : _export,
                  icon: exporting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  label: Text(exporting
                      ? 'Exporting… $_exported'
                      : 'Export ${_kind.many} (CSV)'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Recent imports', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            AsyncView(
              value: ref.watch(importBatchesProvider),
              onRetry: () => ref.invalidate(importBatchesProvider),
              builder: (batches) => batches.isEmpty
                  ? Text('None yet.',
                      style: TextStyle(color: cs.onSurfaceVariant))
                  : Card(
                      margin: EdgeInsets.zero,
                      child: Column(children: [
                        for (final b in batches) _BatchTile(batch: b),
                      ]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips({required this.tips});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in tips)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: style),
              Expanded(child: Text(t, style: style)),
            ]),
          ),
      ],
    );
  }
}

/// One past import, with Undo for an admin or whoever ran it.
class _BatchTile extends ConsumerStatefulWidget {
  const _BatchTile({required this.batch});

  final ImportBatch batch;

  @override
  ConsumerState<_BatchTile> createState() => _BatchTileState();
}

class _BatchTileState extends ConsumerState<_BatchTile> {
  bool _busy = false;

  Future<void> _undo() async {
    final b = widget.batch;
    final ok = await confirmUndoImport(context,
        kind: b.kind, added: b.created, updated: b.updated);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(healthRepositoryProvider).undoImport(b.id);
      messenger.showSnackBar(SnackBar(content: Text(undoneMessage(b.kind, r))));
      ref.invalidate(importBatchesProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.batch;
    final cs = Theme.of(context).colorScheme;
    final role = ref.watch(currentClinicRoleProvider).value;
    final mine = b.createdBy != null && b.createdBy == ref.watch(currentUserIdProvider);
    final canUndo = !b.isUndone && b.created > 0 && (role == AppRole.admin || mine);
    final when = DateFormat('MMM d, y · h:mm a').format(b.createdAt);
    final counts = [
      '${b.created} added',
      if (b.kind == ImportKind.patients) '${b.updated} updated',
      if (b.skipped > 0) '${b.skipped} skipped',
      if (b.failed > 0) '${b.failed} failed',
    ].join(' · ');
    return ListTile(
      leading: Icon(
          b.isUndone
              ? Icons.undo
              : switch (b.kind) {
                  ImportKind.patients => Icons.group_outlined,
                  ImportKind.visits => Icons.event_note_outlined,
                  ImportKind.dental => Icons.grid_view_outlined,
                },
          color: b.isUndone ? cs.onSurfaceVariant : null),
      title: Text('${b.kind.label} · ${b.fileName}', overflow: TextOverflow.ellipsis),
      subtitle: Text(b.isUndone ? '$when · undone' : '$when\n$counts'),
      isThreeLine: !b.isUndone,
      trailing: !canUndo
          ? null
          : _busy
              ? const SizedBox.square(
                  dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(onPressed: _undo, child: const Text('Undo')),
    );
  }
}

/// Asks before undoing an import, saying what it removes and what stays.
Future<bool> confirmUndoImport(BuildContext context,
    {required ImportKind kind, required int added, required int updated}) async {
  final what = switch (kind) {
    ImportKind.patients =>
      'This removes the ${kind.count(added)} it added, with their forms, notes '
          'and opening balances. It only works if none of them has had a '
          'visit, bill or payment since.'
          '${updated == 0 ? '' : '\n\nThe ${kind.count(updated)} it updated keep the changes.'}',
    ImportKind.visits =>
      'This removes the ${kind.count(added)} it added, with their notes. It '
          'only works if none of them has been changed, billed or charted since.',
    ImportKind.dental =>
      'This removes the ${kind.count(added)} it added. It only works if none '
          'of them has been changed since.',
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Undo this import?'),
      content: Text(what),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Undo import')),
      ],
    ),
  );
  return ok ?? false;
}

String undoneMessage(ImportKind kind, UndoImportResult r) =>
    'Import undone: ${kind.count(r.removed)} removed.';
