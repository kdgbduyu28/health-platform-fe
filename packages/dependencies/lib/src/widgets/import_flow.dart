import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../calendar/browser_links.dart';
import '../import_export/csv.dart';
import '../import_export/import_common.dart';
import '../import_export/import_spec.dart';
import '../import_export/visit_columns.dart';
import '../models/app_role.dart';
import '../models/data_import.dart';
import '../models/dental_chart.dart';
import '../models/doctor.dart';
import '../providers/appointments_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/clinical_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';
import 'import_export_screen.dart';

/// Importing one CSV file — patients, visits or a dental chart — start to
/// finish:
///
///   columns    which of the file's columns is which (matched from the
///              headers; the person fixes the rest), how it writes dates and
///              tooth numbers, and which roster doctor each name means
///   check      a dry run of every row against the database
///   review     what will happen: new, updated, already on file, problems,
///              and (patients) possible duplicates, each to be updated,
///              added as new, or skipped
///   import     the real run, a chunk at a time
///   done       the tally, the rows that failed as a file, and Undo
class ImportFlow extends ConsumerStatefulWidget {
  const ImportFlow({
    super.key,
    required this.spec,
    required this.fileName,
    required this.rows,
  });

  final ImportSpec spec;
  final String fileName;

  /// The file as parsed: the header row first.
  final List<List<String>> rows;

  @override
  ConsumerState<ImportFlow> createState() => _ImportFlowState();
}

enum _Step { columns, checking, review, importing, done }

/// What to do with a row that looks like a patient already here.
enum _Decision {
  update('Update'),
  create('Add as new'),
  skip('Skip');

  const _Decision(this.label);
  final String label;
}

/// Rows per call: well inside the database's 500, and a few seconds' work.
const _chunk = 200;

class _ImportFlowState extends ConsumerState<ImportFlow> {
  late final List<String> _headers = widget.rows.first;
  late final List<List<String>> _body = widget.rows.sublist(1);
  late List<ImportColumn?> _columns = widget.spec.match(_headers);
  DateOrder _dateOrder = DateOrder.monthFirst;
  ToothNumbering _numbering = ToothNumbering.fdi;

  /// Visits: the roster doctor picked for each doctor name in the file.
  final Map<String, String> _doctorPicks = {};

  _Step _step = _Step.columns;
  int _done = 0;
  int _total = 0;
  Object? _error;

  List<ImportRow> _parsed = const [];
  Map<int, ImportRowResult> _check = const {};
  final Map<int, _Decision> _decisions = {};

  String? _batchId;
  Map<int, ImportRowResult> _results = const {};
  bool _undone = false;

  ImportKind get _kind => widget.spec.kind;

  /// Each doctor name in the file (cleaned), with how many rows use it.
  Map<String, int> get _doctorNames {
    final i = widget.spec.doctorColumn == null
        ? -1
        : _columns.indexOf(widget.spec.doctorColumn);
    if (i < 0) return const {};
    final out = <String, int>{};
    for (final r in _body) {
      final name = i < r.length ? cleanCell(r[i]) : '';
      out[name] = (out[name] ?? 0) + 1;
    }
    return out;
  }

  /// Why the check cannot run yet, or null.
  String? get _missing {
    final m = widget.spec.missing(_columns);
    if (m != null) return m;
    if (widget.spec.doctorColumn != null) {
      if (!_columns.contains(widget.spec.doctorColumn)) {
        return 'Pick the column with the doctor.';
      }
      if (_doctorNames.keys.any((n) => !_doctorPicks.containsKey(n))) {
        return 'Match every doctor in the file to one on the roster.';
      }
    }
    return null;
  }

  ImportSettings get _settings => ImportSettings(
        dateOrder: _dateOrder,
        numbering: _numbering,
        doctors: _doctorPicks,
      );

  /// Names the file's doctors after the roster, where they plainly match.
  void _autoMatchDoctors(List<Doctor> roster) {
    final byName = {for (final d in roster) d.name: d.id};
    for (final name in _doctorNames.keys) {
      if (_doctorPicks.containsKey(name)) continue;
      final id = name.isEmpty
          ? (roster.where((d) => d.isActive).length == 1
              ? roster.firstWhere((d) => d.isActive).id
              : null)
          : matchDoctor(name, byName);
      if (id != null) _doctorPicks[name] = id;
    }
  }

  String? get _clinicId => ref.read(currentClinicIdProvider);

  // ── Checking ──

  Future<void> _runCheck() async {
    final parsed = [
      for (var i = 0; i < _body.length; i++)
        widget.spec.read(_body[i], _columns, i + 2, _settings),
    ];
    _markRepeats(parsed);
    final sendable = [for (final r in parsed) if (r.ok) r];
    setState(() {
      _parsed = parsed;
      _step = _Step.checking;
      _done = 0;
      _total = sendable.length;
      _error = null;
    });
    try {
      final results = <int, ImportRowResult>{};
      final repo = ref.read(healthRepositoryProvider);
      for (var i = 0; i < sendable.length; i += _chunk) {
        final part = sendable.sublist(i, (i + _chunk).clamp(0, sendable.length));
        final out = await repo.importRows(
            kind: _kind, clinicId: _clinicId!, rows: [for (final r in part) r.json]);
        for (final r in out) {
          results[r.row] = r;
        }
        if (!mounted) return;
        setState(() => _done = i + part.length);
      }
      _decisions
        ..clear()
        ..addAll({
          for (final r in results.values)
            if (r.outcome == ImportOutcome.duplicate) r.row: _Decision.update,
        });
      setState(() {
        _check = results;
        _step = _Step.review;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _step = _Step.columns;
        });
      }
    }
  }

  /// The same patient twice in one file (same chart number, or same name
  /// and phone or birthday) is a mistake to fix in the file, not something
  /// to import twice: the later rows are held back.
  void _markRepeats(List<ImportRow> rows) {
    final seen = <String, int>{};
    for (final r in rows) {
      if (!r.ok) continue;
      final keys = widget.spec.sameRecordKeys(r);
      final first = keys.map((k) => seen[k]).whereType<int>().firstOrNull;
      if (first != null) {
        r.errors.add('The same patient as row $first of this file.');
      } else {
        for (final k in keys) {
          seen[k] = r.row;
        }
      }
    }
  }

  // ── Importing ──

  List<Map<String, dynamic>> get _toSend => [
        for (final r in _parsed)
          if (r.ok && _check[r.row]?.outcome != ImportOutcome.error)
            switch (_decisions[r.row]) {
              null => r.json,
              _Decision.update => {
                  ...r.json,
                  'action': 'update',
                  'match_id': _check[r.row]!.match!.id,
                },
              _Decision.create => {...r.json, 'action': 'create'},
              _Decision.skip => {'row': r.row, 'action': 'skip'},
            },
      ];

  Future<void> _runImport() async {
    final rows = _toSend;
    setState(() {
      _step = _Step.importing;
      _done = 0;
      _total = rows.length;
      _error = null;
    });
    final results = <int, ImportRowResult>{};
    try {
      final repo = ref.read(healthRepositoryProvider);
      _batchId ??= await repo.startImport(
          clinicId: _clinicId!, fileName: widget.fileName, kind: _kind);
      for (var i = 0; i < rows.length; i += _chunk) {
        final part = rows.sublist(i, (i + _chunk).clamp(0, rows.length));
        final out = await repo.importRows(
            kind: _kind, clinicId: _clinicId!, rows: part, batchId: _batchId);
        for (final r in out) {
          results[r.row] = r;
        }
        if (!mounted) return;
        setState(() => _done = i + part.length);
      }
      _refresh();
    } catch (e) {
      // Chunks already in stay in; say how far it got.
      _error = e;
    }
    if (mounted) {
      setState(() {
        _results = results;
        _step = _Step.done;
      });
    }
  }

  Future<void> _undo() async {
    final created = _count(_results, ImportOutcome.created);
    final updated = _count(_results, ImportOutcome.updated);
    if (!await confirmUndoImport(context, kind: _kind, added: created, updated: updated)) {
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(healthRepositoryProvider).undoImport(_batchId!);
      messenger.showSnackBar(SnackBar(content: Text(undoneMessage(_kind, r))));
      _refresh();
      if (mounted) setState(() => _undone = true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  /// The rows that did not go in, as the file had them plus why, to fix and
  /// import again.
  void _downloadProblems(List<(ImportRow, String)> problems) {
    final base = widget.fileName.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');
    downloadTextFile('$base-problems.csv', 'text/csv', toCsv([
      [..._headers, 'Problem'],
      for (final (row, why) in problems)
        [...row.cells, ...List.filled(_headers.length - row.cells.length.clamp(0, _headers.length), ''), why],
    ]));
  }

  Future<void> _addFormerDoctor(String name) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ref.read(healthRepositoryProvider).addFormerDoctor(_clinicId!, name);
      ref.invalidate(rosterProvider);
      ref.invalidate(doctorsProvider);
      if (mounted) setState(() => _doctorPicks[name] = id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  /// What an import changed, shown again wherever it is listed.
  void _refresh() {
    ref.invalidate(patientTableProvider);
    if (_kind == ImportKind.visits) ref.invalidate(appointmentsProvider);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final busy = _step == _Step.checking || _step == _Step.importing;
    return PopScope(
      // Leaving mid-import would stop it halfway; wait for the chunk.
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_step) {
            _Step.columns => 'Import · match the columns',
            _Step.checking => 'Import · checking',
            _Step.review => 'Import · review',
            _Step.importing => 'Importing…',
            _Step.done => 'Import finished',
          }),
          automaticallyImplyLeading: !busy,
        ),
        body: switch (_step) {
          _Step.columns => _columnsStep(context),
          _Step.checking || _Step.importing => _progress(context),
          _Step.review => _reviewStep(context),
          _Step.done => _doneStep(context),
        },
        bottomNavigationBar: switch (_step) {
          _Step.columns => _BottomBar(children: [
              if (_missing case final why?) Expanded(child: Text(why)) else const Spacer(),
              FilledButton(
                onPressed: _missing == null ? _runCheck : null,
                child: Text('Check ${_body.length} ${_body.length == 1 ? 'row' : 'rows'}'),
              ),
            ]),
          _Step.review => _BottomBar(children: [
              TextButton(
                onPressed: () => setState(() => _step = _Step.columns),
                child: const Text('Back to columns'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _importCount == 0 ? null : _runImport,
                child: Text('Import ${_kind.count(_importCount)}'),
              ),
            ]),
          _Step.done => _BottomBar(children: [
              if (_batchId != null && !_undone && _count(_results, ImportOutcome.created) > 0)
                TextButton.icon(
                  onPressed: _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo this import'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ]),
          _ => null,
        },
      ),
    );
  }

  int get _importCount => _toSend.where((r) => r['action'] != 'skip').length;

  Widget _progress(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 320,
              child: LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            ),
            const SizedBox(height: 16),
            Text(_step == _Step.checking
                ? 'Checking row $_done of $_total…'
                : 'Imported $_done of $_total…'),
            const SizedBox(height: 4),
            Text('Keep this page open.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );

  Widget _columnsStep(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final spec = widget.spec;
    final hasDates = _columns.any(spec.dateColumns.contains);
    final notes = [for (final c in _columns) if (spec.clinicianColumns.contains(c)) c!.header];
    final seesNotes = ref.watch(canSeeClinicalNotesProvider).value ?? false;
    final doctors = _doctorNames;
    final roster = spec.doctorColumn == null
        ? null
        : ref.watch(rosterProvider).whenData((r) {
            _autoMatchDoctors(r);
            return r;
          });
    return CenteredScroll(
      maxWidth: ContentWidth.list,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      builder: (padding) => ListView(
        padding: padding,
        children: [
          Text('${_kind.label} · ${widget.fileName}', style: theme.textTheme.titleMedium),
          Text('${_body.length} ${_body.length == 1 ? 'row' : 'rows'} · '
              '${_headers.length} columns'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Banner(color: cs.errorContainer, text: 'The check stopped: ${describeError(_error!)}'),
          ],
          const SizedBox(height: 16),
          const Text('Each column of your file, and what it holds here. '
              'Columns set to "Don\'t import" are left out.'),
          if (hasDates) ...[
            const SizedBox(height: 16),
            Text('How the file writes dates', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            DropdownButton<DateOrder>(
              value: _dateOrder,
              isExpanded: true,
              items: [
                for (final o in DateOrder.values)
                  DropdownMenuItem(value: o, child: Text(o.label)),
              ],
              onChanged: (o) => setState(() => _dateOrder = o!),
            ),
          ],
          if (spec.asksNumbering) ...[
            const SizedBox(height: 16),
            Text('How the file numbers teeth', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            DropdownButton<ToothNumbering>(
              value: _numbering,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                    value: ToothNumbering.fdi,
                    child: Text('FDI (11–48, baby teeth 51–85)')),
                DropdownMenuItem(
                    value: ToothNumbering.universal,
                    child: Text('Universal (1–32, baby teeth A–T)')),
              ],
              onChanged: (n) => setState(() => _numbering = n!),
            ),
          ],
          if (notes.isNotEmpty && !seesNotes) ...[
            const SizedBox(height: 12),
            _Banner(
                color: cs.secondaryContainer,
                text: '${notes.join(' and ')} will be left out: only doctors '
                    'and admins can import them.'),
          ],
          if (roster != null && doctors.isNotEmpty) ...[
            const SizedBox(height: 16),
            AsyncView(
              value: roster,
              onRetry: () => ref.invalidate(rosterProvider),
              builder: (r) => _DoctorsCard(
                names: doctors,
                roster: r,
                picks: _doctorPicks,
                canAdd: ref.watch(currentClinicRoleProvider).value == AppRole.admin,
                onPick: (name, id) => setState(() => _doctorPicks[name] = id),
                onAdd: _addFormerDoctor,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < _headers.length; i++)
                _ColumnTile(
                  options: spec.columns,
                  header: _headers[i],
                  example: _example(i),
                  value: _columns[i],
                  onChanged: (c) => setState(() {
                    _columns = [
                      for (var j = 0; j < _columns.length; j++)
                        j == i ? c : (c != null && _columns[j] == c ? null : _columns[j]),
                    ];
                  }),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  /// The first few values in column [i], to recognise it by.
  String _example(int i) => _body
      .take(20)
      .map((r) => i < r.length ? r[i].trim() : '')
      .where((v) => v.isNotEmpty)
      .take(2)
      .join(' · ');

  Widget _reviewStep(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final problems = <(ImportRow, String)>[
      for (final r in _parsed)
        if (!r.ok)
          (r, r.errors.join(' '))
        else if (_check[r.row] case final c? when c.outcome == ImportOutcome.error)
          (r, c.message ?? 'Could not be imported.'),
    ];
    final dupes = [
      for (final r in _parsed)
        if (_check[r.row]?.outcome == ImportOutcome.duplicate) r,
    ];
    final warned = [
      for (final r in _parsed)
        if (r.ok && _check[r.row]?.outcome != ImportOutcome.error)
          if ({...r.warnings, ...?_check[r.row]?.warnings} case final w when w.isNotEmpty)
            (r, w.join(' ')),
    ];
    final created = _count(_check, ImportOutcome.created);
    final updated = _count(_check, ImportOutcome.updated);
    final onFile = _count(_check, ImportOutcome.skipped);
    final patients = _kind == ImportKind.patients;

    return CenteredScroll(
      maxWidth: ContentWidth.list,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      builder: (padding) => ListView(
        padding: padding,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Stat(label: 'New ${_kind.many}', value: created, icon: Icons.add_circle_outline),
            if (patients) ...[
              _Stat(label: 'Already here, updated', value: updated, icon: Icons.edit_outlined),
              _Stat(label: 'Look like patients here', value: dupes.length,
                  icon: Icons.people_outline),
            ] else
              _Stat(label: 'Already on file', value: onFile, icon: Icons.inventory_2_outlined),
            _Stat(label: 'Problems', value: problems.length, icon: Icons.error_outline,
                color: problems.isEmpty ? null : cs.error),
          ]),
          const SizedBox(height: 8),
          Text(patients
              ? 'Nothing has been saved yet. An update fills in what the file '
                  'has and keeps what is on file where the file is blank.'
              : 'Nothing has been saved yet. What is already on file is '
                  'left as it is.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (dupes.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Text('Look like patients already here',
                    style: theme.textTheme.titleMedium),
              ),
              PopupMenuButton<_Decision>(
                tooltip: 'Set all',
                onSelected: (d) => setState(() {
                  for (final r in dupes) {
                    _decisions[r.row] = d;
                  }
                }),
                itemBuilder: (_) => [
                  for (final d in _Decision.values)
                    PopupMenuItem(value: d, child: Text('${d.label}: all')),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Set all…'),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            for (final r in dupes.take(200))
              _DuplicateCard(
                row: r,
                match: _check[r.row]!.match!,
                decision: _decisions[r.row] ?? _Decision.update,
                onChanged: (d) => setState(() => _decisions[r.row] = d),
              ),
            if (dupes.length > 200)
              Text('…and ${dupes.length - 200} more, set with "Set all".'),
          ],
          if (problems.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Text('Problems (not imported)', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () => _downloadProblems(problems),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download'),
              ),
            ]),
            _RowList(items: problems, color: cs.error),
          ],
          if (warned.isNotEmpty) ...[
            const SizedBox(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Imported, with a note (${warned.length})',
                  style: theme.textTheme.titleMedium),
              children: [_RowList(items: warned)],
            ),
          ],
        ],
      ),
    );
  }

  Widget _doneStep(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final failed = <(ImportRow, String)>[
      for (final r in _parsed)
        if (!r.ok)
          (r, r.errors.join(' '))
        else if (_check[r.row]?.outcome == ImportOutcome.error)
          (r, _check[r.row]!.message ?? 'Could not be imported.')
        else if (_results[r.row] case final res?
            when res.outcome == ImportOutcome.error || res.outcome == ImportOutcome.duplicate)
          (r, res.message ?? 'Could not be imported.'),
    ];
    return CenteredScroll(
      maxWidth: ContentWidth.list,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      builder: (padding) => ListView(
        padding: padding,
        children: [
          if (_error != null)
            _Banner(
              color: cs.errorContainer,
              text: 'The import stopped part-way: ${describeError(_error!)} '
                  'What is counted below went in. To finish, import the same '
                  'file again: the patients already in show up as matches, '
                  'to update or skip.',
            ),
          if (_undone)
            _Banner(color: cs.secondaryContainer, text: 'This import was undone.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Stat(label: 'Added', value: _count(_results, ImportOutcome.created),
                icon: Icons.person_add_alt),
            _Stat(label: 'Updated', value: _count(_results, ImportOutcome.updated),
                icon: Icons.edit_outlined),
            _Stat(label: 'Skipped', value: _count(_results, ImportOutcome.skipped),
                icon: Icons.redo),
            _Stat(label: 'Not imported', value: failed.length, icon: Icons.error_outline,
                color: failed.isEmpty ? null : cs.error),
          ]),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Text('Not imported', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () => _downloadProblems(failed),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download to fix'),
              ),
            ]),
            _RowList(items: failed, color: cs.error),
          ],
        ],
      ),
    );
  }
}

int _count(Map<int, ImportRowResult> results, ImportOutcome o) =>
    results.values.where((r) => r.outcome == o).length;

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Material(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: children),
          ),
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(text),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon, this.color});

  final String label;
  final int value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text('$value',
            style: theme.textTheme.headlineSmall?.copyWith(color: color)),
        Text(label, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

class _ColumnTile extends StatelessWidget {
  const _ColumnTile({
    required this.options,
    required this.header,
    required this.example,
    required this.value,
    required this.onChanged,
  });

  final String header;
  final String example;
  final List<ImportColumn> options;
  final ImportColumn? value;
  final ValueChanged<ImportColumn?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final picker = DropdownButton<ImportColumn?>(
      value: value,
      isExpanded: true,
      items: [
        DropdownMenuItem(
          value: null,
          child: Text("Don't import", style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        for (final c in options)
          DropdownMenuItem(value: c, child: Text(c.header)),
      ],
      onChanged: onChanged,
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(header.isEmpty ? '(no header)' : header,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        if (example.isNotEmpty)
          Text(example,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        if (value != null)
          Text(value!.hint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 520
            ? Row(children: [
                Expanded(child: label),
                const SizedBox(width: 16),
                SizedBox(width: 240, child: picker),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, picker],
              ),
      ),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({
    required this.row,
    required this.match,
    required this.decision,
    required this.onChanged,
  });

  final ImportRow row;
  final ImportMatch match;
  final _Decision decision;
  final ValueChanged<_Decision> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final person = row.json['person'] as Map<String, dynamic>;
    String line(String name, String? phone, String? born, String? chart) => [
          name,
          if (phone != null && phone.isNotEmpty) phone,
          if (born != null) 'born $born',
          if (chart != null) 'chart $chart',
        ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Row ${row.row}: ${line(row.name, person['phone'] as String?,
              person['date_of_birth'] as String?, row.json['chart_number'] as String?)}'),
          Text(
            'On file: ${line(match.name, match.phone,
                match.dateOfBirth == null ? null : DateFormat('yyyy-MM-dd').format(match.dateOfBirth!),
                match.chartNumber)}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SegmentedButton<_Decision>(
            segments: [
              for (final d in _Decision.values)
                ButtonSegment(value: d, label: Text(d.label)),
            ],
            selected: {decision},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ]),
      ),
    );
  }
}

/// Rows with a message each; the first 200, the rest in the download.
class _RowList extends StatelessWidget {
  const _RowList({required this.items, this.color});

  final List<(ImportRow, String)> items;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (row, why) in items.take(200))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 64,
                child: Text('Row ${row.row}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row.name.isEmpty ? '(no name)' : row.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(why, style: TextStyle(color: color, fontSize: 13)),
                ]),
              ),
            ]),
          ),
        if (items.length > 200) Text('…and ${items.length - 200} more in the download.'),
      ],
    );
  }
}

/// Each doctor name in a visits file, and the roster doctor it means. An
/// admin can put someone who has left on the roster, inactive, for their
/// visits.
class _DoctorsCard extends StatelessWidget {
  const _DoctorsCard({
    required this.names,
    required this.roster,
    required this.picks,
    required this.canAdd,
    required this.onPick,
    required this.onAdd,
  });

  final Map<String, int> names;
  final List<Doctor> roster;
  final Map<String, String> picks;
  final bool canAdd;
  final void Function(String name, String doctorId) onPick;
  final void Function(String name) onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Doctors in this file', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            canAdd
                ? 'Match each to the roster. Someone who has left can be added '
                    'as a former doctor: kept for their visits, never booked.'
                : 'Match each to the roster. An admin can add a doctor who has '
                    'left.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          for (final e in names.entries)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${e.key.isEmpty ? '(no doctor given)' : e.key} · ${e.value} '
                    '${e.value == 1 ? 'row' : 'rows'}',
                    style: TextStyle(
                        color: picks.containsKey(e.key) ? null : cs.error,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 240,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: picks[e.key],
                    hint: const Text('Pick a doctor'),
                    items: [
                      for (final d in roster)
                        DropdownMenuItem(
                          value: d.id,
                          child: Text(d.isActive ? d.name : '${d.name} (inactive)',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (id) => onPick(e.key, id!),
                  ),
                ),
                if (canAdd && e.key.isNotEmpty && !picks.containsKey(e.key))
                  IconButton(
                    tooltip: 'Add as a former doctor',
                    icon: const Icon(Icons.person_add_alt),
                    onPressed: () => onAdd(e.key),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
