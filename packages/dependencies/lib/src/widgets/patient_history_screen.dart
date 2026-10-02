import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/dental_chart.dart';
import '../models/invoice.dart';
import '../models/money.dart';
import '../models/patient.dart';
import '../models/patient_intake.dart';
import '../providers/audit_provider.dart';
import '../providers/billing_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/clinical_provider.dart';
import '../providers/dental_provider.dart';
import '../providers/intake_provider.dart';
import '../providers/preferences_provider.dart';
import 'async_view.dart';
import 'audit_log_view.dart';
import 'billing_widgets.dart';
import 'clinical_notes.dart';
import 'dental_chart.dart';
import 'intake_screens.dart';
import 'patient_remarks.dart';
import 'print_statement_sheet.dart';
import 'record_visit_sheet.dart';
import 'status_badge.dart';

/// One patient's record at this clinic, built for handing a patient over:
/// a doctor who has never seen them should be able to tell, from the top of
/// this page, who they are, what happened last, what is still to do, what
/// to watch out for, and what they owe.
///
/// Tabs:
///   Overview      the handover: medical alerts, the last visit in full, the
///                 treatment plan, the next visit, the balance
///   Treatments    every treatment done, visit by visit (dental clinics)
///   Appointments  every visit, upcoming and past
///   Billing       every bill, with what was paid and what is owed
///   Chart & form  the patient information form and the tooth chart
///   Changes       who changed what on this chart, and when (admins only)
///
/// Shared by the doctor, front desk and admin apps. What each sees follows
/// [canSeeClinicalNotesProvider], which mirrors the database: clinicians get
/// the medical and consultation notes, the front desk the same page without
/// them. Every staff role sees the bills.
///
/// The package has no router, so navigation belongs to the app: pass
/// [onOpenAppointment] where the app has an appointment screen, [onOpenInvoice]
/// where it has a bill screen, and [onBook] where it can book.
/// [canRecordVisits] offers to enter a visit that happened but was never
/// logged (the front desk and admins).
class PatientHistoryScreen extends ConsumerWidget {
  const PatientHistoryScreen({
    super.key,
    required this.patientId,
    this.onOpenAppointment,
    this.onOpenInvoice,
    this.onBook,
    this.canRecordVisits = false,
  });

  final String patientId;
  final void Function(Appointment appointment)? onOpenAppointment;
  final void Function(String invoiceId)? onOpenInvoice;
  final VoidCallback? onBook;
  final bool canRecordVisits;

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(patientByIdProvider(patientId))
      ..invalidate(patientHistoryProvider(patientId))
      ..invalidate(chartNoteProvider(patientId))
      ..invalidate(intakeProvider(patientId))
      ..invalidate(dentalEntriesProvider(patientId))
      ..invalidate(patientInvoicesProvider(patientId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientByIdProvider(patientId));
    final guard = asyncGuard(
      patientAsync,
      appBar: AppBar(title: const Text('Patient')),
      onRetry: () => ref.invalidate(patientByIdProvider(patientId)),
    );
    if (guard != null) return guard;

    final patient = patientAsync.requireValue;
    if (patient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient')),
        body: const Center(child: Text('Patient not found.')),
      );
    }

    final historyAsync = ref.watch(patientHistoryProvider(patientId));
    final invoicesAsync = ref.watch(patientInvoicesProvider(patientId));
    final dental = ref.watch(clinicChartsTeethProvider);
    final audited = ref.watch(canSeeAuditLogProvider);
    final chart = dental ? ref.watch(dentalChartProvider(patientId)).value : null;
    final visits = historyAsync.value;
    final invoices = invoicesAsync.value;

    final doneCount =
        chart?.entries.where((e) => e.status == DentalEntryStatus.done).length;
    final open = onOpenAppointment;
    final openInvoice = onOpenInvoice;

    // Tabs by key, so a link on one tab can open another.
    final keys = [
      'overview',
      if (dental) 'treatments',
      'appointments',
      'billing',
      'chart',
      if (audited) 'changes',
    ];

    return DefaultTabController(
      length: keys.length,
      child: Builder(builder: (context) {
        final controller = DefaultTabController.of(context);
        void showTab(String key) {
          final i = keys.indexOf(key);
          if (i >= 0) controller.animateTo(i);
        }

        final tabs = <String, (String, Widget)>{
          'overview': (
            'Overview',
            _OverviewTab(
              patient: patient,
              onOpenAppointment: open,
              onShowTab: showTab,
            ),
          ),
          'treatments': (
            doneCount == null ? 'Treatments' : 'Treatments ($doneCount)',
            _TreatmentsTab(patient: patient, onOpenAppointment: open),
          ),
          'appointments': (
            visits == null ? 'Appointments' : 'Appointments (${visits.length})',
            _AppointmentsTab(
              patient: patient,
              onOpenAppointment: open,
              canRecordVisits: canRecordVisits,
            ),
          ),
          'billing': (
            invoices == null ? 'Billing' : 'Billing (${invoices.length})',
            _BillingTab(patient: patient, onOpenInvoice: openInvoice),
          ),
          'chart': (
            dental ? 'Chart & form' : 'Information form',
            _ChartTab(patient: patient),
          ),
          'changes': ('Changes', AuditLogView(patientId: patient.id)),
        };

        return Scaffold(
          appBar: AppBar(
            title: Text(patient.name),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => _refresh(ref),
              ),
            ],
          ),
          floatingActionButton: onBook == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: onBook,
                  icon: const Icon(Icons.event_available),
                  label: const Text('Book visit'),
                ),
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverCentered(
                maxWidth: ContentWidth.detail,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _PatientHeader(
                    patient: patient,
                    visits: visits,
                    invoices: invoices,
                    plannedCount: chart?.plan.length ?? 0,
                    onShowTab: showTab,
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarHeader(
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [for (final k in keys) Tab(text: tabs[k]!.$1)],
                  ),
                  Theme.of(context).colorScheme.surface,
                ),
              ),
            ],
            body: TabBarView(
              children: [for (final k in keys) tabs[k]!.$2],
            ),
          ),
        );
      }),
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar, this.background);

  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height + 1;
  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: background,
      child: Column(
        children: [
          Centered(maxWidth: ContentWidth.detail, child: tabBar),
          const Divider(height: 1),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarHeader old) =>
      old.tabBar != tabBar || old.background != background;
}

/// A tab's content: centred, scrolling inside the page's [NestedScrollView].
class _TabList extends StatelessWidget {
  const _TabList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CenteredScroll(
      maxWidth: ContentWidth.detail,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      builder: (padding) => ListView(padding: padding, children: children),
    );
  }
}

String _date(DateTime d) => DateFormat('MMM d, y').format(d);

/// "3 months ago", "in 2 weeks", "today".
String _relative(DateTime d, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final day = DateTime(d.year, d.month, d.day);
  final days = day.difference(today).inDays;
  if (days == 0) return 'today';
  if (days == -1) return 'yesterday';
  if (days == 1) return 'tomorrow';
  final n = days.abs();
  final (count, unit) = n < 14
      ? (n, 'day')
      : n < 60
          ? (n ~/ 7, 'week')
          : n < 730
              ? (n ~/ 30, 'month')
              : (n ~/ 365, 'year');
  final text = '$count $unit${count == 1 ? '' : 's'}';
  return days < 0 ? '$text ago' : 'in $text';
}

// ── Header: who, remarks, the numbers ───────────────────────────────────────

class _PatientHeader extends ConsumerWidget {
  const _PatientHeader({
    required this.patient,
    required this.visits,
    required this.invoices,
    required this.plannedCount,
    required this.onShowTab,
  });

  final Patient patient;

  /// Null while still loading; what depends on them waits.
  final List<Appointment>? visits;
  final List<Invoice>? invoices;
  final int plannedCount;
  final void Function(String tab) onShowTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final dob = patient.dateOfBirth;
    final all = visits;
    final bills = invoices;
    final recallMonths =
        ref.watch(currentClinicProvider).value?.recallMonths ?? 6;
    final remarks = all == null || bills == null
        ? null
        : patientRemarks(
            patient: patient,
            visits: all,
            invoices: bills,
            plannedCount: plannedCount,
            recallMonths: recallMonths,
          );

    final details = [
      if (patient.chartNumber case final n?) (Icons.folder_outlined, 'Chart no. $n'),
      if (patient.phone.isNotEmpty) (Icons.phone_outlined, patient.phone),
      if (patient.email.isNotEmpty) (Icons.email_outlined, patient.email),
      if (dob != null)
        (
          Icons.cake_outlined,
          'Age ${patient.age} · born ${_date(dob)}'
              '${patient.sex == null ? '' : ' · ${patient.sex!.label}'}',
        ),
      if (patient.address case final a? when a.trim().isNotEmpty)
        (Icons.place_outlined, a),
      if (patient.emergencyContactName case final n? when n.trim().isNotEmpty)
        (
          Icons.contact_emergency_outlined,
          'Emergency: $n'
              '${patient.emergencyContactPhone == null ? '' : ' · ${patient.emergencyContactPhone}'}',
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: cs.primaryContainer,
                child: Text(patient.initials,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    if (details.isEmpty)
                      _DetailLine(
                          icon: Icons.info_outline,
                          text: 'No contact details on file'),
                    // Two columns of details once there is room.
                    CardColumns(
                      minItemWidth: 280,
                      maxColumns: 2,
                      spacing: 12,
                      runSpacing: 0,
                      children: [
                        for (final (icon, text) in details)
                          _DetailLine(icon: icon, text: text),
                      ],
                    ),
                    if (remarks != null && remarks.flags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      RemarkChips(
                          flags: remarks.flags, attention: remarks.attention),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (all != null) ...[
            const SizedBox(height: 16),
            _Stats(
              visits: all,
              invoices: bills,
              onShowTab: onShowTab,
            ),
          ],
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({
    required this.visits,
    required this.invoices,
    required this.onShowTab,
  });

  /// Newest first, as the history provider returns them.
  final List<Appointment> visits;
  final List<Invoice>? invoices;
  final void Function(String tab) onShowTab;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final completed =
        visits.where((a) => a.status == AppointmentStatus.completed).toList();
    final upcoming = visits
        .where((a) => a.dateTime.isAfter(now) && a.status.holdsTime)
        .toList();
    final next = upcoming.isEmpty ? null : upcoming.last.dateTime;
    final first = completed.isEmpty ? null : completed.last.dateTime;
    final last = completed.isEmpty ? null : completed.first.dateTime;
    final bills = invoices;
    final owed = bills
        ?.where((v) => v.status == InvoiceStatus.issued)
        .fold<double>(0, (sum, v) => sum + v.balance);

    final stats = [
      _Stat(
          label: 'First visit',
          value: first == null ? '—' : _date(first),
          onTap: () => onShowTab('appointments')),
      _Stat(
          label: 'Last visit',
          value: last == null ? '—' : _date(last),
          caption: last == null ? null : _relative(last),
          onTap: () => onShowTab('appointments')),
      _Stat(
          label: 'Next visit',
          value: next == null ? 'None booked' : _date(next),
          caption: next == null ? null : _relative(next),
          onTap: () => onShowTab('appointments')),
      _Stat(
          label: 'Visits',
          value: '${completed.length}',
          onTap: () => onShowTab('appointments')),
      _Stat(
          label: 'Balance',
          value: owed == null ? '…' : (owed > 0 ? formatPeso(owed) : 'None'),
          color: (owed ?? 0) > 0
              ? remarkColor(context, PatientFlag.balance)
              : null,
          onTap: () => onShowTab('billing')),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: CardColumns(
        minItemWidth: 120,
        maxColumns: 5,
        spacing: 0,
        runSpacing: 0,
        children: stats,
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.caption,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color ?? cs.primary)),
            Text(caption == null ? label : '$label · $caption',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ── Overview: the handover ──────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({
    required this.patient,
    required this.onShowTab,
    this.onOpenAppointment,
  });

  final Patient patient;
  final void Function(String tab) onShowTab;
  final void Function(Appointment appointment)? onOpenAppointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(patientHistoryProvider(patient.id));
    final showClinical = ref.watch(canSeeClinicalNotesProvider).value ?? false;

    return _TabList(children: [
      AsyncView(
        value: historyAsync,
        onRetry: () => ref.invalidate(patientHistoryProvider(patient.id)),
        builder: (visits) {
          final now = DateTime.now();
          final over = [
            for (final a in visits)
              if (!a.dateTime.isAfter(now) &&
                  (a.status == AppointmentStatus.completed ||
                      a.status == AppointmentStatus.noShow))
                a,
          ];
          final lastVisit = over.isEmpty ? null : over.first;
          final upcoming = [
            for (final a in visits)
              if (a.dateTime.isAfter(now) && a.status.holdsTime) a,
          ].reversed.toList();
          final open = onOpenAppointment;

          return SplitColumns(
            start: [
              const _SectionTitle('Last visit'),
              if (lastVisit == null)
                const _Muted('No visit completed at this clinic yet.')
              else
                _LastVisitCard(
                  appointment: lastVisit,
                  showClinical: showClinical,
                  onTap: open == null ? null : () => open(lastVisit),
                ),
              _TreatmentPlan(patient: patient, upcoming: upcoming),
              const _SectionTitle('Next visit'),
              if (upcoming.isEmpty)
                const _Muted('Nothing booked.')
              else
                for (final a in upcoming.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: VisitTile(
                      appointment: a,
                      onTap: open == null ? null : () => open(a),
                    ),
                  ),
              if (over.length > 1) ...[
                Row(
                  children: [
                    const Expanded(child: _SectionTitle('Before that')),
                    TextButton(
                      onPressed: () => onShowTab('appointments'),
                      child: const Text('All appointments'),
                    ),
                  ],
                ),
                for (final a in over.skip(1).take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: VisitTile(
                      appointment: a,
                      showClinical: showClinical,
                      onTap: open == null ? null : () => open(a),
                    ),
                  ),
              ],
            ],
            end: [
              _MedicalAlerts(patientId: patient.id, onShowTab: onShowTab),
              ChartNoteSection(patient: patient),
              _BalanceCard(patientId: patient.id, onShowTab: onShowTab),
            ],
            // On a phone: what to watch out for before the history.
            narrow: [
              _MedicalAlerts(patientId: patient.id, onShowTab: onShowTab),
              const _SectionTitle('Last visit'),
              if (lastVisit == null)
                const _Muted('No visit completed at this clinic yet.')
              else
                _LastVisitCard(
                  appointment: lastVisit,
                  showClinical: showClinical,
                  onTap: open == null ? null : () => open(lastVisit),
                ),
              _TreatmentPlan(patient: patient, upcoming: upcoming),
              const _SectionTitle('Next visit'),
              if (upcoming.isEmpty)
                const _Muted('Nothing booked.')
              else
                for (final a in upcoming.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: VisitTile(
                      appointment: a,
                      onTap: open == null ? null : () => open(a),
                    ),
                  ),
              const SizedBox(height: 8),
              ChartNoteSection(patient: patient),
              _BalanceCard(patientId: patient.id, onShowTab: onShowTab),
            ],
          );
        },
      ),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(text,
          style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    );
  }
}

/// The last visit in full: who, what, the consultation note, the note to the
/// patient, and every tooth touched.
class _LastVisitCard extends ConsumerWidget {
  const _LastVisitCard({
    required this.appointment,
    required this.showClinical,
    this.onTap,
  });

  final Appointment appointment;
  final bool showClinical;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final a = appointment;
    final missed = a.status == AppointmentStatus.noShow;
    final note = a.visitNote;
    final chart = ref.watch(clinicChartsTeethProvider)
        ? ref.watch(dentalChartProvider(a.patient.id)).value
        : null;
    final entries = chart?.atVisit(a.id) ?? const <DentalEntry>[];
    final numbering = ref.watch(toothNumberingProvider);

    List<DentalEntry> having(DentalEntryStatus s) =>
        [for (final e in entries) if (e.status == s) e];
    final groups = [
      ('Done', having(DentalEntryStatus.done)),
      ('Found', having(DentalEntryStatus.existing)),
      ('Planned', having(DentalEntryStatus.planned)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(a.service,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    StatusBadge(status: a.status, small: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_date(a.dateTime)} (${_relative(a.dateTime)}) · '
                  'Dr. ${a.doctor.name}',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                if (missed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('The patient did not come to this visit.',
                        style: TextStyle(color: cs.error)),
                  ),
                if (showClinical) ...[
                  const SizedBox(height: 12),
                  _LabeledText(
                    icon: Icons.assignment_outlined,
                    label: 'Consultation note',
                    text: note?.body,
                    empty: 'No consultation note written.',
                  ),
                ],
                if (a.patientNote case final pn?) ...[
                  const SizedBox(height: 10),
                  _LabeledText(
                    icon: Icons.chat_bubble_outline,
                    label: 'Note to the patient',
                    text: pn,
                  ),
                ],
                for (final (title, list) in groups)
                  if (list.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(title,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant)),
                    for (final e in list)
                      DentalEntryTile(entry: e, numbering: numbering),
                  ],
                if (onTap != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('Open visit ›',
                        style: TextStyle(
                            color: cs.primary, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({
    required this.icon,
    required this.label,
    required this.text,
    this.empty,
  });

  final IconData icon;
  final String label;
  final String? text;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              Text(body ?? empty ?? '',
                  style: body == null
                      ? TextStyle(color: cs.outline, fontStyle: FontStyle.italic)
                      : null),
            ],
          ),
        ),
      ],
    );
  }
}

/// What is planned and not done yet, and whether it is booked. Dental.
class _TreatmentPlan extends ConsumerWidget {
  const _TreatmentPlan({required this.patient, required this.upcoming});

  final Patient patient;
  final List<Appointment> upcoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(clinicChartsTeethProvider)) return const SizedBox.shrink();
    final chart = ref.watch(dentalChartProvider(patient.id)).value;
    if (chart == null) return const SizedBox.shrink();
    final plan = chart.plan;
    final numbering = ref.watch(toothNumberingProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Treatment plan${plan.isEmpty ? '' : ' (${plan.length})'}'),
        if (plan.isEmpty)
          const _Muted('Nothing planned.')
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (upcoming.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 16, color: cs.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Not booked yet',
                                  style: TextStyle(
                                      color: cs.error,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    for (final e in plan)
                      DentalEntryTile(entry: e, numbering: numbering),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Allergies, conditions, medicines and the like from the information form,
/// on top because they change what anyone may do.
class _MedicalAlerts extends ConsumerWidget {
  const _MedicalAlerts({required this.patientId, required this.onShowTab});

  final String patientId;
  final void Function(String tab) onShowTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final intakeAsync = ref.watch(intakeProvider(patientId));
    final intake = intakeAsync.value;
    if (intakeAsync.isLoading && intake == null) return const SizedBox.shrink();

    if (intake == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.assignment_late_outlined, color: cs.outline),
            title: const Text('No information form on file'),
            subtitle: const Text('Allergies and conditions are unknown.'),
            trailing: TextButton(
              onPressed: () => onShowTab('chart'),
              child: const Text('Fill in'),
            ),
          ),
        ),
      );
    }

    final lines = _alertLines(intake);
    final alert = lines.isNotEmpty;
    final color = alert ? cs.error : cs.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: alert ? cs.errorContainer.withAlpha(90) : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(alert ? 90 : 40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    alert
                        ? Icons.medical_information
                        : Icons.verified_user_outlined,
                    size: 18,
                    color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(alert ? 'Medical alerts' : 'No medical alerts',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: color)),
                ),
                Text('Form ${_date(intake.updatedAt)}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
            for (final (label, text) in lines)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                          text: '$label: ',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: text),
                    ],
                  ),
                ),
              ),
            if (!alert)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'No allergies, conditions or medicines declared.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }

  static List<(String, String)> _alertLines(PatientIntake i) {
    String join(List<String> labels, String? other) =>
        [...labels, if (other != null && other.trim().isNotEmpty) other.trim()]
            .join(', ');
    final allergies = join(i.allergyLabels, i.allergiesOther);
    final conditions = join(i.conditionLabels, i.conditionsOther);
    return [
      if (allergies.isNotEmpty) ('Allergies', allergies),
      if (conditions.isNotEmpty) ('Conditions', conditions),
      if (i.takesMedications)
        ('Medicines', (i.medications ?? '').trim().isEmpty ? 'Yes, not listed' : i.medications!.trim()),
      if (i.underTreatment)
        ('Under treatment',
            (i.treatmentDetails ?? '').trim().isEmpty ? 'Yes' : i.treatmentDetails!.trim()),
      if (i.pregnant == true) ('Pregnant', 'Yes'),
      if (i.nursing == true) ('Nursing', 'Yes'),
    ];
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.patientId, required this.onShowTab});

  final String patientId;
  final void Function(String tab) onShowTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(patientInvoicesProvider(patientId)).value;
    if (bills == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final open = [
      for (final v in bills)
        if (v.status == InvoiceStatus.issued && v.balance > 0) v,
    ];
    final owed = open.fold<double>(0, (s, v) => s + v.balance);
    final drafts = bills.where((v) => v.isDraft).length;
    final color = owed > 0 ? remarkColor(context, PatientFlag.balance) : cs.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: () => onShowTab('billing'),
          leading: Icon(Icons.account_balance_wallet_outlined, color: color),
          title: Text(owed > 0 ? '${formatPeso(owed)} owed' : 'Nothing owed',
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          subtitle: Text([
            if (open.isNotEmpty)
              '${open.length} unpaid bill${open.length == 1 ? '' : 's'}',
            if (drafts > 0) '$drafts draft${drafts == 1 ? '' : 's'} not issued',
            if (open.isEmpty && drafts == 0) '${bills.length} bill${bills.length == 1 ? '' : 's'} on file',
          ].join(' · ')),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

// ── Treatments done (dental) ────────────────────────────────────────────────

/// Every treatment done, grouped by the visit it was done at, newest first.
class _TreatmentsTab extends ConsumerWidget {
  const _TreatmentsTab({required this.patient, this.onOpenAppointment});

  final Patient patient;
  final void Function(Appointment appointment)? onOpenAppointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final chartAsync = ref.watch(dentalChartProvider(patient.id));
    final visits = ref.watch(patientHistoryProvider(patient.id)).value ?? const [];
    final numbering = ref.watch(toothNumberingProvider);
    final showClinical = ref.watch(canSeeClinicalNotesProvider).value ?? false;
    final byId = {for (final a in visits) a.id: a};

    return _TabList(children: [
      AsyncView(
        value: chartAsync,
        onRetry: () => ref.invalidate(dentalEntriesProvider(patient.id)),
        builder: (chart) {
          final done = [
            for (final e in chart.entries)
              if (e.status == DentalEntryStatus.done) e,
          ];
          if (done.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: _Muted('No treatment recorded as done yet.')),
            );
          }
          // Visit by visit. A treatment done always names its visit; one
          // whose visit was deleted is kept under "Visit not on file".
          final groups = <String?, List<DentalEntry>>{};
          for (final e in done) {
            groups.putIfAbsent(e.appointmentId, () => []).add(e);
          }
          DateTime when(String? id, List<DentalEntry> list) =>
              byId[id]?.dateTime ??
              list.map((e) => e.updatedAt ?? e.createdAt ?? DateTime(1970))
                  .reduce((a, b) => a.isAfter(b) ? a : b);
          final ordered = groups.entries.toList()
            ..sort((a, b) => when(b.key, b.value).compareTo(when(a.key, a.value)));
          final open = onOpenAppointment;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${done.length} treatment${done.length == 1 ? '' : 's'} '
                'over ${ordered.length} visit${ordered.length == 1 ? '' : 's'}',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final g in ordered)
                _TreatmentVisit(
                  visit: byId[g.key],
                  entries: g.value..sort((a, b) => a.tooth.compareTo(b.tooth)),
                  date: when(g.key, g.value),
                  numbering: numbering,
                  showClinical: showClinical,
                  onTap: byId[g.key] == null || open == null
                      ? null
                      : () => open(byId[g.key]!),
                ),
            ],
          );
        },
      ),
    ]);
  }
}

class _TreatmentVisit extends StatelessWidget {
  const _TreatmentVisit({
    required this.visit,
    required this.entries,
    required this.date,
    required this.numbering,
    required this.showClinical,
    this.onTap,
  });

  final Appointment? visit;
  final List<DentalEntry> entries;
  final DateTime date;
  final ToothNumbering numbering;
  final bool showClinical;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = visit;
    final note = v?.visitNote;

    // A timeline: a dot per visit, joined by a line.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 18),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(width: 2, color: cs.outlineVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                v == null
                                    ? 'Visit not on file'
                                    : '${_date(date)} · ${v.service}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (onTap != null)
                              Icon(Icons.chevron_right, color: cs.outline),
                          ],
                        ),
                        if (v != null)
                          Text('Dr. ${v.doctor.name} · ${_relative(date)}',
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant)),
                        for (final e in entries)
                          DentalEntryTile(entry: e, numbering: numbering),
                        if (showClinical && note != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 4),
                            child: _NoteLine(
                                icon: Icons.assignment_outlined,
                                text: note.body),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Appointments ────────────────────────────────────────────────────────────

class _AppointmentsTab extends ConsumerWidget {
  const _AppointmentsTab({
    required this.patient,
    required this.canRecordVisits,
    this.onOpenAppointment,
  });

  final Patient patient;
  final bool canRecordVisits;
  final void Function(Appointment appointment)? onOpenAppointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(patientHistoryProvider(patient.id));
    final showClinical = ref.watch(canSeeClinicalNotesProvider).value ?? false;
    return _TabList(children: [
      AsyncView(
        value: historyAsync,
        onRetry: () => ref.invalidate(patientHistoryProvider(patient.id)),
        builder: (visits) => _Visits(
          visits: visits,
          showClinical: showClinical,
          onOpen: onOpenAppointment,
          onRecord: canRecordVisits
              ? () => showRecordVisitSheet(context, patient: patient)
              : null,
        ),
      ),
    ]);
  }
}

// ── Billing ─────────────────────────────────────────────────────────────────

class _BillingTab extends ConsumerWidget {
  const _BillingTab({required this.patient, this.onOpenInvoice});

  final Patient patient;
  final void Function(String invoiceId)? onOpenInvoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final patientId = patient.id;
    final billsAsync = ref.watch(patientInvoicesProvider(patientId));
    final open = onOpenInvoice;

    return _TabList(children: [
      AsyncView(
        value: billsAsync,
        onRetry: () => ref.invalidate(patientInvoicesProvider(patientId)),
        builder: (bills) {
          if (bills.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: _Muted('No bills yet.')),
            );
          }
          final counted = [
            for (final v in bills)
              if (v.status == InvoiceStatus.issued ||
                  v.status == InvoiceStatus.paid)
                v,
          ];
          final billed = counted.fold<double>(0, (s, v) => s + v.total);
          final paid = counted.fold<double>(0, (s, v) => s + v.amountPaid);
          final owed = counted.fold<double>(0, (s, v) => s + v.balance);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(child: _Stat(label: 'Billed', value: formatPeso(billed))),
                    Expanded(child: _Stat(label: 'Paid', value: formatPeso(paid))),
                    Expanded(
                      child: _Stat(
                        label: 'Balance',
                        value: owed > 0 ? formatPeso(owed) : 'None',
                        color: owed > 0
                            ? remarkColor(context, PatientFlag.balance)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Drafts and voided bills are not counted.',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                    TextButton.icon(
                      onPressed: () => showPrintStatementSheet(context,
                          patient: patient, invoices: bills),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print statement'),
                    ),
                  ],
                ),
              ),
              for (final v in bills)
                InvoiceTile(
                  invoice: v,
                  onTap: open == null ? null : () => open(v.id),
                ),
            ],
          );
        },
      ),
    ]);
  }
}

// ── Chart & form ────────────────────────────────────────────────────────────

class _ChartTab extends StatelessWidget {
  const _ChartTab({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    return _TabList(children: [
      IntakeSection(patient: patient),
      DentalChartSection(patient: patient),
    ]);
  }
}

/// A patient's visits before [appointment], for the doctor to glance at during
/// the consult: the latest few, and a link to the whole history.
///
/// Only on a visit still open. On one that is over it would chain: an old
/// visit listing older ones, each listing older still, every tap a page
/// deeper. The full history is the place to browse those.
class PreviousVisitsSection extends ConsumerWidget {
  const PreviousVisitsSection({
    super.key,
    required this.appointment,
    this.limit = 3,
    this.onOpenHistory,
    this.onOpenAppointment,
  });

  final Appointment appointment;
  final int limit;
  final VoidCallback? onOpenHistory;
  final void Function(Appointment appointment)? onOpenAppointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!appointment.status.isOpen) return const SizedBox.shrink();
    final patientId = appointment.patient.id;
    final historyAsync = ref.watch(patientHistoryProvider(patientId));
    final showClinical = ref.watch(canSeeClinicalNotesProvider).value ?? false;
    final cs = Theme.of(context).colorScheme;
    final open = onOpenAppointment;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Previous visits',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontSize: 12)),
              const Spacer(),
              if (onOpenHistory != null)
                TextButton(
                    onPressed: onOpenHistory,
                    child: const Text('Full history')),
            ],
          ),
          AsyncView(
            value: historyAsync,
            onRetry: () => ref.invalidate(patientHistoryProvider(patientId)),
            builder: (visits) {
              final earlier = visits
                  .where((a) =>
                      a.id != appointment.id &&
                      a.dateTime.isBefore(appointment.dateTime) &&
                      a.status.holdsTime)
                  .take(limit)
                  .toList();
              if (earlier.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No earlier visits at this clinic.',
                      style: TextStyle(color: cs.outline)),
                );
              }
              return Column(
                children: [
                  for (final a in earlier)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: VisitTile(
                        appointment: a,
                        showClinical: showClinical,
                        onTap: open == null ? null : () => open(a),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One appointment in a patient's history.
///
/// With [showClinical] it also shows the consultation note — pass true only
/// for a clinician, and only for an appointment fetched with its visit note.
class VisitTile extends StatelessWidget {
  const VisitTile({
    super.key,
    required this.appointment,
    this.showClinical = false,
    this.onTap,
  });

  final Appointment appointment;
  final bool showClinical;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = appointment;
    final visitNote = a.visitNote;
    final patientNote = a.patientNote;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateBlock(date: a.dateTime),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(a.service,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                        StatusBadge(status: a.status, small: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Dr. ${a.doctor.name} · '
                      '${DateFormat('h:mm a').format(a.dateTime)}',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                    if (showClinical && visitNote != null)
                      _NoteLine(
                          icon: Icons.assignment_outlined,
                          text: visitNote.body),
                    if (patientNote != null)
                      _NoteLine(
                          icon: Icons.chat_bubble_outline, text: patientNote),
                    VisitDentalLine(
                        patientId: a.patient.id, appointmentId: a.id),
                  ],
                ),
              ),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 8),
                  child: Icon(Icons.chevron_right, color: cs.outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Visits extends StatelessWidget {
  const _Visits({
    required this.visits,
    required this.showClinical,
    this.onOpen,
    this.onRecord,
  });

  /// Newest first.
  final List<Appointment> visits;
  final bool showClinical;
  final void Function(Appointment appointment)? onOpen;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final open = onOpen;

    bool isUpcoming(Appointment a) =>
        a.dateTime.isAfter(now) && a.status.holdsTime;
    final upcoming = visits.where(isUpcoming).toList().reversed.toList();
    final past = visits.where((a) => !isUpcoming(a)).toList();
    final missed =
        past.where((a) => a.status == AppointmentStatus.noShow).length;
    final cancelled =
        past.where((a) => a.status == AppointmentStatus.cancelled).length;

    Widget tile(Appointment a) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: VisitTile(
            appointment: a,
            showClinical: showClinical,
            onTap: open == null ? null : () => open(a),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (upcoming.isNotEmpty) ...[
          const _Heading('Upcoming'),
          ...upcoming.map(tile),
        ],
        Row(
          children: [
            const Expanded(child: _Heading('Visit history')),
            if (onRecord != null)
              TextButton.icon(
                onPressed: onRecord,
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Manually add visit'),
              ),
          ],
        ),
        if (missed > 0 || cancelled > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              [
                if (missed > 0) '$missed missed',
                if (cancelled > 0) '$cancelled cancelled',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        if (past.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No past visits yet.',
                style: TextStyle(color: cs.outline)),
          )
        else
          ...past.map(tile),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(color: cs.onPrimaryContainer);
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(DateFormat('MMM').format(date),
              style: style.copyWith(fontSize: 11)),
          Text('${date.day}',
              style: style.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('${date.year}', style: style.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: cs.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
