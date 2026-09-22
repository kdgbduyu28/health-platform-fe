import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/patient.dart';
import '../providers/clinical_provider.dart';
import 'async_view.dart';
import 'clinical_notes.dart';
import 'status_badge.dart';

/// One patient's record at this clinic: who they are, what is on file, and
/// every visit.
///
/// Shared by the doctor, front desk and admin apps. What each sees follows
/// [canSeeClinicalNotesProvider], which mirrors the database: clinicians get
/// the medical and consultation notes, the front desk gets the same page
/// without them.
///
/// The package has no router, so navigation belongs to the app: pass
/// [onOpenAppointment] where the app has an appointment screen, and [onBook]
/// where it can book.
class PatientHistoryScreen extends ConsumerWidget {
  const PatientHistoryScreen({
    super.key,
    required this.patientId,
    this.onOpenAppointment,
    this.onBook,
  });

  final String patientId;
  final void Function(Appointment appointment)? onOpenAppointment;
  final VoidCallback? onBook;

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
    final showClinical = ref.watch(canSeeClinicalNotesProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(patient.name)),
      floatingActionButton: onBook == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onBook,
              icon: const Icon(Icons.event_available),
              label: const Text('Book visit'),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(patientByIdProvider(patientId))
            ..invalidate(patientHistoryProvider(patientId))
            ..invalidate(chartNoteProvider(patientId));
          await ref.read(patientHistoryProvider(patientId).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _PatientHeader(patient: patient, history: historyAsync.value),
            const SizedBox(height: 12),
            ChartNoteSection(patient: patient),
            AsyncView(
              value: historyAsync,
              onRetry: () => ref.invalidate(patientHistoryProvider(patientId)),
              builder: (visits) => _Visits(
                visits: visits,
                showClinical: showClinical,
                onOpen: onOpenAppointment,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A patient's visits before [appointment], for the doctor to glance at during
/// the consult: the latest few, and a link to the whole history.
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

class _PatientHeader extends StatelessWidget {
  const _PatientHeader({required this.patient, required this.history});

  final Patient patient;

  /// Null while the history is still loading; the stats wait for it.
  final List<Appointment>? history;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dob = patient.dateOfBirth;
    final visits = history;

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
                    if (patient.phone.isNotEmpty)
                      _DetailLine(icon: Icons.phone_outlined, text: patient.phone),
                    if (patient.email.isNotEmpty)
                      _DetailLine(icon: Icons.email_outlined, text: patient.email),
                    if (dob != null)
                      _DetailLine(
                        icon: Icons.cake_outlined,
                        text: 'Age ${patient.age} · born '
                            '${DateFormat('MMM d, y').format(dob)}',
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (visits != null) ...[
            const SizedBox(height: 16),
            _Stats(visits: visits),
          ],
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.visits});

  /// Newest first, as the history provider returns them.
  final List<Appointment> visits;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final completed =
        visits.where((a) => a.status == AppointmentStatus.completed).toList();
    final upcoming = visits
        .where((a) =>
            a.dateTime.isAfter(now) && a.status.holdsTime)
        .length;
    final last = completed.isEmpty ? null : completed.first.dateTime;

    return Row(
      children: [
        _Stat(label: 'Visits', value: '${completed.length}'),
        _Stat(label: 'Upcoming', value: '$upcoming'),
        _Stat(
          label: 'Last visit',
          value: last == null ? '—' : DateFormat('MMM d, y').format(last),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: cs.primary)),
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Visits extends StatelessWidget {
  const _Visits({required this.visits, required this.showClinical, this.onOpen});

  /// Newest first.
  final List<Appointment> visits;
  final bool showClinical;
  final void Function(Appointment appointment)? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final open = onOpen;

    bool isUpcoming(Appointment a) =>
        a.dateTime.isAfter(now) && a.status.holdsTime;
    final upcoming = visits.where(isUpcoming).toList().reversed.toList();
    final past = visits.where((a) => !isUpcoming(a)).toList();

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
        const _Heading('Visit history'),
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
