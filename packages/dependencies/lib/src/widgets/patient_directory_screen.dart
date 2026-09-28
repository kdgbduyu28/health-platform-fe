import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../models/money.dart';
import '../models/patient.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import 'async_view.dart';
import 'clinic_title.dart';
import 'intake_screens.dart';
import 'patient_remarks.dart';
import 'record_visit_sheet.dart';

/// Every chart held at the current clinic, as a working list: search,
/// filter by remark (for recall, with balance, no contact info, needs
/// attention, pedia or adult), sort, and page through.
///
/// A sortable table from tablet width up, cards on a phone. The searching,
/// remarks, sorting and paging all happen in the database
/// (`search_patients`), one page at a time, so a clinic with thousands of
/// charts opens as fast as one with ten.
///
/// Shared by the staff apps; each passes [onOpenPatient] to route to its own
/// patient page. [canRecordVisits] adds "Manually add visit", for a visit
/// that happened but was never logged. The apps that register patients
/// (front desk, admin) also get "Add patient", and [onOpenData] opens their
/// import and export of patients as CSV.
class PatientDirectoryScreen extends ConsumerStatefulWidget {
  const PatientDirectoryScreen({
    super.key,
    required this.onOpenPatient,
    this.canRecordVisits = false,
    this.onOpenData,
  });

  final void Function(Patient patient) onOpenPatient;
  final bool canRecordVisits;
  final VoidCallback? onOpenData;

  @override
  ConsumerState<PatientDirectoryScreen> createState() =>
      _PatientDirectoryScreenState();
}

class _PatientDirectoryScreenState
    extends ConsumerState<PatientDirectoryScreen> {
  final _search = TextEditingController();
  PatientTableQuery _q = const PatientTableQuery();

  /// The page last shown, kept on screen while the next one loads.
  PatientPage? _shown;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// A new search, filter or sort starts again at page one.
  void _set(PatientTableQuery q) => setState(() => _q = q.copyWith(page: 0));

  void _toggleFilter(PatientFlag f) {
    final next = {..._q.filters};
    if (!next.remove(f)) {
      next.add(f);
      // An age group is one or the other.
      if (f == PatientFlag.pedia) next.remove(PatientFlag.adult);
      if (f == PatientFlag.adult) next.remove(PatientFlag.pedia);
    }
    _set(_q.copyWith(filters: next));
  }

  void _sortBy(PatientSort sort) {
    // Again on the same column flips it. Dates and amounts start with the
    // largest: the latest visit, the biggest balance.
    final descending =
        sort == _q.sort ? !_q.descending : sort != PatientSort.name;
    _set(_q.copyWith(sort: sort, descending: descending));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pageAsync = ref.watch(patientTableProvider(_q));
    final page = pageAsync.value ?? _shown;
    if (pageAsync.value != null) _shown = pageAsync.value;
    final loading = pageAsync.isLoading;
    final canRegister = ref.watch(appRoleProvider).registersPatients;
    final searching = _q.search.trim().isNotEmpty;
    // With the table, "Add patient" sits in the app bar; below that it is a
    // round button sharing the bottom row with the pager.
    final table = MediaQuery.sizeOf(context).width >= Breakpoints.twoPane;

    Future<void> addPatient() async {
      final added = await showAddPatientSheet(context, ref);
      if (added != null && mounted) widget.onOpenPatient(added);
    }

    return Scaffold(
      floatingActionButton: !canRegister || table
          ? null
          : FloatingActionButton(
              tooltip: 'Add patient',
              onPressed: addPatient,
              child: const Icon(Icons.person_add_alt_1),
            ),
      appBar: AppBar(
        title: ClinicNavScaffold.showsClinicName(context)
            ? Text('Patients',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Patients',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  ClinicTitle(
                    markSize: 20,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
        actions: [
          if (widget.canRecordVisits)
            IconButton(
              tooltip: 'Manually add visit',
              icon: const Icon(Icons.edit_note),
              onPressed: () => showRecordVisitSheet(context),
            ),
          if (canRegister && widget.onOpenData != null)
            IconButton(
              tooltip: 'Import / export',
              icon: const Icon(Icons.import_export),
              onPressed: widget.onOpenData,
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(patientTableProvider),
          ),
          if (canRegister && table)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: addPatient,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Add patient'),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.twoPane;
        return Column(
          children: [
            Centered(
              maxWidth: ContentWidth.wide + 32,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => _set(_q.copyWith(search: v)),
                        decoration: InputDecoration(
                          hintText: 'Search by name, phone, email or chart no.…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _search.clear();
                                    _set(_q.copyWith(search: ''));
                                  },
                                ),
                        ),
                      ),
                    ),
                    // The table sorts by its headers; a phone, or a tablet
                    // whose table leaves out a column, also gets a menu.
                    if (!wide || constraints.maxWidth - 32 < _PatientTable.fullWidth) ...[
                      const SizedBox(width: 8),
                      _SortMenu(query: _q, onSort: _sortBy),
                    ],
                  ],
                ),
              ),
            ),
            Centered(
              maxWidth: ContentWidth.wide + 32,
              child: SizedBox(
                width: double.infinity,
                child: _FilterBar(
                  selected: _q.filters,
                  counts: page?.counts ?? const {},
                  onToggle: _toggleFilter,
                  onClear: _q.filters.isEmpty
                      ? null
                      : () => _set(_q.copyWith(filters: const {})),
                ),
              ),
            ),
            if (page != null)
              Centered(
                maxWidth: ContentWidth.wide + 40,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _summary(page, searching || _q.filters.isNotEmpty),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            SizedBox(
              height: 2,
              child: loading && page != null
                  ? const LinearProgressIndicator()
                  : null,
            ),
            Expanded(
              child: page == null
                  ? AsyncView(
                      value: pageAsync,
                      onRetry: () => ref.invalidate(patientTableProvider(_q)),
                      builder: (_) => const SizedBox.shrink(),
                    )
                  : page.patients.isEmpty
                      ? _Empty(
                          text: searching
                              ? 'No patients match "${_q.search.trim()}".'
                              : _q.filters.isNotEmpty
                                  ? 'No patients with these remarks.'
                                  : 'No patients yet.',
                        )
                      : wide
                          ? _PatientTable(
                              page: page,
                              query: _q,
                              onSort: _sortBy,
                              onOpen: widget.onOpenPatient,
                            )
                          : CenteredScroll(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              builder: (padding) => ListView.separated(
                                padding: padding,
                                itemCount: page.patients.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) => _PatientCard(
                                  listing: page.patients[i],
                                  onTap: () => widget
                                      .onOpenPatient(page.patients[i].patient),
                                ),
                              ),
                            ),
            ),
            if (page != null && page.total > 0)
              Centered(
                maxWidth: ContentWidth.wide + 32,
                child: _Pager(
                  query: _q,
                  total: page.total,
                  // Clear of the round "Add patient" button.
                  endPadding: canRegister && !table ? 80 : 16,
                  onPage: (p) => setState(() => _q = _q.copyWith(page: p)),
                  onPageSize: (s) => _set(_q.copyWith(pageSize: s)),
                ),
              ),
          ],
        );
      }),
    );
  }

  static String _summary(PatientPage page, bool narrowed) {
    String n(int count) => '$count patient${count == 1 ? '' : 's'}';
    final all = page.all;
    if (!narrowed || all == null) return n(page.total);
    return '${page.total} of ${n(all)}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

// ── Filters, sort, pages ────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.counts,
    required this.onToggle,
    this.onClear,
  });

  final Set<PatientFlag> selected;
  final Map<PatientFlag, int> counts;
  final void Function(PatientFlag flag) onToggle;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    // Full width, so the chips start under the search field rather than
    // centring when they all fit.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          for (final f in PatientFlag.values) ...[
            if (f == PatientFlag.pedia)
              const SizedBox(height: 24, child: VerticalDivider(width: 16)),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                avatar: Icon(f.icon, size: 16, color: remarkColor(context, f)),
                label: Text(counts[f] == null
                    ? f.label
                    : '${f.label}  ${counts[f]}'),
                selected: selected.contains(f),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onToggle(f),
              ),
            ),
          ],
          if (onClear != null)
            TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}

const _sortLabels = {
  PatientSort.name: 'Name',
  PatientSort.age: 'Age',
  PatientSort.firstVisit: 'First visit',
  PatientSort.lastVisit: 'Last visit',
  PatientSort.nextVisit: 'Next visit',
  PatientSort.visits: 'Visits',
  PatientSort.balance: 'Balance',
};

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.query, required this.onSort});

  final PatientTableQuery query;
  final void Function(PatientSort sort) onSort;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PatientSort>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      onSelected: onSort,
      itemBuilder: (_) => [
        for (final s in PatientSort.values)
          CheckedPopupMenuItem(
            value: s,
            checked: s == query.sort,
            child: Row(
              children: [
                Expanded(child: Text(_sortLabels[s]!)),
                if (s == query.sort)
                  Icon(
                      query.descending
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.query,
    required this.total,
    required this.onPage,
    required this.onPageSize,
    this.endPadding = 16,
  });

  final PatientTableQuery query;
  final int total;
  final void Function(int page) onPage;
  final void Function(int size) onPageSize;
  final double endPadding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = query.pageSize;
    final pages = (total / size).ceil();
    final page = query.page.clamp(0, pages - 1);
    final from = page * size + 1;
    final to = ((page + 1) * size).clamp(0, total);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, endPadding, 8),
      child: LayoutBuilder(builder: (context, box) {
      // Rows per page and first/last only where they fit.
      final wide = box.maxWidth >= 520;
      return Row(
        children: [
          Flexible(
            child: Text('$from–$to of $total',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          const Spacer(),
          if (wide) ...[
            Text('Rows', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: size,
              underline: const SizedBox.shrink(),
              items: [
                for (final s in const [25, 50, 100])
                  DropdownMenuItem(value: s, child: Text('$s')),
              ],
              onChanged: (s) => s == null ? null : onPageSize(s),
            ),
            const SizedBox(width: 12),
          ],
          if (wide)
            IconButton(
              tooltip: 'First page',
              onPressed: page > 0 ? () => onPage(0) : null,
              icon: const Icon(Icons.first_page),
            ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: page > 0 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${page + 1} / $pages',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'Next page',
            onPressed: page < pages - 1 ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          if (wide)
            IconButton(
              tooltip: 'Last page',
              onPressed: page < pages - 1 ? () => onPage(pages - 1) : null,
              icon: const Icon(Icons.last_page),
            ),
        ],
      );
      }),
    );
  }
}

// ── The table (tablet and up) ───────────────────────────────────────────────

String _date(DateTime? d) => d == null ? '—' : DateFormat('MMM d, y').format(d);

class _PatientTable extends StatelessWidget {
  const _PatientTable({
    required this.page,
    required this.query,
    required this.onSort,
    required this.onOpen,
  });

  final PatientPage page;
  final PatientTableQuery query;
  final void Function(PatientSort sort) onSort;
  final void Function(Patient patient) onOpen;

  /// Narrower than this (a tablet held sideways, beside the rail), the table
  /// leaves out First visit and tightens the remarks, so every column fits
  /// without scrolling sideways.
  static const double fullWidth = 1100;

  /// The sort behind each column, by index; null for one that does not sort.
  static const _columns = <(String, PatientSort?, bool)>[
    ('Patient', PatientSort.name, false),
    ('Age', PatientSort.age, true),
    ('First visit', PatientSort.firstVisit, false),
    ('Last visit', PatientSort.lastVisit, false),
    ('Next visit', PatientSort.nextVisit, false),
    ('Visits', PatientSort.visits, true),
    ('Balance', PatientSort.balance, true),
    ('Remarks', null, false),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ContentWidth.wide),
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(builder: (context, box) {
              final compact = box.maxWidth < fullWidth;
              final columns = [
                for (final c in _columns)
                  if (!(compact && c.$2 == PatientSort.firstVisit)) c,
              ];
              final sortIndex = columns.indexWhere((c) => c.$2 == query.sort);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    sortColumnIndex: sortIndex < 0 ? null : sortIndex,
                    sortAscending: !query.descending,
                    headingTextStyle: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant),
                    headingRowColor:
                        WidgetStatePropertyAll(cs.surfaceContainerHighest),
                    dataRowMinHeight: 60,
                    dataRowMaxHeight: 76,
                    horizontalMargin: 16,
                    columnSpacing: compact ? 16 : 20,
                    columns: [
                      for (final (label, sort, numeric) in columns)
                        DataColumn(
                          label: Text(label),
                          numeric: numeric,
                          onSort: sort == null ? null : (_, _) => onSort(sort),
                        ),
                    ],
                    rows: [
                      for (final l in page.patients)
                        DataRow(
                          onSelectChanged: (_) => onOpen(l.patient),
                          cells: _cells(context, l, compact: compact),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  List<DataCell> _cells(BuildContext context, PatientListing l,
      {required bool compact}) {
    final cs = Theme.of(context).colorScheme;
    final p = l.patient;
    final small = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final contact = p.phone.isNotEmpty ? p.phone : p.email;

    return [
      DataCell(SizedBox(
        width: compact ? 190 : 220,
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primaryContainer,
              child: Text(p.initials,
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                      TextSpan(text: p.name, children: [
                        if (p.chartNumber case final n?)
                          TextSpan(
                              text: '  $n',
                              style: small.copyWith(fontWeight: FontWeight.normal)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(contact.isEmpty ? 'No contact info' : contact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: contact.isEmpty
                          ? small.copyWith(
                              color: remarkColor(context, PatientFlag.noContact),
                              fontStyle: FontStyle.italic)
                          : small),
                ],
              ),
            ),
          ],
        ),
      )),
      DataCell(Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(l.age == null ? '—' : '${l.age}'),
          if (l.flags.contains(PatientFlag.pedia))
            Text('Pedia',
                style: small.copyWith(
                    color: remarkColor(context, PatientFlag.pedia))),
        ],
      )),
      if (!compact) DataCell(Text(_date(l.firstVisitAt))),
      DataCell(SizedBox(
        width: compact ? 150 : 170,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_date(l.lastVisitAt)),
            if (l.lastVisitMissed)
              Text('Missed last visit',
                  style: small.copyWith(color: cs.error))
            else if (l.lastVisitService != null)
              Text(
                  [
                    l.lastVisitService!,
                    if (l.lastVisitDoctor != null) 'Dr. ${l.lastVisitDoctor}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small),
          ],
        ),
      )),
      DataCell(Text(
        l.nextVisitAt == null ? '—' : _date(l.nextVisitAt),
        style: l.nextVisitAt == null
            ? null
            : TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
      )),
      DataCell(Text('${l.completedVisits}')),
      DataCell(Text(
        l.balance > 0 ? formatPeso(l.balance) : '—',
        style: l.balance > 0
            ? TextStyle(
                color: remarkColor(context, PatientFlag.balance),
                fontWeight: FontWeight.w700)
            : null,
      )),
      DataCell(SizedBox(
        width: compact ? 190 : 260,
        child: RemarkChips(
          flags: l.flags,
          attention: l.attention,
          dense: true,
          showAgeGroup: false,
        ),
      )),
    ];
  }
}

// ── Cards (phone) ───────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.listing, required this.onTap});

  final PatientListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = listing;
    final p = l.patient;
    final small = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Text(p.initials,
                        style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            p.name,
                            if (l.age != null) '${l.age}',
                          ].join(', '),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        Text(
                          p.phone.isNotEmpty
                              ? p.phone
                              : p.email.isNotEmpty
                                  ? p.email
                                  : 'No contact info',
                          style: small,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (l.balance > 0)
                        Text(formatPeso(l.balance),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: remarkColor(
                                    context, PatientFlag.balance))),
                      Text(
                          '${l.completedVisits} visit'
                          '${l.completedVisits == 1 ? '' : 's'}',
                          style: small),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                [
                  'Last ${_date(l.lastVisitAt)}'
                      '${l.lastVisitMissed ? ' (missed)' : ''}',
                  if (l.nextVisitAt != null) 'Next ${_date(l.nextVisitAt)}',
                  if (l.firstVisitAt != null)
                    'Since ${DateFormat('MMM y').format(l.firstVisitAt!)}',
                ].join(' · '),
                style: small,
              ),
              if (l.flags.isNotEmpty) ...[
                const SizedBox(height: 8),
                RemarkChips(flags: l.flags, attention: l.attention, dense: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The last row of a paged list: fetches the next page as soon as it scrolls
/// into view, and offers a retry if that fails.
class LoadMoreFooter extends StatefulWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.onLoadMore,
    this.error,
  });

  final bool loading;
  final Object? error;
  final VoidCallback onLoadMore;

  @override
  State<LoadMoreFooter> createState() => _LoadMoreFooterState();
}

class _LoadMoreFooterState extends State<LoadMoreFooter> {
  @override
  void initState() {
    super.initState();
    // Built means scrolled to: ask for the next page. After the frame, since
    // it changes provider state.
    if (widget.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoadMore();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    if (error != null && !widget.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(describeError(error),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 13)),
            TextButton(
                onPressed: widget.onLoadMore, child: const Text('Try again')),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
