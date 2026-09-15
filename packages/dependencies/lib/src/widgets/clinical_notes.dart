import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import '../models/patient.dart';
import '../providers/appointments_provider.dart';
import '../providers/clinical_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';

/// The chart's standing medical note. Clinicians only; renders nothing for
/// anyone else.
class ChartNoteSection extends ConsumerWidget {
  const ChartNoteSection({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(canSeeClinicalNotesProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final note = ref.watch(chartNoteProvider(patient.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NoteCard(
        title: 'Medical notes',
        icon: Icons.medical_information_outlined,
        caption: 'Allergies and conditions every visit should know about. '
            'Doctors and admins only.',
        hint: 'e.g. Allergic to latex',
        emptyText: 'Nothing on file.',
        value: note.whenData((n) => n?.body),
        updatedAt: note.value?.updatedAt,
        onRetry: () => ref.invalidate(chartNoteProvider(patient.id)),
        onSave: (body) async {
          // Read the container up front: the widget may be gone by the time
          // the write returns, and the cache still has to be refreshed.
          final container = ProviderScope.containerOf(context, listen: false);
          await container.read(healthRepositoryProvider).saveChartNote(
              patientId: patient.id, clinicId: patient.clinicId, body: body);
          container.invalidate(chartNoteProvider(patient.id));
        },
      ),
    );
  }
}

/// The consultation note on one appointment. Clinicians only.
class VisitNoteSection extends ConsumerWidget {
  const VisitNoteSection({super.key, required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(canSeeClinicalNotesProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final note = ref.watch(visitNoteProvider(appointment.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NoteCard(
        title: 'Consultation notes',
        icon: Icons.assignment_outlined,
        caption: 'Doctors and admins only. The patient never sees these.',
        hint: 'Findings, treatment, follow-up…',
        emptyText: 'No consultation notes yet.',
        value: note.whenData((n) => n?.body),
        updatedAt: note.value?.updatedAt,
        onRetry: () => ref.invalidate(visitNoteProvider(appointment.id)),
        onSave: (body) async {
          final container = ProviderScope.containerOf(context, listen: false);
          await container.read(healthRepositoryProvider).saveVisitNote(
              appointmentId: appointment.id,
              clinicId: appointment.clinicId,
              body: body);
          container
            ..invalidate(visitNoteProvider(appointment.id))
            ..invalidate(patientHistoryProvider(appointment.patient.id));
        },
      ),
    );
  }
}

/// What the doctor wants the patient to read about this visit.
///
/// Clinicians can edit it. Other staff see it read-only when there is one —
/// it is not clinical, and the front desk may be asked about it.
class PatientNoteSection extends ConsumerWidget {
  const PatientNoteSection({super.key, required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(canSeeClinicalNotesProvider).value ?? false;
    final note = appointment.patientNote;
    if (!canWrite && note == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NoteCard(
        title: 'Note to patient',
        icon: Icons.chat_bubble_outline,
        caption: 'The patient sees this in their app.',
        hint: 'Aftercare, instructions, what to bring next time…',
        emptyText: 'No note for the patient.',
        value: AsyncValue.data(note),
        onSave: !canWrite
            ? null
            : (body) async {
                final container =
                    ProviderScope.containerOf(context, listen: false);
                await container
                    .read(appointmentsProvider.notifier)
                    .updatePatientNote(appointment.id, body);
                container.invalidate(
                    patientHistoryProvider(appointment.patient.id));
              },
      ),
    );
  }
}

/// A titled note with an Edit → Save flow, for a value that may still be
/// loading or may have failed.
class NoteCard extends StatefulWidget {
  const NoteCard({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    this.caption,
    this.hint,
    this.emptyText = 'No notes yet.',
    this.updatedAt,
    this.onSave,
    this.onRetry,
  });

  final String title;
  final IconData icon;

  /// The note text. Null or blank means there is none.
  final AsyncValue<String?> value;
  final String? caption;
  final String? hint;
  final String emptyText;
  final DateTime? updatedAt;

  /// Receives the trimmed text; an empty string clears the note. Null makes
  /// the card read-only.
  final Future<void> Function(String body)? onSave;
  final VoidCallback? onRetry;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  final _ctrl = TextEditingController();
  bool _editing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final onSave = widget.onSave;
    if (onSave == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await onSave(_ctrl.text.trim());
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = widget.value;
    final text = value.value?.trim() ?? '';
    final hasText = text.isNotEmpty;
    final updatedAt = widget.updatedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(widget.title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontSize: 12)),
              const Spacer(),
              if (widget.onSave != null && value.hasValue)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _editing = !_editing;
                            _error = null;
                            if (_editing) _ctrl.text = text;
                          }),
                  icon: Icon(_editing ? Icons.close : Icons.edit_outlined,
                      size: 16),
                  label: Text(_editing ? 'Cancel' : (hasText ? 'Edit' : 'Add')),
                ),
            ],
          ),
          if (widget.caption != null)
            Text(widget.caption!,
                style: TextStyle(fontSize: 11, color: cs.outline)),
          const SizedBox(height: 8),
          if (!value.hasValue && value.hasError)
            Row(
              children: [
                Expanded(
                  child: Text(describeError(value.error!),
                      style: TextStyle(color: cs.error, fontSize: 13)),
                ),
                if (widget.onRetry != null)
                  TextButton(
                      onPressed: widget.onRetry, child: const Text('Retry')),
              ],
            )
          else if (!value.hasValue)
            const LinearProgressIndicator(minHeight: 2)
          else if (_editing) ...[
            TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: widget.hint),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ] else ...[
            Text(
              hasText ? text : widget.emptyText,
              style: TextStyle(color: hasText ? cs.onSurface : cs.outline),
            ),
            if (hasText && updatedAt != null) ...[
              const SizedBox(height: 6),
              Text('Updated ${DateFormat('MMM d, y').format(updatedAt)}',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
            ],
          ],
        ],
      ),
    );
  }
}
